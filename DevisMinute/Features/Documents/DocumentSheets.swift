import SwiftUI
import PDFKit
import DevisCore
import DevisPDF

/// Aperçu fidèle du PDF (rendu identique au fichier partagé) et feuille de partage iOS.
struct PDFPreviewView: View {
    @Environment(AppDataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let record: DocumentRecord

    @State private var result: RenderResult?
    @State private var fileURL: URL?
    @State private var error: PresentedError?

    var body: some View {
        VStack(spacing: 0) {
            if let result {
                PDFKitView(data: result.data)
                if !result.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(result.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle").font(.footnote)
                        }
                    }
                    .foregroundStyle(Theme.ochre)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.ivory)
                }
            } else {
                ProgressView("Génération du PDF…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("\(result?.pageCount ?? 0) page\((result?.pageCount ?? 0) > 1 ? "s" : "")")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
            ToolbarItem(placement: .primaryAction) {
                if let fileURL {
                    ShareLink(item: fileURL, subject: Text(DocumentPDFRenderer.suggestedFileName(for: record.document))) {
                        Label("Partager", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .errorAlert($error)
        .task { @MainActor in
            let rendered = DocumentExportService.renderPDF(for: record, store: store)
            result = rendered
            do {
                fileURL = try DocumentExportService.temporaryFile(named: DocumentPDFRenderer.suggestedFileName(for: record.document), data: rendered.data)
            } catch {
                self.error = PresentedError(error)
            }
        }
    }
}

/// Affichage PDFKit.
struct PDFKitView: UIViewRepresentable {
    let data: Data

    final class Coordinator {
        var data: Data?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = UIColor(named: "Ivory") ?? .systemGroupedBackground
        view.document = PDFDocument(data: data)
        context.coordinator.data = data
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        guard context.coordinator.data != data else { return }
        view.document = PDFDocument(data: data)
        context.coordinator.data = data
    }
}

/// Enregistrement d'un paiement (total ou partiel).
struct PaymentSheet: View {
    @Environment(AppDataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let record: DocumentRecord
    let allRecords: [DocumentRecord]

    @State private var amount: Decimal = 0
    @State private var date = Date()
    @State private var method: PaymentMethod = .transfer
    @State private var note = ""
    @State private var error: PresentedError?

    private var balance: Decimal { Accounting.ledger(for: record, in: allRecords).balance }

    var body: some View {
        Form {
            Section {
                LabeledDecimalRow(label: "Montant reçu", value: $amount, maxScale: 2)
                Button("Solder la facture (\(Money.format(balance)))") { amount = balance }
                DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                Picker("Moyen de paiement", selection: $method) {
                    ForEach(PaymentMethod.allCases) { Text($0.label).tag($0) }
                }
                TextField("Note (facultatif)", text: $note)
            } footer: {
                Text("Solde restant dû : \(Money.format(balance)). Un paiement ne peut pas dépasser ce solde.")
            }
        }
        .appBackground()
        .navigationTitle("Paiement")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer") { save() }.fontWeight(.semibold).disabled(amount <= 0)
            }
        }
        .errorAlert($error)
    }

    private func save() {
        do {
            try store.addPayment(invoiceID: record.id, payment: PaymentRecord(date: date, amount: amount, method: method, note: note))
            dismiss()
        } catch {
            self.error = PresentedError(error)
        }
    }
}

/// Création d'un avoir (total ou partiel) : seule procédure de correction d'une facture émise.
struct CreditNoteSheet: View {
    @Environment(AppDataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let record: DocumentRecord
    let onCreated: (DocumentRecord) -> Void

    @State private var isPartial = false
    @State private var amountHT: Decimal = 0
    @State private var vatRate: Decimal = 20
    @State private var reason = ""
    @State private var error: PresentedError?

    var body: some View {
        Form {
            Section {
                Text("Une facture émise ne se modifie pas. Pour la corriger ou l'annuler, on établit un avoir qui y fait référence ; si nécessaire, une nouvelle facture est ensuite émise.")
                    .font(.footnote).foregroundStyle(Theme.neutral)
            }
            Section {
                Picker("Type d'avoir", selection: $isPartial) {
                    Text("Total (annulation)").tag(false)
                    Text("Partiel").tag(true)
                }
                .pickerStyle(.segmented)
                if isPartial {
                    LabeledDecimalRow(label: record.document.seller.isVATRegistered ? "Montant HT" : "Montant", value: $amountHT, maxScale: 2)
                    if record.document.chargesVAT {
                        VATRatePicker(rate: $vatRate)
                    }
                }
                TextField("Motif (imprimé sur l'avoir)", text: $reason, axis: .vertical)
            }
        }
        .appBackground()
        .navigationTitle("Avoir sur \(record.document.number)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Créer le brouillon") { create() }
                    .fontWeight(.semibold)
                    .disabled(reason.trimmed.isEmpty || (isPartial && amountHT <= 0))
            }
        }
        .errorAlert($error)
        .onAppear { vatRate = record.document.itemLines.first?.vatRate ?? 20 }
    }

    private func create() {
        do {
            let rate = record.document.chargesVAT ? vatRate : 0
            let created = try store.createCreditNote(invoiceID: record.id, partialAmountHT: isPartial ? amountHT : nil, vatRate: rate, reason: reason)
            dismiss()
            onCreated(created)
        } catch {
            self.error = PresentedError(error)
        }
    }
}

/// Facture d'acompte sur un devis.
struct DepositSheet: View {
    @Environment(AppDataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let record: DocumentRecord
    let onCreated: (DocumentRecord) -> Void

    @State private var amount: Decimal = 0
    @State private var error: PresentedError?

    private var totals: DocumentTotals { DocumentCalculator.totals(for: record.document) }

    var body: some View {
        Form {
            Section {
                LabeledContent("Total TTC du devis") { AmountText(value: totals.totalTTC, weight: .regular) }
                LabeledDecimalRow(label: "Acompte TTC", value: $amount, maxScale: 2)
                HStack {
                    ForEach([30, 40, 50], id: \.self) { percent in
                        Button("\(percent) %") { amount = Money.round(totals.totalTTC * Decimal(percent) / 100) }
                            .buttonStyle(.bordered)
                    }
                }
            } footer: {
                Text("La TVA de l'acompte suit la répartition des taux du devis. L'acompte sera déduit automatiquement de la facture de solde.")
            }
        }
        .appBackground()
        .navigationTitle("Facture d'acompte")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Créer le brouillon") { create() }
                    .fontWeight(.semibold)
                    .disabled(amount <= 0 || amount > totals.totalTTC)
            }
        }
        .errorAlert($error)
        .onAppear {
            let requested = totals.requestedDepositTTC
            amount = requested > 0 ? requested : Money.round(totals.totalTTC * 30 / 100)
        }
    }

    private func create() {
        do {
            let created = try store.createDepositInvoice(quoteID: record.id, amountTTC: amount)
            dismiss()
            onCreated(created)
        } catch {
            self.error = PresentedError(error)
        }
    }
}
