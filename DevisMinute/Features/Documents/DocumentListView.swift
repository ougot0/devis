import SwiftUI
import SwiftData
import DevisCore

/// État affiché d'un document (devis ou facture), avec sa tonalité.
struct DocumentStatusInfo {
    let label: String
    let tone: StatusBadge.Tone

    init(record: DocumentRecord, allRecords: [DocumentRecord], today: Date = Date()) {
        let document = record.document
        if document.kind == .quote {
            let status = QuoteLifecycle.effectiveStatus(record.quoteStatus ?? .draft, validUntil: document.validUntil, today: today)
            label = status.label
            switch status {
            case .draft: tone = .neutral
            case .sent: tone = .info
            case .accepted: tone = .success
            case .refused: tone = .danger
            case .expired: tone = .warning
            }
            return
        }
        guard record.isIssuedInvoice else {
            label = "Brouillon"
            tone = .neutral
            return
        }
        if document.kind == .creditNote {
            label = "Avoir émis"
            tone = .neutral
            return
        }
        let state = Accounting.ledger(for: record, in: allRecords).state(dueDate: document.dueDate, today: today)
        label = state.label
        switch state {
        case .paid: tone = .success
        case .partiallyPaid: tone = .info
        case .unpaid: tone = .info
        case .overdue: tone = .danger
        case .cancelled: tone = .neutral
        }
    }
}

/// Ligne de liste d'un document.
struct DocumentRow: View {
    let record: DocumentRecord
    let allRecords: [DocumentRecord]

    var body: some View {
        let document = record.document
        let status = DocumentStatusInfo(record: record, allRecords: allRecords)
        let totals = DocumentCalculator.totals(for: document)
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 3) {
                Text(document.customer.name.isEmpty ? "Client non renseigné" : document.customer.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text([document.kind == .quote || document.kind == .invoice ? "" : document.kind.title, document.number.isEmpty ? "Sans numéro" : document.number, DateFormatting.short(document.issueDate)]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(Theme.neutral)
            }
            Spacer(minLength: Theme.Space.s)
            VStack(alignment: .trailing, spacing: 4) {
                AmountText(value: document.kind == .creditNote ? -totals.totalTTC : totals.totalTTC)
                    .foregroundStyle(Theme.ink)
                StatusBadge(text: status.label, tone: status.tone)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// Liste des devis ou des factures, avec recherche et filtres.
struct DocumentListView: View {
    @Environment(AppDataStore.self) private var store
    let group: DocumentGroup

    @Query private var entities: [DocumentEntity]
    @State private var search = ""
    @State private var filter: Filter = .all
    @State private var editor: DashboardView.EditorTarget?
    @State private var error: PresentedError?

    enum Filter: String, CaseIterable, Identifiable {
        case all = "Tous"
        case drafts = "Brouillons"
        case pending = "En attente"
        case done = "Acceptés / payés"
        case problem = "Refusés / en retard"
        var id: String { rawValue }
    }

    init(group: DocumentGroup) {
        self.group = group
        let raw = group.rawValue
        _entities = Query(filter: #Predicate<DocumentEntity> { $0.group == raw }, sort: [SortDescriptor(\DocumentEntity.issueDate, order: .reverse)])
    }

    private var title: String { group == .quotes ? "Devis" : "Factures" }

    private var filtered: [DocumentRecord] {
        let all = store.allRecords()
        let query = search.trimmed.lowercased()
        let pairs: [(DocumentEntity, DocumentRecord)] = entities.compactMap { entity in entity.record.map { (entity, $0) } }
        return pairs.filter { entity, record in
            if !query.isEmpty && !entity.searchText.contains(query) { return false }
            let status = DocumentStatusInfo(record: record, allRecords: all)
            switch filter {
            case .all: return true
            case .drafts: return status.label == QuoteStatus.draft.label
            case .pending: return status.tone == .info
            case .done: return status.tone == .success
            case .problem: return status.tone == .danger || status.tone == .warning
            }
        }.map(\.1)
    }

    var body: some View {
        let all = store.allRecords()
        List {
            Picker("Filtre", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            .listRowBackground(Color.clear)

            ForEach(filtered) { record in
                NavigationLink(value: record.id) {
                    DocumentRow(record: record, allRecords: all)
                }
                .swipeActions(edge: .trailing) {
                    if !record.isIssuedInvoice {
                        Button(role: .destructive) { delete(record) } label: { Label("Supprimer", systemImage: "trash") }
                    }
                    Button { duplicate(record) } label: { Label("Dupliquer", systemImage: "plus.square.on.square") }
                        .tint(Theme.petrol)
                }
            }
        }
        .overlay {
            if entities.isEmpty {
                EmptyStateView(title: group == .quotes ? "Aucun devis" : "Aucune facture",
                               message: group == .quotes ? "Touchez + pour créer votre premier devis." : "Créez une facture, ou convertissez un devis accepté.",
                               systemImage: "doc.text")
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .searchable(text: $search, prompt: "Numéro, client, prestation")
        .navigationTitle(title)
        .navigationDestination(for: UUID.self) { DocumentDetailView(documentID: $0) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editor = DashboardView.EditorTarget(record: group == .quotes ? store.makeQuote(customer: nil) : store.makeInvoice(customer: nil))
                } label: {
                    Label(group == .quotes ? "Nouveau devis" : "Nouvelle facture", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editor) { target in
            NavigationStack { DocumentEditorView(record: target.record) }
        }
        .errorAlert($error)
        .appBackground()
    }

    private func delete(_ record: DocumentRecord) {
        do { try store.delete(id: record.id) } catch { self.error = PresentedError(error) }
    }

    private func duplicate(_ record: DocumentRecord) {
        do {
            let copy = try store.duplicate(id: record.id)
            editor = DashboardView.EditorTarget(record: copy)
        } catch {
            self.error = PresentedError(error)
        }
    }
}
