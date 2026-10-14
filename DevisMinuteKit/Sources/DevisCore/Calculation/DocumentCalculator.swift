import Foundation

/// Montants calculés d'une ligne.
public struct LineTotals: Sendable, Equatable {
    /// Quantité × prix unitaire, arrondi au centime.
    public var grossHT: Decimal
    /// Remise de ligne, au centime.
    public var discountHT: Decimal
    /// Montant HT net de la ligne (règle R2).
    public var netHT: Decimal
}

/// Base et montant de TVA pour un taux donné.
public struct VATBucket: Sendable, Equatable, Identifiable {
    public var rate: Decimal
    /// Base HT après remise globale.
    public var baseHT: Decimal
    public var vatAmount: Decimal
    public var id: Decimal { rate }
}

/// Totaux d'un document. Tous les montants sont positifs, y compris pour un avoir :
/// le signe comptable est porté par le type de document.
public struct DocumentTotals: Sendable, Equatable {
    public var lines: [UUID: LineTotals]
    /// Somme des lignes HT, avant remise globale.
    public var subtotalHT: Decimal
    public var globalDiscountHT: Decimal
    public var totalHT: Decimal
    public var vatBuckets: [VATBucket]
    public var totalVAT: Decimal
    public var totalTTC: Decimal
    /// Acomptes déjà facturés et déduits (TTC).
    public var depositsDeductedTTC: Decimal
    /// Montant restant à payer sur ce document (TTC − acomptes déduits).
    public var netToPay: Decimal
    /// Acompte demandé à la commande (devis).
    public var requestedDepositTTC: Decimal
    /// Total des remises (lignes + globale), HT.
    public var totalDiscountHT: Decimal {
        lines.values.reduce(Decimal(0)) { $0 + $1.discountHT } + globalDiscountHT
    }
}

/// Moteur de calcul des devis et factures. Fonctions pures, sans état.
/// Les règles d'arrondi R1 à R5 sont décrites dans `Money`.
public enum DocumentCalculator {

    public static func lineTotals(_ line: DocumentLine) -> LineTotals {
        guard line.kind == .item else { return LineTotals(grossHT: 0, discountHT: 0, netHT: 0) }
        let gross = Money.round(line.quantity * line.unitPriceHT)
        let discount = line.discount.amount(on: gross)
        return LineTotals(grossHT: gross, discountHT: discount, netHT: gross - discount)
    }

    /// Calcule l'ensemble des totaux.
    /// En franchise en base ou en autoliquidation, la TVA est forcée à 0.
    public static func totals(for document: BusinessDocument) -> DocumentTotals {
        let vatApplicable = document.chargesVAT
        var perLine: [UUID: LineTotals] = [:]
        var baseByRate: [Decimal: Decimal] = [:]
        var subtotal = Decimal(0)
        for line in document.lines where line.kind == .item {
            let totals = lineTotals(line)
            perLine[line.id] = totals
            subtotal += totals.netHT
            let rate = vatApplicable ? line.vatRate : 0
            baseByRate[rate, default: 0] += totals.netHT
        }

        let globalDiscount = document.globalDiscount.amount(on: subtotal)
        let rates = baseByRate.keys.sorted(by: >)
        let weights = rates.map { baseByRate[$0] ?? 0 }
        let discountShares = Money.allocate(globalDiscount, weights: weights)

        var buckets: [VATBucket] = []
        for (index, rate) in rates.enumerated() {
            let base = (baseByRate[rate] ?? 0) - (discountShares.indices.contains(index) ? discountShares[index] : 0)
            let vat = Money.round(base * rate / 100)
            buckets.append(VATBucket(rate: rate, baseHT: base, vatAmount: vat))
        }

        let totalHT = subtotal - globalDiscount
        let totalVAT = buckets.reduce(Decimal(0)) { $0 + $1.vatAmount }
        let totalTTC = totalHT + totalVAT
        let deposits = document.depositDeductions.reduce(Decimal(0)) { $0 + Money.round($1.amountTTC) }
        let netToPay = totalTTC - deposits
        let requested = document.kind == .quote ? document.depositRequest.amount(onTTC: totalTTC) : 0

        return DocumentTotals(
            lines: perLine,
            subtotalHT: subtotal,
            globalDiscountHT: globalDiscount,
            totalHT: totalHT,
            vatBuckets: buckets,
            totalVAT: totalVAT,
            totalTTC: totalTTC,
            depositsDeductedTTC: deposits,
            netToPay: netToPay,
            requestedDepositTTC: requested
        )
    }

    /// Convertit un prix TTC en prix unitaire HT (4 décimales, règle R1).
    public static func priceHT(fromTTC ttc: Decimal, vatRate: Decimal) -> Decimal {
        Money.round(ttc / (1 + vatRate / 100), scale: Money.unitPriceScale)
    }

    /// Convertit un prix HT en TTC (au centime).
    public static func priceTTC(fromHT ht: Decimal, vatRate: Decimal) -> Decimal {
        Money.round(ht * (1 + vatRate / 100))
    }

    /// Lignes d'une facture d'acompte : une ligne par taux de TVA, au prorata des bases
    /// du devis, pour que la TVA de l'acompte suive la ventilation du devis.
    public static func depositLines(for quote: BusinessDocument, depositTTC: Decimal) -> [DocumentLine] {
        let totals = totals(for: quote)
        guard totals.totalTTC > 0, depositTTC > 0 else { return [] }
        let amount = min(Money.round(depositTTC), totals.totalTTC)
        let ttcWeights = totals.vatBuckets.map { $0.baseHT + $0.vatAmount }
        let ttcShares = Money.allocate(amount, weights: ttcWeights)
        let percent = Money.round(amount * 100 / totals.totalTTC, scale: 2)
        let reference = quote.number.isEmpty ? "" : " — devis n° \(quote.number)"
        var lines: [DocumentLine] = []
        // R6 — La TVA étant calculée sur la base HT (R4), tous les montants TTC ne sont pas
        // atteignables au centime (HT + arrondi(HT × taux) saute parfois un centime). On choisit
        // pour chaque taux la base HT dont le TTC est le plus proche de la part visée et on reporte
        // l'écart sur le taux suivant : le TTC final diffère au plus d'un centime de l'acompte demandé.
        var carry = Decimal(0)
        for (bucket, shareTTC) in zip(totals.vatBuckets, ttcShares) where shareTTC > 0 {
            let desired = shareTTC + carry
            let approx = Money.round(desired / (1 + bucket.rate / 100))
            var bestHT = approx
            var bestGap = Decimal.greatestFiniteMagnitude
            for step in -3...3 {
                let candidate = approx + Decimal(step) / 100
                guard candidate > 0 else { continue }
                let ttc = candidate + Money.round(candidate * bucket.rate / 100)
                let gap = abs(ttc - desired)
                if gap < bestGap || (gap == bestGap && candidate > bestHT) {
                    bestGap = gap
                    bestHT = candidate
                }
            }
            carry = desired - (bestHT + Money.round(bestHT * bucket.rate / 100))
            let rateLabel = totals.vatBuckets.count > 1 ? " (TVA \(Money.formatQuantity(bucket.rate)) %)" : ""
            lines.append(DocumentLine(
                designation: "Acompte de \(Money.formatQuantity(percent)) %\(reference)\(rateLabel)",
                quantity: 1,
                unit: "forfait",
                unitPriceHT: bestHT,
                vatRate: bucket.rate,
                nature: quote.itemLines.allSatisfy { $0.nature == .goods } ? .goods : .services
            ))
        }
        return lines
    }
}
