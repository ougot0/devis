import SwiftUI
import UIKit
import DevisCore

/// Fiche d'un document : aperçu, statut, actions, paiements, intégrité.
struct DocumentDetailView: View {
    @Environment(AppDataStore.self) private var store
    @Environment(PurchaseManager.self) private var purchases
    @Environment(\.dismiss) private var dismiss
    let documentID: UUID

    @State private var record: DocumentRecord?
    @State private var allRecords: [DocumentRecord] = []
    @State private var editor: DashboardView.EditorTarget?
    @State private var sheet: SheetKind?
    @State private var shareURL: URL?
    @State private var error: PresentedError?
    @State private var confirmIssue = false
    @State private var confirmDelete = false
    @State private var celebration: Celebration?

    enum SheetKind: Identifiable {
        case preview, payment, creditNote, deposit, signature, send, reminder
        var id: Int { hashValue }
    }

    var body: some View {
        Group {
            if let record {
                content(record)
            } else {
                EmptyStateView(title: "Document introuvable", message: "Il a peut-être été supprimé.")
            }
        }
        .background(Theme.ivory)
        .onAppear(perform: reload)
        .onChange(of: store.revision) { _, _ in reload() }
        .sheet(item: $editor) { target in
            NavigationStack { DocumentEditorView(record: target.record) }
        }
        .sheet(item: $sheet) { kind in
            if let record {
                NavigationStack {
                    switch kind {
                    case .preview: PDFPreviewView(record: record)
                    case .payment: PaymentSheet(record: record, allRecords: allRecords)
                    case .creditNote: CreditNoteSheet(record: record) { created in openEditorAfterDismiss(created) }
                    case .deposit: DepositSheet(record: record) { created in openEditorAfterDismiss(created) }
                    case .signature: SignatureSheet(record: record) {}
                    case .send: SendDocumentSheet(record: record, mode: .send)
                    case .reminder: SendDocumentSheet(record: record, mode: .reminder)
                    }
                }
            }
        }
        .errorAlert($error)
        .celebration($celebration)
        .animation(.easeInOut(duration: 0.2), value: celebration)
    }

    /// Ouvre l'éditeur une fois la feuille précédente refermée (deux feuilles ne peuvent se chevaucher).
    private func openEditorAfterDismiss(_ created: DocumentRecord) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            editor = DashboardView.EditorTarget(record: created)
        }
    }

    private func reload() {
        let previous = record
        record = store.record(id: documentID)
        allRecords = store.allRecords()
        if let previous, let current = record { celebrateIfNeeded(from: previous, to: current) }
    }

    /// Fête la signature d'un devis ou le dernier paiement d'une facture.
    private func celebrateIfNeeded(from old: DocumentRecord, to new: DocumentRecord) {
        if old.signature == nil, let signature = new.signature {
            let total = DocumentCalculator.totals(for: new.document).totalTTC
            celebration = Celebration(title: "Devis signé !", subtitle: "\(signature.signerName) a accepté \(Money.format(total)).")
            return
        }
        guard new.isIssuedInvoice, new.document.kind != .creditNote, new.payments.count > old.payments.count else { return }
        let ledger = Accounting.ledger(for: new, in: allRecords)
        if ledger.balance == 0 {
            celebration = Celebration(title: "Facture payée !", subtitle: "\(Money.format(ledger.totalPaid)) encaissés · \(new.document.customer.name)")
        }
    }

    @ViewBuilder
    private func content(_ record: DocumentRecord) -> some View {
        let document = record.document
        let totals = DocumentCalculator.totals(for: document)
        let status = DocumentStatusInfo(record: record, allRecords: allRecords)
        List {
            Section {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(document.kind.title).font(.footnote.weight(.semibold)).foregroundStyle(Theme.neutral)
                        Spacer()
                        StatusBadge(text: status.label, tone: status.tone)
                    }
                    Text(document.customer.name.isEmpty ? "Client non renseigné" : document.customer.name)
                        .font(.title3.weight(.semibold))
                    if !document.title.isEmpty { Text(document.title).foregroundStyle(Theme.neutral) }
                    AmountText(value: totals.totalTTC, style: .largeTitle)
                        .padding(.top, Theme.Space.xs)
                    Text(subtitle(record, totals: totals)).font(.footnote).foregroundStyle(Theme.neutral)
                }
                .padding(.vertical, Theme.Space.xs)
            }

            Section {
                if record.imported {
                    Label("Facture importée d'un autre logiciel : le document d'origine fait foi. Elle sert d'archive pour l'historique, les statistiques et le suivi des paiements.", systemImage: "tray.and.arrow.down")
                        .font(.footnote).foregroundStyle(Theme.neutral)
                } else {
                    Button { sheet = .preview } label: { Label("Aperçu et partage du PDF", systemImage: "doc.richtext") }
                }
                actions(record)
            }

            if document.kind.isInvoiceLike && record.isIssuedInvoice && document.kind != .creditNote {
                paymentsSection(record)
            }

            Section("Détail") {
                ForEach(document.lines) { line in
                    LineSummaryRow(line: line, totals: totals.lines[line.id], chargesVAT: document.chargesVAT)
                }
                LabeledContent(document.seller.isVATRegistered ? "Total HT" : "Total") { AmountText(value: totals.totalHT, weight: .regular) }
                if document.chargesVAT {
                    LabeledContent("TVA") { AmountText(value: totals.totalVAT, weight: .regular) }
                }
            }

            if let signature = record.signature {
                signatureSection(signature, document: document)
            }

            if record.isIssuedInvoice && !record.imported {
                integritySection(record)
            }
        }
        .appBackground()
        .navigationTitle(document.number.isEmpty ? document.kind.title : document.number)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Émettre définitivement ?", isPresented: $confirmIssue, titleVisibility: .visible) {
            Button("Émettre \(document.kind == .creditNote ? "l'avoir" : "la facture")") { issue(record) }
        } message: {
            Text("Un numéro définitif (\(store.nextNumberPreview(for: document.kind, date: document.issueDate))) sera attribué. Le document ne pourra plus être modifié ni supprimé ; une correction passera par un avoir.")
        }
        .confirmationDialog("Supprimer ce brouillon ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) { delete(record) }
        }
    }

    private func subtitle(_ record: DocumentRecord, totals: DocumentTotals) -> String {
        let document = record.document
        var parts = ["\(document.number.isEmpty ? "Sans numéro" : document.number) du \(DateFormatting.short(document.issueDate))"]
        if document.kind == .quote, let valid = document.validUntil { parts.append("valable jusqu'au \(DateFormatting.short(valid))") }
        if document.kind != .quote, let due = document.dueDate, document.kind != .creditNote { parts.append("échéance \(DateFormatting.short(due))") }
        if !document.sourceQuoteNumber.isEmpty { parts.append("devis \(document.sourceQuoteNumber)") }
        if !document.correctedInvoiceNumber.isEmpty { parts.append("corrige \(document.correctedInvoiceNumber)") }
        return parts.joined(separator: " · ")
    }

    // MARK: Actions selon le type et l'état

    @ViewBuilder
    private func actions(_ record: DocumentRecord) -> some View {
        let document = record.document
        if document.kind == .quote, let status = record.quoteStatus {
            let effective = QuoteLifecycle.effectiveStatus(status, validUntil: document.validUntil, today: Date())
            if status != .refused {
                Button { sheet = .send } label: { Label("Envoyer par e-mail", systemImage: "paperplane.fill") }
            }
            if QuoteLifecycle.canSign(effective) {
                Button { sheet = .signature } label: { Label("Faire signer le client", systemImage: "signature") }
                    .foregroundStyle(Theme.ochre)
            }
            if status.isEditable {
                Button { editor = DashboardView.EditorTarget(record: record) } label: { Label("Modifier", systemImage: "pencil") }
            }
            if status == .draft {
                Button { setStatus(.sent) } label: { Label("Marquer comme envoyé", systemImage: "paperplane") }
            }
            if effective == .sent || effective == .expired {
                Button { setStatus(.accepted) } label: { Label("Marquer comme accepté", systemImage: "checkmark") }
                Button { setStatus(.refused) } label: { Label("Marquer comme refusé", systemImage: "xmark") }
            }
            if status == .sent {
                Button { setStatus(.draft) } label: { Label("Repasser en brouillon", systemImage: "arrow.uturn.backward") }
            }
            if QuoteLifecycle.canConvertToInvoice(status) {
                Button { sheet = .deposit } label: { Label("Facturer un acompte", systemImage: "banknote") }
                Button { convert(record) } label: { Label("Convertir en facture", systemImage: "arrow.right.doc.on.clipboard") }
                    .foregroundStyle(Theme.ochre)
            }
            Button { duplicate(record) } label: { Label("Dupliquer", systemImage: "plus.square.on.square") }
            Button(role: .destructive) { confirmDelete = true } label: { Label("Supprimer", systemImage: "trash") }
        } else if !record.isIssuedInvoice {
            Button { editor = DashboardView.EditorTarget(record: record) } label: { Label("Modifier le brouillon", systemImage: "pencil") }
            Button { confirmIssue = true } label: { Label(document.kind == .creditNote ? "Émettre l'avoir" : "Émettre la facture", systemImage: "checkmark.seal") }
                .foregroundStyle(Theme.ochre)
            let issues = ComplianceValidator.validate(document)
            if ComplianceValidator.hasBlockingIssues(issues) {
                ForEach(issues.filter { $0.severity == .blocking }) { issue in
                    Label(issue.message, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(Theme.danger)
                }
            }
            Button(role: .destructive) { confirmDelete = true } label: { Label("Supprimer le brouillon", systemImage: "trash") }
        } else {
            if !record.imported {
                Button { sheet = .send } label: { Label("Envoyer par e-mail", systemImage: "paperplane.fill") }
            }
            if document.kind != .creditNote,
               Accounting.ledger(for: record, in: allRecords).state(dueDate: document.dueDate, today: Date()) == .overdue {
                Button { sheet = .reminder } label: { Label("Relancer le client", systemImage: "bell.badge") }
                    .foregroundStyle(Theme.ochre)
            }
            if document.kind != .creditNote {
                Button { sheet = .payment } label: { Label("Enregistrer un paiement", systemImage: "eurosign.circle") }
                Button { sheet = .creditNote } label: { Label("Corriger ou annuler par un avoir", systemImage: "arrow.uturn.left.circle") }
            }
            Button { duplicate(record) } label: { Label("Dupliquer en nouvelle facture", systemImage: "plus.square.on.square") }
            if purchases.isUnlocked(.structuredExport) && !record.imported {
                Button { exportCII(record) } label: { Label("Exporter les données structurées (XML)", systemImage: "chevron.left.forwardslash.chevron.right") }
            }
            if let shareURL {
                ShareLink(item: shareURL) { Label("Partager le fichier XML", systemImage: "square.and.arrow.up") }
            }
        }
    }

    private func paymentsSection(_ record: DocumentRecord) -> some View {
        let ledger = Accounting.ledger(for: record, in: allRecords)
        return Section {
            LabeledContent("Montant dû") { AmountText(value: ledger.amountDue, weight: .regular) }
            if ledger.creditedAmount > 0 {
                LabeledContent("Avoirs imputés") { Text("−" + Money.format(ledger.creditedAmount)).font(.amount(.body, weight: .regular)) }
            }
            ForEach(record.payments) { payment in
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(payment.method.label) du \(DateFormatting.short(payment.date))")
                        if !payment.note.isEmpty { Text(payment.note).font(.footnote).foregroundStyle(Theme.neutral) }
                    }
                    Spacer()
                    AmountText(value: payment.amount, weight: .regular).foregroundStyle(Theme.success)
                }
                .swipeActions {
                    Button(role: .destructive) {
                        do { try store.removePayment(invoiceID: record.id, paymentID: payment.id) } catch { self.error = PresentedError(error) }
                    } label: { Label("Supprimer", systemImage: "trash") }
                }
            }
            LabeledContent("Solde restant dû") { AmountText(value: ledger.balance, style: .headline) }
            ForEach(record.reminders ?? []) { reminder in
                Label("\(reminder.level.label) envoyé le \(DateFormatting.short(reminder.date))", systemImage: "bell")
                    .font(.footnote).foregroundStyle(Theme.neutral)
            }
        } header: {
            Text("Paiements")
        } footer: {
            Text("Les paiements sont déclarés par vous : DevisMinute n'est relié à aucune banque.")
        }
    }

    private func signatureSection(_ signature: QuoteSignature, document: BusinessDocument) -> some View {
        Section {
            if let image = UIImage(data: signature.imageJPEG) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 90)
                    .frame(maxWidth: .infinity)
                    .padding(Theme.Space.s)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("Signature de \(signature.signerName)")
            }
            LabeledContent("Signé par", value: signature.signerName)
            LabeledContent("Le", value: signature.signedAt.formatted(date: .abbreviated, time: .shortened))
            if !signature.place.isEmpty { LabeledContent("À", value: signature.place) }
            let intact = signature.matches(document)
            Label(intact ? "Devis identique à la version signée" : "Le devis a changé depuis la signature", systemImage: intact ? "checkmark.seal" : "exclamationmark.triangle")
                .foregroundStyle(intact ? Theme.success : Theme.danger)
        } header: {
            Text("Bon pour accord")
        } footer: {
            Text("Signature électronique simple recueillie sur cet iPhone. Elle figure sur le PDF du devis.")
        }
    }

    private func integritySection(_ record: DocumentRecord) -> some View {
        let valid = record.seal.map { DocumentSealer.verify(record.document, seal: $0) } ?? false
        return Section {
            Label(valid ? "Contenu identique à l'émission" : "Le contenu ne correspond pas au sceau", systemImage: valid ? "checkmark.seal" : "exclamationmark.triangle")
                .foregroundStyle(valid ? Theme.success : Theme.danger)
            if let seal = record.seal {
                LabeledContent("Émise le") { Text(seal.sealedAt.formatted(date: .abbreviated, time: .shortened)) }
                Text("Empreinte SHA-256 : \(seal.contentHash.prefix(16))…")
                    .font(.caption.monospaced()).foregroundStyle(Theme.neutral)
                    .textSelection(.enabled)
            }
        } header: {
            Text("Intégrité")
        } footer: {
            Text("Protection locale contre les modifications. Ce n'est ni une signature électronique ni une certification.")
        }
    }

    // MARK: Opérations

    private func run(_ operation: () throws -> Void) {
        do { try operation() } catch { self.error = PresentedError(error) }
    }

    private func setStatus(_ status: QuoteStatus) {
        run { try store.setQuoteStatus(id: documentID, to: status) }
    }

    private func issue(_ record: DocumentRecord) {
        run { _ = try store.issue(id: record.id) }
    }

    private func convert(_ record: DocumentRecord) {
        run {
            let created = try store.convertToInvoice(quoteID: record.id)
            editor = DashboardView.EditorTarget(record: created)
        }
    }

    private func duplicate(_ record: DocumentRecord) {
        run {
            let created = try store.duplicate(id: record.id)
            editor = DashboardView.EditorTarget(record: created)
        }
    }

    private func delete(_ record: DocumentRecord) {
        run {
            try store.delete(id: record.id)
            dismiss()
        }
    }

    private func exportCII(_ record: DocumentRecord) {
        run { shareURL = try DocumentExportService.ciiFile(for: record) }
    }
}
