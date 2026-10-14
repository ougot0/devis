import SwiftUI
import DevisCore

/// Calculateur de rentabilité indépendant des devis.
struct ProfitabilityView: View {
    @State private var price: Decimal = 0
    @State private var cost: Decimal = 0
    @State private var discount: Decimal = 0
    @State private var quantity: Decimal = 1
    @State private var targetRate: Decimal = 30

    private var result: ProfitabilityResult {
        ProfitabilityCalculator.compute(ProfitabilityInput(salePriceHT: price, unitCostHT: cost, discountPercent: discount, quantity: quantity))
    }

    var body: some View {
        Form {
            Section {
                LabeledDecimalRow(label: "Prix de vente HT", value: $price)
                LabeledDecimalRow(label: "Coût de revient HT", value: $cost)
                LabeledDecimalRow(label: "Remise commerciale", value: $discount, suffix: "%", maxScale: 2)
                LabeledDecimalRow(label: "Quantité", value: $quantity, suffix: "")
            } header: {
                Text("Données (montants unitaires)")
            }

            if price > 0 {
                let result = result
                Section("Résultats") {
                    row("Prix de vente net HT", Money.format(result.netSalePriceHT, scale: 2))
                    row("Marge brute unitaire", Money.format(result.unitMargin, scale: 2), danger: result.isLossMaking)
                    row("Taux de marge (sur coût)", result.marginRate.map { "\(Money.formatQuantity($0)) %" } ?? "—")
                    row("Taux de marque (sur prix)", result.markupRate.map { "\(Money.formatQuantity($0)) %" } ?? "—")
                    row("Coefficient multiplicateur", result.multiplier.map { Money.formatQuantity($0) } ?? "—")
                    row("Chiffre d'affaires HT", Money.format(result.revenueHT))
                    row("Bénéfice brut estimé", Money.format(result.estimatedGrossProfit), danger: result.isLossMaking)
                    if cost > 0 && cost < price {
                        row("Remise maximale avant perte", "\(Money.formatQuantity(ProfitabilityCalculator.maximumDiscount(salePriceHT: price, unitCostHT: cost))) %")
                    }
                }
                if result.isLossMaking {
                    Section {
                        Label("À ce prix, chaque unité est vendue à perte.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.danger)
                    }
                }
            }

            Section {
                LabeledDecimalRow(label: "Taux visé", value: $targetRate, suffix: "%", maxScale: 2)
                if cost > 0 {
                    row("Prix pour ce taux de marge", Money.format(ProfitabilityCalculator.price(forMarginRate: targetRate, cost: cost)))
                    row("Prix pour ce taux de marque", ProfitabilityCalculator.price(forMarkupRate: targetRate, cost: cost).map { Money.format($0) } ?? "Impossible (≥ 100 %)")
                } else {
                    Text("Saisissez un coût de revient pour calculer un prix de vente.").font(.footnote).foregroundStyle(Theme.neutral)
                }
            } header: {
                Text("Trouver un prix de vente")
            }

            Section("Repères") {
                Text("• La marge brute est la différence entre le prix de vente net et le coût de revient.\n• Le taux de marge la rapporte au coût ; le taux de marque, au prix de vente.\n• Le bénéfice brut n'est pas le bénéfice net : restent à payer les charges fixes, les cotisations sociales et les impôts.\n• Le chiffre d'affaires n'est pas la trésorerie : seules les sommes encaissées sont disponibles.")
                    .font(.footnote)
                    .foregroundStyle(Theme.neutral)
            }
        }
        .appBackground()
        .navigationTitle("Rentabilité")
    }

    private func row(_ label: String, _ value: String, danger: Bool = false) -> some View {
        LabeledContent(label) {
            Text(value).font(.amount(.body, weight: .medium)).foregroundStyle(danger ? Theme.danger : Theme.ink)
        }
    }
}
