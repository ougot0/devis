import SwiftUI
import SwiftData
import DevisCore

/// Catalogue de produits et prestations réutilisables.
struct CatalogListView: View {
    @Environment(DataStore.self) private var store
    @Query(sort: \CatalogEntity.name) private var entities: [CatalogEntity]
    @State private var search = ""
    @State private var category: String?
    @State private var editing: CatalogItem?
    @State private var error: PresentedError?

    private var categories: [String] {
        Array(Set(entities.map(\.category).filter { !$0.isEmpty })).sorted()
    }

    private var filtered: [CatalogItem] {
        let query = search.trimmed.lowercased()
        return entities
            .filter { (category == nil || $0.category == category) && (query.isEmpty || $0.searchText.contains(query)) }
            .compactMap(\.item)
    }

    var body: some View {
        List {
            if !categories.isEmpty {
                Picker("Catégorie", selection: $category) {
                    Text("Toutes").tag(String?.none)
                    ForEach(categories, id: \.self) { Text($0).tag(String?.some($0)) }
                }
            }
            ForEach(filtered) { item in
                Button { editing = item } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).foregroundStyle(item.isArchived ? Theme.neutral : Theme.ink)
                            Text([item.category, "TVA \(Money.formatQuantity(item.vatRate)) %", item.unit].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.footnote).foregroundStyle(Theme.neutral)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            AmountText(value: item.price, weight: .medium).foregroundStyle(Theme.ink)
                            Text(item.priceIncludesVAT ? "TTC" : "HT").font(.caption2).foregroundStyle(Theme.neutral)
                        }
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        do { try store.deleteCatalogItem(id: item.id) } catch { self.error = PresentedError(error) }
                    } label: { Label("Supprimer", systemImage: "trash") }
                }
            }
        }
        .overlay {
            if entities.isEmpty {
                EmptyStateView(title: "Catalogue vide", message: "Enregistrez vos prestations et produits habituels pour composer un devis en quelques touches.", systemImage: "shippingbox")
            }
        }
        .searchable(text: $search, prompt: "Rechercher")
        .navigationTitle("Catalogue")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = CatalogItem(name: "", price: 0, vatRate: store.company.isVATRegistered ? 20 : 0) } label: {
                    Label("Nouvel élément", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editing) { item in
            NavigationStack { CatalogItemEditorView(item: item) }
        }
        .errorAlert($error)
        .appBackground()
    }
}

struct CatalogItemEditorView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var item: CatalogItem
    @State private var error: PresentedError?

    init(item: CatalogItem) { _item = State(initialValue: item) }

    var body: some View {
        Form {
            Section {
                TextField("Nom", text: $item.name)
                TextField("Description", text: $item.details, axis: .vertical)
                TextField("Catégorie", text: $item.category)
                Picker("Nature", selection: $item.nature) {
                    ForEach(OperationNature.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section {
                Picker("Prix saisi", selection: $item.priceIncludesVAT) {
                    Text("HT").tag(false)
                    Text("TTC").tag(true)
                }
                .pickerStyle(.segmented)
                LabeledDecimalRow(label: item.priceIncludesVAT ? "Prix TTC" : "Prix HT", value: $item.price)
                if store.company.isVATRegistered {
                    VATRatePicker(rate: $item.vatRate)
                    if item.priceIncludesVAT {
                        LabeledContent("Soit HT") { Text(Money.format(item.unitPriceHT, scale: 4)).font(.amount(.body, weight: .regular)) }
                    }
                }
                TextField("Unité (h, jour, m², forfait…)", text: $item.unit)
            } header: {
                Text("Prix")
            }
            Section {
                LabeledDecimalRow(label: "Coût de revient HT", value: Binding(get: { item.unitCost ?? 0 }, set: { item.unitCost = $0 == 0 ? nil : $0 }))
                if let cost = item.unitCost, cost > 0 {
                    let result = ProfitabilityCalculator.compute(ProfitabilityInput(salePriceHT: item.unitPriceHT, unitCostHT: cost))
                    LabeledContent("Marge brute unitaire") { AmountText(value: result.unitMargin, weight: .regular) }
                    if let markup = result.markupRate {
                        LabeledContent("Taux de marque") { Text("\(Money.formatQuantity(markup)) %").font(.amount(.body, weight: .regular)) }
                    }
                }
            } header: {
                Text("Rentabilité (facultatif)")
            }
            Section {
                Toggle("Archivé (masqué lors de la création des devis)", isOn: $item.isArchived)
            }
        }
        .appBackground()
        .navigationTitle(item.name.isEmpty ? "Nouvel élément" : item.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer") { save() }.fontWeight(.semibold).disabled(item.name.trimmed.isEmpty)
            }
        }
        .errorAlert($error)
    }

    private func save() {
        do {
            try store.save(item: item)
            dismiss()
        } catch {
            self.error = PresentedError(error)
        }
    }
}
