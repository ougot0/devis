import SwiftUI
import DevisCore

/// Édition d'une ligne de document.
struct LineEditorView: View {
    @Environment(AppDataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var line: DocumentLine
    @State private var saveToCatalog = false
    @State private var error: PresentedError?
    let isNew: Bool
    let chargesVAT: Bool
    let onSave: (DocumentLine) -> Void

    static let commonUnits = ["u", "h", "jour", "forfait", "m", "m²", "m³", "kg", "lot", "mois"]

    init(line: DocumentLine, isNew: Bool, chargesVAT: Bool, onSave: @escaping (DocumentLine) -> Void) {
        _line = State(initialValue: line)
        self.isNew = isNew
        self.chargesVAT = chargesVAT
        self.onSave = onSave
    }

    private var totals: LineTotals { DocumentCalculator.lineTotals(line) }

    var body: some View {
        Form {
            switch line.kind {
            case .section:
                Section("Titre de section") {
                    TextField("Ex. : Lot 1 — Préparation", text: $line.designation)
                }
            case .note:
                Section("Texte libre") {
                    TextField("Texte imprimé dans le tableau", text: $line.designation, axis: .vertical)
                        .lineLimit(3...10)
                }
            case .item:
                itemForm
            }
        }
        .appBackground()
        .navigationTitle(isNew ? "Nouvelle ligne" : "Modifier la ligne")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? "Ajouter" : "OK") { save() }
                    .fontWeight(.semibold)
                    .disabled(line.designation.trimmed.isEmpty)
            }
        }
        .errorAlert($error)
    }

    @ViewBuilder
    private var itemForm: some View {
        Section("Désignation") {
            TextField("Prestation ou produit", text: $line.designation, axis: .vertical)
                .lineLimit(1...4)
            TextField("Description détaillée (facultatif)", text: $line.details, axis: .vertical)
                .lineLimit(2...10)
            Picker("Nature", selection: $line.nature) {
                ForEach(OperationNature.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        Section("Quantité et prix") {
            LabeledDecimalRow(label: "Quantité", value: $line.quantity, suffix: "")
            LabeledContent("Unité") {
                Menu {
                    ForEach(Self.commonUnits, id: \.self) { unit in
                        Button(unit) { line.unit = unit }
                    }
                } label: {
                    Text(line.unit.isEmpty ? "Choisir" : line.unit)
                }
            }
            TextField("Autre unité", text: $line.unit)
            LabeledDecimalRow(label: "Prix unitaire HT", value: $line.unitPriceHT)
            if chargesVAT {
                VATRatePicker(rate: $line.vatRate)
            }
        }
        Section("Remise sur la ligne") {
            DiscountEditor(title: "Remise", discount: $line.discount)
        }
        Section {
            LabeledDecimalRow(label: "Coût de revient unitaire", value: Binding(get: { line.unitCost ?? 0 }, set: { line.unitCost = $0 == 0 ? nil : $0 }))
            if let cost = line.unitCost, cost > 0, line.quantity > 0, totals.netHT > 0 {
                let result = ProfitabilityCalculator.compute(ProfitabilityInput(salePriceHT: totals.netHT / line.quantity, unitCostHT: cost, quantity: line.quantity))
                LabeledContent("Marge brute estimée") {
                    AmountText(value: result.estimatedGrossProfit, weight: .regular)
                        .foregroundStyle(result.isLossMaking ? Theme.danger : Theme.ink)
                }
            }
        } header: {
            Text("Rentabilité (non imprimé)")
        }
        Section {
            LabeledContent("Total HT de la ligne") { AmountText(value: totals.netHT) }
            if isNew && line.catalogItemID == nil {
                Toggle("Enregistrer dans le catalogue", isOn: $saveToCatalog)
            }
        }
    }

    private func save() {
        if saveToCatalog {
            let item = CatalogItem(name: line.designation, details: line.details, price: line.unitPriceHT, vatRate: line.vatRate, unit: line.unit, unitCost: line.unitCost, nature: line.nature)
            do {
                try store.save(item: item)
                line.catalogItemID = item.id
            } catch {
                self.error = PresentedError(error)
                return
            }
        }
        onSave(line)
        dismiss()
    }
}
