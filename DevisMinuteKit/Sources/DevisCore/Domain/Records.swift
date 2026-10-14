import Foundation

/// Fiche client du répertoire.
public struct CustomerRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var snapshot: CustomerSnapshot
    public var notes: String
    public var createdAt: Date
    public var isArchived: Bool

    public init(id: UUID = UUID(), snapshot: CustomerSnapshot, notes: String = "", createdAt: Date = Date(), isArchived: Bool = false) {
        self.id = id
        self.snapshot = snapshot
        self.notes = notes
        self.createdAt = createdAt
        self.isArchived = isArchived
    }
}

/// Élément du catalogue de produits et prestations.
public struct CatalogItem: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var details: String
    public var category: String
    /// Prix saisi, HT ou TTC selon `priceIncludesVAT`.
    public var price: Decimal
    public var priceIncludesVAT: Bool
    public var vatRate: Decimal
    public var unit: String
    public var unitCost: Decimal?
    public var nature: OperationNature
    public var isArchived: Bool

    public init(id: UUID = UUID(), name: String, details: String = "", category: String = "", price: Decimal, priceIncludesVAT: Bool = false, vatRate: Decimal = 20, unit: String = "u", unitCost: Decimal? = nil, nature: OperationNature = .services, isArchived: Bool = false) {
        self.id = id
        self.name = name
        self.details = details
        self.category = category
        self.price = price
        self.priceIncludesVAT = priceIncludesVAT
        self.vatRate = vatRate
        self.unit = unit
        self.unitCost = unitCost
        self.nature = nature
        self.isArchived = isArchived
    }

    /// Prix unitaire HT utilisé dans les documents (4 décimales max, règle R1).
    public var unitPriceHT: Decimal {
        priceIncludesVAT ? DocumentCalculator.priceHT(fromTTC: price, vatRate: vatRate) : Money.round(price, scale: Money.unitPriceScale)
    }

    /// Ligne de document pré-remplie. En franchise en base, le taux est mis à 0.
    public func makeLine(quantity: Decimal = 1, sellerChargesVAT: Bool = true) -> DocumentLine {
        let priceHT: Decimal
        if priceIncludesVAT && !sellerChargesVAT {
            // Sans TVA, le prix « TTC » saisi est le prix facturé.
            priceHT = Money.round(price, scale: Money.unitPriceScale)
        } else {
            priceHT = unitPriceHT
        }
        return DocumentLine(designation: name, details: details, quantity: quantity, unit: unit, unitPriceHT: priceHT, vatRate: sellerChargesVAT ? vatRate : 0, nature: nature, catalogItemID: id, unitCost: unitCost)
    }
}

/// Document persistant : contenu + statut + paiements + sceau.
public struct DocumentRecord: Codable, Sendable, Equatable, Identifiable {
    public var document: BusinessDocument
    public var quoteStatus: QuoteStatus?
    public var invoiceStatus: InvoiceStatus?
    public var payments: [PaymentRecord]
    public var seal: DocumentSeal?
    public var customerID: UUID?
    /// Document d'origine (devis converti, facture corrigée par un avoir…).
    public var sourceDocumentID: UUID?
    public var createdAt: Date
    public var updatedAt: Date
    /// Horodatage de l'émission définitive (factures).
    public var issuedAt: Date?

    public var id: UUID { document.id }

    public init(document: BusinessDocument, quoteStatus: QuoteStatus? = nil, invoiceStatus: InvoiceStatus? = nil, payments: [PaymentRecord] = [], seal: DocumentSeal? = nil, customerID: UUID? = nil, sourceDocumentID: UUID? = nil, createdAt: Date = Date(), updatedAt: Date = Date(), issuedAt: Date? = nil) {
        self.document = document
        self.quoteStatus = quoteStatus ?? (document.kind == .quote ? .draft : nil)
        self.invoiceStatus = invoiceStatus ?? (document.kind == .quote ? nil : .draft)
        self.payments = payments
        self.seal = seal
        self.customerID = customerID
        self.sourceDocumentID = sourceDocumentID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.issuedAt = issuedAt
    }

    public var isIssuedInvoice: Bool { document.kind.isInvoiceLike && invoiceStatus == .issued }
}

/// Calculs transverses entre documents (avoirs imputés, soldes).
public enum Accounting {

    /// Montant TTC des avoirs émis qui se rapportent à `invoice`.
    public static func creditedAmount(for invoice: DocumentRecord, in records: [DocumentRecord]) -> Decimal {
        guard !invoice.document.number.isEmpty else { return 0 }
        return records
            .filter { $0.document.kind == .creditNote && $0.invoiceStatus == .issued && $0.document.correctedInvoiceNumber == invoice.document.number }
            .reduce(Decimal(0)) { $0 + DocumentCalculator.totals(for: $1.document).totalTTC }
    }

    public static func ledger(for invoice: DocumentRecord, in records: [DocumentRecord]) -> PaymentLedger {
        let totals = DocumentCalculator.totals(for: invoice.document)
        return PaymentLedger(amountDue: totals.netToPay, payments: invoice.payments, creditedAmount: creditedAmount(for: invoice, in: records))
    }

    /// Montant « facturé » d'un document émis, signé (avoirs négatifs), TTC.
    /// Pour une facture de solde, les acomptes déjà facturés sont exclus pour éviter le double comptage.
    public static func invoicedTTC(_ record: DocumentRecord) -> Decimal {
        guard record.isIssuedInvoice else { return 0 }
        let totals = DocumentCalculator.totals(for: record.document)
        switch record.document.kind {
        case .creditNote: return -totals.totalTTC
        case .quote: return 0
        default: return totals.netToPay
        }
    }

    /// Montant facturé HT, au prorata du net à payer pour une facture de solde.
    public static func invoicedHT(_ record: DocumentRecord) -> Decimal {
        guard record.isIssuedInvoice else { return 0 }
        let totals = DocumentCalculator.totals(for: record.document)
        switch record.document.kind {
        case .creditNote: return -totals.totalHT
        case .quote: return 0
        default:
            guard totals.totalTTC > 0 else { return totals.totalHT }
            if totals.depositsDeductedTTC == 0 { return totals.totalHT }
            return Money.round(totals.totalHT * totals.netToPay / totals.totalTTC)
        }
    }
}
