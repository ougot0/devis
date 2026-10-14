import SwiftUI
import SwiftData
import DevisCore

/// Répertoire clients avec recherche et filtre par type.
struct CustomerListView: View {
    @Environment(AppDataStore.self) private var store
    @Query(sort: \CustomerEntity.name) private var entities: [CustomerEntity]
    @State private var search = ""
    @State private var kindFilter: CustomerKind?
    @State private var showArchived = false
    @State private var creating = false

    private var filtered: [CustomerEntity] {
        let query = search.trimmed.lowercased()
        return entities.filter { entity in
            (showArchived || !entity.isArchived)
                && (kindFilter == nil || entity.kindRaw == kindFilter?.rawValue)
                && (query.isEmpty || entity.searchText.contains(query))
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Type", selection: $kindFilter) {
                    Text("Tous").tag(CustomerKind?.none)
                    ForEach(CustomerKind.allCases) { Text($0.label).tag(CustomerKind?.some($0)) }
                }
                Toggle("Afficher les clients archivés", isOn: $showArchived)
            }
            ForEach(filtered) { entity in
                NavigationLink { CustomerDetailView(customerID: entity.id) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entity.name).foregroundStyle(entity.isArchived ? Theme.neutral : Theme.ink)
                        Text([CustomerKind(rawValue: entity.kindRaw)?.label ?? "", entity.city, entity.isArchived ? "archivé" : ""]
                            .filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.footnote).foregroundStyle(Theme.neutral)
                    }
                }
            }
        }
        .overlay {
            if entities.isEmpty {
                EmptyStateView(title: "Aucun client", message: "Ajoutez un client : ses coordonnées seront reprises automatiquement dans vos devis et factures.", systemImage: "person.2")
            }
        }
        .searchable(text: $search, prompt: "Nom, ville, email, SIREN")
        .navigationTitle("Clients")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { creating = true } label: { Label("Nouveau client", systemImage: "plus") }
            }
        }
        .navigationDestination(isPresented: $creating) { CustomerEditorView(customer: nil) }
        .appBackground()
    }
}

/// Fiche client : coordonnées, historique des devis et factures, montants facturés et encaissés.
struct CustomerDetailView: View {
    @Environment(AppDataStore.self) private var store
    let customerID: UUID

    @State private var customer: CustomerRecord?
    @State private var records: [DocumentRecord] = []
    @State private var allRecords: [DocumentRecord] = []
    @State private var editor: DashboardView.EditorTarget?
    @State private var editing = false
    @State private var error: PresentedError?

    var body: some View {
        List {
            if let customer {
                let snapshot = customer.snapshot
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(snapshot.name).font(.title3.weight(.semibold))
                        Text(snapshot.kind.label).font(.footnote).foregroundStyle(Theme.neutral)
                    }
                    if !snapshot.contactName.isEmpty { LabeledContent("Contact", value: snapshot.contactName) }
                    if !snapshot.address.isEmpty { LabeledContent("Adresse", value: snapshot.address.lines.joined(separator: "\n")) }
                    if !snapshot.email.isEmpty, let url = URL(string: "mailto:\(snapshot.email)") {
                        Link(destination: url) { LabeledContent("Email", value: snapshot.email) }
                    }
                    if !snapshot.phone.isEmpty, let url = URL(string: "tel:\(snapshot.phone.filter { $0.isNumber || $0 == "+" })") {
                        Link(destination: url) { LabeledContent("Téléphone", value: snapshot.phone) }
                    }
                    if !snapshot.siren.isEmpty { LabeledContent("SIREN", value: LegalMentionsBuilder.formatSiren(snapshot.siren)) }
                    if !snapshot.vatNumber.isEmpty { LabeledContent("TVA", value: snapshot.vatNumber) }
                    if !customer.notes.isEmpty {
                        Text(customer.notes).font(.footnote).foregroundStyle(Theme.neutral)
                    }
                }
                Section("Montants") {
                    LabeledContent("Facturé (TTC, avoirs déduits)") { AmountText(value: invoiced) }
                    LabeledContent("Encaissé") { AmountText(value: collected).foregroundStyle(Theme.success) }
                    LabeledContent("Reste dû") { AmountText(value: outstanding) }
                }
                Section {
                    Button { editor = DashboardView.EditorTarget(record: store.makeQuote(customer: customer)) } label: { Label("Nouveau devis", systemImage: "doc.text") }
                    Button { editor = DashboardView.EditorTarget(record: store.makeInvoice(customer: customer)) } label: { Label("Nouvelle facture", systemImage: "doc.plaintext") }
                }
                Section("Historique") {
                    if records.isEmpty {
                        Text("Aucun document pour ce client.").font(.footnote).foregroundStyle(Theme.neutral)
                    }
                    ForEach(records) { record in
                        NavigationLink { DocumentDetailView(documentID: record.id) } label: {
                            DocumentRow(record: record, allRecords: allRecords)
                        }
                    }
                }
            }
        }
        .appBackground()
        .navigationTitle(customer?.snapshot.name ?? "Client")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button("Modifier") { editing = true } }
            ToolbarItem(placement: .secondaryAction) {
                Button(role: .destructive) { archive() } label: { Label("Supprimer ou archiver", systemImage: "archivebox") }
            }
        }
        .navigationDestination(isPresented: $editing) {
            if let customer { CustomerEditorView(customer: customer) }
        }
        .sheet(item: $editor) { target in NavigationStack { DocumentEditorView(record: target.record) } }
        .errorAlert($error)
        .onAppear(perform: reload)
        .onChange(of: store.revision) { _, _ in reload() }
    }

    private var issued: [DocumentRecord] { records.filter(\.isIssuedInvoice) }
    private var invoiced: Decimal { issued.reduce(Decimal(0)) { $0 + Accounting.invoicedTTC($1) } }
    private var collected: Decimal { issued.reduce(Decimal(0)) { total, record in total + record.payments.reduce(Decimal(0)) { $0 + $1.amount } } }
    private var outstanding: Decimal {
        issued.filter { $0.document.kind != .creditNote }.reduce(Decimal(0)) { $0 + Accounting.ledger(for: $1, in: allRecords).balance }
    }

    private func reload() {
        customer = store.customer(id: customerID)
        allRecords = store.allRecords()
        records = allRecords.filter { $0.customerID == customerID }
    }

    private func archive() {
        do { try store.deleteOrArchive(customerID: customerID) } catch { self.error = PresentedError(error) }
    }
}

/// Création et modification d'un client.
struct CustomerEditorView: View {
    @Environment(AppDataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var record: CustomerRecord
    @State private var error: PresentedError?
    private let onSave: ((CustomerRecord) -> Void)?

    init(customer: CustomerRecord?, onSave: ((CustomerRecord) -> Void)? = nil) {
        _record = State(initialValue: customer ?? CustomerRecord(snapshot: CustomerSnapshot()))
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section {
                Picker("Type", selection: $record.snapshot.kind) {
                    ForEach(CustomerKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                TextField(record.snapshot.kind == .individual ? "Nom et prénom" : "Raison sociale", text: $record.snapshot.name)
                    .textContentType(record.snapshot.kind == .individual ? .name : .organizationName)
                if record.snapshot.kind != .individual {
                    TextField("Nom du contact", text: $record.snapshot.contactName)
                }
            }
            Section("Adresse de facturation") {
                TextField("Adresse", text: $record.snapshot.address.line1)
                TextField("Complément", text: $record.snapshot.address.line2)
                HStack {
                    TextField("Code postal", text: $record.snapshot.address.postalCode)
                        .keyboardType(.numberPad)
                        .frame(maxWidth: 110)
                    TextField("Ville", text: $record.snapshot.address.city)
                }
                TextField("Pays", text: $record.snapshot.address.country)
            }
            Section("Contact") {
                TextField("Email", text: $record.snapshot.email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                TextField("Téléphone", text: $record.snapshot.phone)
                    .keyboardType(.phonePad)
            }
            if record.snapshot.kind != .individual {
                Section {
                    TextField("SIREN", text: $record.snapshot.siren)
                        .keyboardType(.numberPad)
                    if !record.snapshot.siren.trimmed.isEmpty && !Identifiers.isValidSIREN(record.snapshot.siren) {
                        Text("SIREN invalide.").font(.footnote).foregroundStyle(Theme.danger)
                    }
                    TextField("N° de TVA intracommunautaire", text: $record.snapshot.vatNumber)
                        .textInputAutocapitalization(.characters)
                } header: {
                    Text("Identifiants")
                } footer: {
                    Text("Le SIREN du client professionnel devient une mention obligatoire avec la facturation électronique.")
                }
            }
            Section("Notes internes (non imprimées)") {
                TextField("Notes", text: $record.notes, axis: .vertical)
            }
        }
        .appBackground()
        .navigationTitle(record.snapshot.name.isEmpty ? "Nouveau client" : record.snapshot.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer") { save() }
                    .fontWeight(.semibold)
                    .disabled(record.snapshot.name.trimmed.isEmpty)
            }
        }
        .errorAlert($error)
    }

    private func save() {
        record.snapshot.siren = record.snapshot.siren.filter(\.isNumber)
        do {
            try store.save(customer: record)
            onSave?(record)
            dismiss()
        } catch {
            self.error = PresentedError(error)
        }
    }
}
