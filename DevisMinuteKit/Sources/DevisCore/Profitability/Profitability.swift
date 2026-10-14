import Foundation

/// Calculateur de rentabilité, utilisable indépendamment des devis.
///
/// Définitions (vocabulaire du commerce, montants HT) :
/// - **Prix de vente net** = prix de vente − remise commerciale.
/// - **Marge brute** (marge commerciale unitaire) = prix de vente net − coût de revient.
/// - **Taux de marge** = marge brute ÷ coût de revient.
/// - **Taux de marque** = marge brute ÷ prix de vente net.
/// - **Coefficient multiplicateur** = prix de vente net ÷ coût de revient.
/// - **Bénéfice brut estimé** = marge brute × quantité.
///
/// La marge brute n'est ni le bénéfice net (il reste les charges fixes, cotisations et impôts),
/// ni le chiffre d'affaires (le prix de vente total), ni la trésorerie (les sommes réellement encaissées).
public struct ProfitabilityInput: Sendable, Equatable {
    public var salePriceHT: Decimal
    public var unitCostHT: Decimal
    public var discountPercent: Decimal
    public var quantity: Decimal

    public init(salePriceHT: Decimal, unitCostHT: Decimal, discountPercent: Decimal = 0, quantity: Decimal = 1) {
        self.salePriceHT = salePriceHT
        self.unitCostHT = unitCostHT
        self.discountPercent = discountPercent
        self.quantity = quantity
    }
}

public struct ProfitabilityResult: Sendable, Equatable {
    public var netSalePriceHT: Decimal
    public var discountAmount: Decimal
    public var unitMargin: Decimal
    /// En pourcentage ; `nil` si le coût est nul.
    public var marginRate: Decimal?
    /// En pourcentage ; `nil` si le prix net est nul.
    public var markupRate: Decimal?
    public var multiplier: Decimal?
    public var revenueHT: Decimal
    public var totalCost: Decimal
    public var estimatedGrossProfit: Decimal
    public var isLossMaking: Bool
}

public enum ProfitabilityCalculator {

    public static func compute(_ input: ProfitabilityInput) -> ProfitabilityResult {
        let discount = Money.round(input.salePriceHT * min(max(input.discountPercent, 0), 100) / 100, scale: 4)
        let net = input.salePriceHT - discount
        let margin = net - input.unitCostHT
        let marginRate: Decimal? = input.unitCostHT > 0 ? Money.round(margin * 100 / input.unitCostHT, scale: 2) : nil
        let markupRate: Decimal? = net > 0 ? Money.round(margin * 100 / net, scale: 2) : nil
        let multiplier: Decimal? = input.unitCostHT > 0 ? Money.round(net / input.unitCostHT, scale: 3) : nil
        let revenue = Money.round(net * input.quantity)
        let cost = Money.round(input.unitCostHT * input.quantity)
        return ProfitabilityResult(
            netSalePriceHT: Money.round(net, scale: 4),
            discountAmount: discount,
            unitMargin: Money.round(margin, scale: 4),
            marginRate: marginRate,
            markupRate: markupRate,
            multiplier: multiplier,
            revenueHT: revenue,
            totalCost: cost,
            estimatedGrossProfit: revenue - cost,
            isLossMaking: margin < 0
        )
    }

    /// Prix de vente HT pour obtenir un taux de marge donné (sur coût).
    public static func price(forMarginRate rate: Decimal, cost: Decimal) -> Decimal {
        Money.round(cost * (1 + rate / 100))
    }

    /// Prix de vente HT pour obtenir un taux de marque donné (sur prix de vente). `nil` si le taux ≥ 100 %.
    public static func price(forMarkupRate rate: Decimal, cost: Decimal) -> Decimal? {
        guard rate < 100 else { return nil }
        return Money.round(cost / (1 - rate / 100))
    }

    /// Remise maximale (en %) avant de vendre à perte.
    public static func maximumDiscount(salePriceHT: Decimal, unitCostHT: Decimal) -> Decimal {
        guard salePriceHT > 0, unitCostHT < salePriceHT else { return 0 }
        return Money.round((salePriceHT - unitCostHT) * 100 / salePriceHT, scale: 2)
    }
}
