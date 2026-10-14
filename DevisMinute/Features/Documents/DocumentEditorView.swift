import SwiftUI
import DevisCore

/// Éditeur de devis et de factures brouillons.
/// Calculs instantanés, lignes réorganisables, client et catalogue en deux touches.
struct DocumentEditorView: View {
    @Environment(AppDataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var record: DocumentRecord
    @State private var lineEditor: LineTarget?
    @State private var showCustomerPicker = false
    @State private var showCatalogPicker = false
    @State private var showDetails = false
    @State private var error: PresentedError?
    private let isNew: Bool

    struct LineTarget: Identifiable {
        let id = UUID()
        let line: DocumentLine
        let isNew: Bool
    }

    init(record: DocumentRecord) {
        _record = State(initialValue: record)
        isNew = record.document.number.isEmpty && record.document.lines.isEmpty
    }

    private var document: BusinessDocument { record.document }
    private var totals: DocumentTotals { DocumentCalculator.totals(for: document) }
    private var isQuote: Bool { document.kind == .quote }
    private var chargesVAT: Bool { store.company.isVATRegistered && !document.reverseCharge }

    var body: some View {
        Form {
            customerSection
            linesSection
            totalsSection
            datesSection
            optionsSection
            textsSection
            complianceSection
        }
        .appBackground()
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer") { save() }.fontWeight(.semibold)
            }
        }
        .sheet(item: $lineEditor) { target in
            NavigationStack {
                LineEditorView(line: target.line, isNew: target.isNew, chargesVAT: chargesVAT) { updated in
                    apply(updated, isNew: target.isNew)
                }
            }
        }
        .sheet(isPresented: $showCustomerPicker) {
            NavigationStack {
                CustomerPickerView { customer in
                    record.customerID = customer.id
                    record.document.customer = customer.snapshot
                }
            }
        }
        .sheet(isPresented: $showCatalogPicker) {
            NavigationStack {
                CatalogPickerView(chargesVAT: chargesVAT) { lines in
                    record.document.lines.append(contentsOf: lines)
                }
            }
        }
        .errorAlert($error)
        .interactiveDismissDisabled()
        .onAppear {
            if record.document.customer.name.isEmpty && isNew { showCustomerPicker = true }
        }
    }

    private var navigationTitle: String {
        if !document.number.isEmpty { return "\(document.kind.title) \(document.number)" }
        return isQuote ? "Nouveau devis" : "\(document.kind.title) (brouillon)"
    }

    // MARK: Sections

    private var customerSection: some View {
        Section("Client") {
            Button { showCustomerPicker = true } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(document.customer.name.isEmpty ? "Choisir un client" : document.customer.name)
                            .font(.body.weight(.medium))
                            .foregroundStyle(document.customer.name.isEmpty ? Theme.petrol : Theme.ink)
                        let address = document.customer.address.lines.joined(separator: ", ")
                        if !address.isEmpty {
                            Text(address).font(.footnote).foregroundStyle(Theme.neutral).lineLimit(2)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Theme.neutral)
                }
            }
            .accessibilityHint("Ouvre le répertoire clients")
        }
    }

    private var linesSection: some View {
        Section {
            ForEach(document.lines) { line in
                Button { lineEditor = LineTarget(line: line, isNew: false) } label: {
                    LineSummaryRow(line: line, totals: totals.lines[line.id], chargesVAT: chargesVAT)
                }
                .swipeActions(edge: .leading) {
                    Button { duplicateLine(line) } label: { Label("Dupliquer", systemImage: "plus.square.on.square") }
                        .tint(Theme.petrol)
                }
            }
            .onDelete { record.document.lines.remove(atOffsets: $0) }
            .onMove { record.document.lines.move(fromOffsets: $0, toOffset: $1) }

            Button { lineEditor = LineTarget(line: DocumentLine(vatRate: chargesVAT ? 20 : 0), isNew: true) } label: {
                Label("Ajouter une prestation", systemImage: "plus")
            }
            Button { showCatalogPicker = true } label: {
                Label("Ajouter depuis le catalogue", systemImage: "shippingbox")
            }
            Menu {
                Button("Titre de section") { lineEditor = LineTarget(line: .section(""), isNew: true) }
                Button("Texte libre") { lineEditor = LineTarget(line: DocumentLine(kind: .note, quantity: 0, unit: "", unitPriceHT: 0, vatRate: 0), isNew: true) }
            } label: {
                Label("Ajouter un titre ou un texte", systemImage: "text.alignleft")
            }
        } header: {
            HStack {
                Text("Prestations")
                Spacer()
                if document.lines.count > 1 {
                    EditButton().font(.footnote).textCase(nil)
                }
            }
        } footer: {
            if !document.lines.isEmpty {
                Text("« Modifier » pour réorganiser, balayez vers la gauche pour supprimer, vers la droite pour dupliquer.")
            }
        }
    }

    private var totalsSection: some View {
        Section("Totaux") {
            if totals.totalDiscountHT > 0 {
                LabeledContent("Remises") { Text("−" + Money.format(totals.totalDiscountHT)).font(.amount(.body, weight: .regular)) }
            }
            LabeledContent(store.company.isVATRegistered ? "Total HT" : "Total") { AmountText(value: totals.totalHT, weight: .regular) }
            if chargesVAT {
                ForEach(totals.vatBuckets) { bucket in
                    LabeledContent("TVA \(Money.formatQuantity(bucket.rate)) %") { AmountText(value: bucket.vatAmount, weight: .regular) }
                }
                LabeledContent("Total TTC") { AmountText(value: totals.totalTTC, style: .headline) }
            }
            if totals.depositsDeductedTTC > 0 {
                LabeledContent("Acomptes déduits") { Text("−" + Money.format(totals.depositsDeductedTTC)).font(.amount()) }
                LabeledContent("Net à payer") { AmountText(value: totals.netToPay, style: .headline) }
            }
            if isQuote && totals.requestedDepositTTC > 0 {
                LabeledContent("Acompte à la commande") { AmountText(value: totals.requestedDepositTTC, weight: .regular) }
            }
            if !store.company.isVATRegistered {
                Text(LegalTexts.franchiseMention).font(.footnote).foregroundStyle(Theme.neutral)
            }
        }
    }

    private var datesSection: some View {
        Section {
            LabeledContent("Numéro") {
                Text(document.number.isEmpty ? (isQuote ? store.nextNumberPreview(for: .quote, date: document.issueDate) : "Attribué à l'émission") : document.number)
                    .foregroundStyle(Theme.neutral)
            }
            DatePicker(isQuote ? "Date du devis" : "Date d'émission", selection: $record.document.issueDate, displayedComponents: .date)
            if isQuote {
                DatePicker("Valable jusqu'au", selection: Binding(get: { document.validUntil ?? document.issueDate }, set: { record.document.validUntil = $0 }), in: document.issueDate..., displayedComponents: .date)
            } else {
                DatePicker("Date de la prestation", selection: Binding(get: { document.serviceDate ?? document.issueDate }, set: { record.document.serviceDate = $0 }), displayedComponents: .date)
                if document.kind != .creditNote {
                    DatePicker("Échéance", selection: Binding(get: { document.dueDate ?? document.issueDate }, set: { record.document.dueDate = $0 }), in: document.issueDate..., displayedComponents: .date)
                }
            }
            TextField("Objet (facultatif)", text: $record.document.title)
        } header: {
            Text("Références")
        } footer: {
            if !isQuote {
                Text("Le numéro de facture est attribué au moment de l'émission, dans l'ordre chronologique, sans rupture de séquence.")
            }
        }
    }

    private var optionsSection: some View {
        Section {
            DisclosureGroup("Remise globale, acompte, TVA", isExpanded: $showDetails) {
                DiscountEditor(title: "Remise globale", discount: $record.document.globalDiscount)
                if isQuote {
                    DepositRequestEditor(request: $record.document.depositRequest)
                }
                if store.company.isVATRegistered {
                    Toggle("Autoliquidation (TVA due par le client)", isOn: $record.document.reverseCharge)
                }
                TextField("Référence de commande du client", text: $record.document.purchaseOrderReference)
                if document.customer.kind == .business {
                    Toggle("Adresse de livraison différente", isOn: Binding(get: { document.customer.deliveryAddress != nil }, set: { record.document.customer.deliveryAddress = $0 ? PostalAddress() : nil }))
                    if document.customer.deliveryAddress != nil {
                        TextField("Adresse de livraison", text: Binding(get: { document.customer.deliveryAddress?.line1 ?? "" }, set: { record.document.customer.deliveryAddress?.line1 = $0 }))
                        TextField("Code postal", text: Binding(get: { document.customer.deliveryAddress?.postalCode ?? "" }, set: { record.document.customer.deliveryAddress?.postalCode = $0 }))
                        TextField("Ville", text: Binding(get: { document.customer.deliveryAddress?.city ?? "" }, set: { record.document.customer.deliveryAddress?.city = $0 }))
                    }
                }
            }
        }
    }

    private var textsSection: some View {
        Section("Conditions et notes") {
            TextField("Conditions de paiement (ex. 30 % à la commande, solde à la livraison)", text: $record.document.paymentTermsText, axis: .vertical)
            TextField("Conditions particulières", text: $record.document.specialConditions, axis: .vertical)
            TextField(document.kind == .creditNote ? "Motif de l'avoir" : "Notes", text: $record.document.notes, axis: .vertical)
        }
    }

    @ViewBuilder
    private var complianceSection: some View {
        let issues = ComplianceValidator.validate(document)
        if !issues.isEmpty && !document.lines.isEmpty {
            Section("Points à vérifier") {
                ForEach(issues) { issue in
                    Label {
                        Text(issue.message).font(.footnote)
                    } icon: {
                        Image(systemName: issue.severity == .blocking ? "exclamationmark.circle" : (issue.severity == .warning ? "exclamationmark.triangle" : "info.circle"))
                            .foregroundStyle(issue.severity == .blocking ? Theme.danger : (issue.severity == .warning ? Theme.ochre : Theme.neutral))
                    }
                }
            }
        }
    }

    // MARK: Actions

    private func apply(_ line: DocumentLine, isNew: Bool) {
        if isNew {
            record.document.lines.append(line)
        } else if let index = record.document.lines.firstIndex(where: { $0.id == line.id }) {
            record.document.lines[index] = line
        }
    }

    private func duplicateLine(_ line: DocumentLine) {
        guard let index = record.document.lines.firstIndex(where: { $0.id == line.id }) else { return }
        record.document.lines.insert(line.duplicated(), at: index + 1)
    }

    private func save() {
        // Les brouillons suivent les réglages courants de l'entreprise.
        record.document.seller = store.company
        do {
            try store.save(record)
            dismiss()
        } catch {
            self.error = PresentedError(error)
        }
    }
}

/// Résumé d'une ligne dans l'éditeur.
struct LineSummaryRow: View {
    let line: DocumentLine
    let totals: LineTotals?
    let chargesVAT: Bool

    var body: some View {
        switch line.kind {
        case .section:
            Text(line.designation.isEmpty ? "Titre de section" : line.designation)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.petrol)
        case .note:
            Text(line.designation.isEmpty ? "Texte libre" : line.designation)
                .font(.footnote.italic())
                .foregroundStyle(Theme.neutral)
                .lineLimit(3)
        case .item:
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.designation.isEmpty ? "Sans désignation" : line.designation)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                    Text(detail).font(.footnote).foregroundStyle(Theme.neutral)
                }
                Spacer()
                AmountText(value: totals?.netHT ?? 0, weight: .medium).foregroundStyle(Theme.ink)
            }
        }
    }

    private var detail: String {
        var parts = ["\(Money.formatQuantity(line.quantity)) \(line.unit) × \(Money.format(line.unitPriceHT, scale: Money.round(line.unitPriceHT) == line.unitPriceHT ? 2 : 4))"]
        if !line.discount.isNone { parts.append("remise \(line.discount.label)") }
        if chargesVAT { parts.append("TVA \(Money.formatQuantity(line.vatRate)) %") }
        return parts.joined(separator: " · ")
    }
}

/// Saisie de l'acompte demandé sur un devis.
struct DepositRequestEditor: View {
    @Binding var request: DepositRequest
    @State private var mode = 0
    @State private var value: Decimal = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Picker("Acompte à la commande", selection: $mode) {
                Text("Pas d'acompte").tag(0)
                Text("%").tag(1)
                Text("€ TTC").tag(2)
            }
            .pickerStyle(.segmented)
            if mode != 0 {
                LabeledDecimalRow(label: "Acompte", value: $value, suffix: mode == 1 ? "%" : "€", maxScale: 2)
            }
        }
        .onAppear {
            switch request {
            case .none: mode = 0
            case .percent(let rate): mode = 1; value = rate
            case .amount(let amount): mode = 2; value = amount
            }
        }
        .onChange(of: mode) { _, _ in update() }
        .onChange(of: value) { _, _ in update() }
    }

    private func update() {
        switch mode {
        case 1: request = .percent(min(value, 100))
        case 2: request = .amount(value)
        default: request = .none
        }
    }
}
