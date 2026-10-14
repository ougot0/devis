import SwiftUI
import SwiftData
import DevisCore

/// Choix d'un client (avec création rapide).
struct CustomerPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<CustomerEntity> { !$0.isArchived }, sort: \CustomerEntity.name) private var customers: [CustomerEntity]
    @State private var search = ""
    @State private var creating = false
    let onSelect: (CustomerRecord) -> Void

    private var filtered: [CustomerRecord] {
        let query = search.trimmed.lowercased()
        return customers.filter { query.isEmpty || $0.searchText.contains(query) }.compactMap(\.record)
    }

    var body: some View {
        List {
            Section {
                Button { creating = true } label: { Label("Nouveau client", systemImage: "person.badge.plus") }
            }
            ForEach(filtered) { customer in
                Button {
                    onSelect(customer)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(customer.snapshot.name).foregroundStyle(Theme.ink)
                        Text([customer.snapshot.kind.label, customer.snapshot.address.city].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.footnote).foregroundStyle(Theme.neutral)
                    }
                }
            }
        }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Rechercher un client")
        .navigationTitle("Client")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
        .navigationDestination(isPresented: $creating) {
            CustomerEditorView(customer: nil) { created in
                onSelect(created)
                dismiss()
            }
        }
        .appBackground()
    }
}

/// Choix d'éléments du catalogue, avec quantité.
struct CatalogPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<CatalogEntity> { !$0.isArchived }, sort: \CatalogEntity.name) private var entities: [CatalogEntity]
    @State private var search = ""
    @State private var quantities: [UUID: Decimal] = [:]
    let chargesVAT: Bool
    let onAdd: ([DocumentLine]) -> Void

    private var items: [CatalogItem] {
        let query = search.trimmed.lowercased()
        return entities.filter { query.isEmpty || $0.searchText.contains(query) }.compactMap(\.item)
    }

    private var selectedCount: Int { quantities.values.filter { $0 > 0 }.count }

    var body: some View {
        List {
            if entities.isEmpty {
                Text("Votre catalogue est vide. Ajoutez des prestations depuis l'onglet Plus › Catalogue, ou cochez « Enregistrer dans le catalogue » en créant une ligne.")
                    .font(.footnote).foregroundStyle(Theme.neutral)
            }
            ForEach(items) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).foregroundStyle(Theme.ink)
                        Text("\(Money.format(item.unitPriceHT)) HT / \(item.unit)" + (item.category.isEmpty ? "" : " · \(item.category)"))
                            .font(.footnote).foregroundStyle(Theme.neutral)
                    }
                    Spacer()
                    let quantity = quantities[item.id] ?? 0
                    if quantity > 0 {
                        Text(Money.formatQuantity(quantity)).font(.amount()).frame(minWidth: 28)
                    }
                    Stepper("Quantité", value: Binding(get: { quantities[item.id] ?? 0 }, set: { quantities[item.id] = max($0, 0) }), in: 0...9999)
                        .labelsHidden()
                        .accessibilityLabel("Quantité de \(item.name)")
                }
            }
        }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Rechercher")
        .navigationTitle("Catalogue")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Ajouter (\(selectedCount))") { add() }
                    .fontWeight(.semibold)
                    .disabled(selectedCount == 0)
            }
        }
        .appBackground()
    }

    private func add() {
        let all = entities.compactMap(\.item)
        let lines = all.compactMap { item -> DocumentLine? in
            guard let quantity = quantities[item.id], quantity > 0 else { return nil }
            return item.makeLine(quantity: quantity, sellerChargesVAT: chargesVAT)
        }
        onAdd(lines)
        dismiss()
    }
}
