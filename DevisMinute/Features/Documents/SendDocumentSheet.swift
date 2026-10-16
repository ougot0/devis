import SwiftUI
import MessageUI
import DevisCore
import DevisPDF

/// Envoi en une touche : e-mail prérempli avec le PDF joint, ou partage vers une autre application.
/// En mode relance, le niveau (rappel, relance ferme, mise en demeure) choisit le texte.
struct SendDocumentSheet: View {
    enum Mode: Equatable {
        case send
        case reminder
    }

    @Environment(AppDataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let record: DocumentRecord
    let mode: Mode

    @State private var level: ReminderLevel = .friendly
    @State private var recipient = ""
    @State private var subject = ""
    @State private var messageBody = ""
    @State private var pdfURL: URL?
    @State private var pdfData: Data?
    @State private var showComposer = false
    @State private var error: PresentedError?
    @State private var prepared = false

    private var ledger: PaymentLedger { Accounting.ledger(for: record, in: store.allRecords()) }

    var body: some View {
        Form {
            if mode == .reminder {
                Section {
                    Picker("Type de relance", selection: $level) {
                        ForEach(ReminderLevel.allCases) { Text($0.label).tag($0) }
                    }
                    let history = record.reminders ?? []
                    if history.isEmpty {
                        Text("Aucune relance envoyée pour l'instant.").font(.footnote).foregroundStyle(Theme.neutral)
                    }
                    ForEach(history) { reminder in
                        LabeledContent(reminder.level.label, value: DateFormatting.short(reminder.date))
                            .font(.footnote)
                    }
                } header: {
                    Text("Relance")
                } footer: {
                    Text("\(Money.format(ledger.balance)) restant dû · \(ledger.daysOverdue(dueDate: record.document.dueDate, today: Date())) jour(s) de retard.")
                }
            }
            Section("Destinataire") {
                TextField("E-mail du client", text: $recipient)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Objet", text: $subject)
            }
            Section {
                TextEditor(text: $messageBody)
                    .frame(minHeight: 260)
                    .font(.callout)
            } header: {
                Text("Message")
            } footer: {
                Text("Le PDF \(record.document.number.isEmpty ? "" : "« \(DocumentPDFRenderer.suggestedFileName(for: record.document)) » ")est joint automatiquement. Vous pouvez modifier le texte.")
            }
            Section {
                Button {
                    if MailComposer.canSendMail { showComposer = true } else { error = PresentedError(message: "Aucun compte e-mail n'est configuré dans l'app Mail. Utilisez « Autre application » ci-dessous (Gmail, WhatsApp, Messages…).") }
                } label: {
                    Label("Envoyer par e-mail", systemImage: "paperplane.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .disabled(pdfData == nil)
                if let pdfURL {
                    ShareLink(item: pdfURL, subject: Text(subject), message: Text(messageBody)) {
                        Label("Autre application (WhatsApp, Messages…)", systemImage: "square.and.arrow.up")
                    }
                    if mode == .reminder {
                        Button("J'ai envoyé cette relance par un autre moyen") { recordReminder() }
                    }
                }
            }
        }
        .appBackground()
        .navigationTitle(mode == .reminder ? "Relancer le client" : "Envoyer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
        }
        .sheet(isPresented: $showComposer) {
            MailComposer(
                recipient: recipient.trimmed,
                subject: subject,
                body: messageBody,
                attachment: pdfData.map { MailComposer.Attachment(data: $0, mimeType: "application/pdf", fileName: DocumentPDFRenderer.suggestedFileName(for: record.document)) }
            ) { result in
                showComposer = false
                if result == .sent { didSend() }
            }
            .ignoresSafeArea()
        }
        .onChange(of: level) { _, _ in fillTemplate() }
        .errorAlert($error)
        .task { prepare() }
    }

    private func prepare() {
        guard !prepared else { return }
        prepared = true
        if mode == .reminder { level = ReminderPolicy.suggestedLevel(after: record.reminders ?? []) }
        fillTemplate()
        let rendered = DocumentExportService.renderPDF(for: record, store: store)
        pdfData = rendered.data
        pdfURL = try? DocumentExportService.temporaryFile(named: DocumentPDFRenderer.suggestedFileName(for: record.document), data: rendered.data)
    }

    private func fillTemplate() {
        let draft: EmailDraft
        switch mode {
        case .send:
            draft = EmailTemplates.sending(record.document, balance: record.isIssuedInvoice ? ledger.balance : nil)
        case .reminder:
            draft = EmailTemplates.reminder(level, for: record.document, balance: ledger.balance, daysOverdue: ledger.daysOverdue(dueDate: record.document.dueDate, today: Date()))
        }
        if recipient.isEmpty { recipient = draft.recipient }
        subject = draft.subject
        messageBody = draft.body
    }

    private func didSend() {
        switch mode {
        case .reminder:
            recordReminder()
        case .send:
            // Un devis envoyé par e-mail passe automatiquement en « Envoyé ».
            if record.document.kind == .quote, record.quoteStatus == .draft {
                try? store.setQuoteStatus(id: record.id, to: .sent)
            }
            dismiss()
        }
    }

    private func recordReminder() {
        do {
            try store.recordReminder(invoiceID: record.id, level: level)
            dismiss()
        } catch {
            self.error = PresentedError(error)
        }
    }
}
