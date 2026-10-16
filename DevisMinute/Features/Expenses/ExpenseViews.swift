import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import VisionKit
import DevisCore

/// Dépenses de l'entreprise, regroupées par mois, avec le bénéfice estimé.
struct ExpenseListView: View {
    @Environment(AppDataStore.self) private var store
    @State private var expenses: [ExpenseRecord] = []
    @State private var search = ""
    @State private var editing: ExpenseRecord?
    @State private var exportFile: ExportFile?
    @State private var showExporter = false
    @State private var error: PresentedError?

    private var filtered: [ExpenseRecord] {
        let query = search.trimmed.lowercased()
        guard !query.isEmpty else { return expenses }
        return expenses.filter { [$0.supplier, $0.label, $0.category.label, $0.notes].joined(separator: " ").lowercased().contains(query) }
    }

    private var months: [(month: Date, items: [ExpenseRecord])] {
        let calendar = Calendar.devisMinute
        let grouped = Dictionary(grouping: filtered) { calendar.dateInterval(of: .month, for: $0.date)?.start ?? $0.date }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0]!.sorted { $0.date > $1.date }) }
    }

    var body: some View {
        List {
            Section {
                ProfitCard(summary: store.profit(interval: Calendar.devisMinute.dateInterval(of: .month, for: Date())), title: "Ce mois-ci")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            ForEach(months, id: \.month) { group in
                Section {
                    ForEach(group.items) { expense in
                        Button { editing = expense } label: { ExpenseRow(expense: expense) }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button(role: .destructive) { delete(expense) } label: { Label("Supprimer", systemImage: "trash") }
                            }
                    }
                } header: {
                    HStack {
                        Text(MicroCalculator.title(for: DateInterval(start: group.month, duration: 86_400), frequency: .monthly))
                        Spacer()
                        Text(Money.format(group.items.reduce(Decimal(0)) { $0 + $1.amountTTC }) + " TTC")
                    }
                }
            }
        }
        .overlay {
            if expenses.isEmpty {
                EmptyStateView(title: "Aucune dépense", message: "Ajoutez vos achats, carburant, abonnements… et scannez les tickets : DevisMinute calcule votre vrai bénéfice.", systemImage: "cart")
                    .padding(.top, 160)
            }
        }
        .searchable(text: $search, prompt: "Fournisseur, libellé, catégorie")
        .navigationTitle("Dépenses")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = ExpenseRecord(date: Date(), amountTTC: 0) } label: { Label("Nouvelle dépense", systemImage: "plus") }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Exporter en CSV") {
                    exportFile = ExportFile(data: CSVExporter.expenses(expenses))
                    showExporter = true
                }
                .disabled(expenses.isEmpty)
            }
        }
        .sheet(item: $editing) { expense in
            NavigationStack { ExpenseEditorView(expense: expense) }
        }
        .fileExporter(isPresented: $showExporter, document: exportFile, contentType: .commaSeparatedText, defaultFilename: "DevisMinute depenses \(DocumentExportService.dateStamp())") { _ in }
        .errorAlert($error)
        .appBackground()
        .onAppear(perform: reload)
        .onChange(of: store.revision) { _, _ in reload() }
    }

    private func reload() { expenses = store.allExpenses() }

    private func delete(_ expense: ExpenseRecord) {
        do { try store.deleteExpense(id: expense.id) } catch { self.error = PresentedError(error) }
    }
}

/// Carte « chiffre d'affaires − dépenses = bénéfice ».
struct ProfitCard: View {
    let summary: ProfitSummary
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Bénéfice estimé · \(title)").font(.subheadline.weight(.semibold)).opacity(0.85)
            Text(Money.format(summary.profit))
                .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.6)
            HStack(spacing: Theme.Space.l) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Facturé HT").font(.caption).opacity(0.75)
                    Text(Money.format(summary.revenueHT)).font(.amount(.footnote))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dépenses").font(.caption).opacity(0.75)
                    Text("− " + Money.format(summary.expenses)).font(.amount(.footnote))
                }
                if let rate = summary.marginRate {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Marge").font(.caption).opacity(0.75)
                        Text("\(Money.formatQuantity(rate)) %").font(.amount(.footnote))
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .card(fill: summary.profit < 0 ? Theme.danger : Theme.success)
        .accessibilityElement(children: .combine)
    }
}

private struct ExpenseRow: View {
    let expense: ExpenseRecord

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: expense.category.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.petrol)
                .frame(width: 36, height: 36)
                .background(Theme.petrol.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.title).foregroundStyle(Theme.ink).lineLimit(1)
                Text([DateFormatting.short(expense.date), expense.category.label].joined(separator: " · "))
                    .font(.footnote).foregroundStyle(Theme.neutral).lineLimit(1)
            }
            Spacer(minLength: Theme.Space.s)
            VStack(alignment: .trailing, spacing: 2) {
                AmountText(value: expense.amountTTC)
                if expense.receiptJPEG != nil {
                    Image(systemName: "paperclip").font(.caption).foregroundStyle(Theme.neutral)
                        .accessibilityLabel("Justificatif joint")
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// Saisie d'une dépense, avec scan ou photo du justificatif.
struct ExpenseEditorView: View {
    @Environment(AppDataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var expense: ExpenseRecord
    @State private var vatRate: Decimal? = 20
    @State private var photoItem: PhotosPickerItem?
    @State private var showScanner = false
    @State private var showReceipt = false
    @State private var error: PresentedError?
    private let isNew: Bool

    init(expense: ExpenseRecord) {
        _expense = State(initialValue: expense)
        isNew = expense.amountTTC == 0
        if expense.amountTTC > 0 {
            let match = [Decimal(20), 10, Decimal.exact("5.5"), 0].first { ExpenseRecord.vat(fromTTC: expense.amountTTC, rate: $0) == expense.vatAmount }
            _vatRate = State(initialValue: match)
        }
    }

    private static let rates: [Decimal] = [20, 10, Decimal.exact("5.5"), 0]

    var body: some View {
        Form {
            Section {
                receiptButtons
            } header: {
                Text("Justificatif")
            } footer: {
                Text("Le ticket ou la facture fournisseur est conservé dans l'application et dans vos sauvegardes.")
            }
            Section("Montant") {
                LabeledDecimalRow(label: "Montant TTC", value: $expense.amountTTC, maxScale: 2)
                Picker("Taux de TVA", selection: $vatRate) {
                    ForEach(Self.rates, id: \.self) { Text("\(Money.formatQuantity($0)) %").tag(Decimal?.some($0)) }
                    Text("Autre montant").tag(Decimal?.none)
                }
                if vatRate == nil {
                    LabeledDecimalRow(label: "TVA", value: $expense.vatAmount, maxScale: 2)
                } else {
                    LabeledContent("TVA") { AmountText(value: expense.vatAmount, weight: .regular) }
                }
                LabeledContent("Montant HT") { AmountText(value: expense.amountHT, weight: .regular) }
            }
            Section("Détails") {
                DatePicker("Date", selection: $expense.date, in: ...Date().addingTimeInterval(86_400), displayedComponents: .date)
                TextField("Fournisseur", text: $expense.supplier)
                TextField("Libellé (facultatif)", text: $expense.label)
                Picker("Catégorie", selection: $expense.category) {
                    ForEach(ExpenseCategory.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                }
                Picker("Payé par", selection: $expense.paymentMethod) {
                    ForEach(PaymentMethod.allCases) { Text($0.label).tag($0) }
                }
                TextField("Notes", text: $expense.notes, axis: .vertical)
            }
            if !store.company.isVATRegistered {
                Section {
                    Text("En franchise de TVA, la TVA de vos achats n'est pas récupérable : le bénéfice est calculé sur le montant TTC.")
                        .font(.footnote).foregroundStyle(Theme.neutral)
                }
            }
            if !isNew {
                Section {
                    Button("Supprimer la dépense", role: .destructive) {
                        do { try store.deleteExpense(id: expense.id); dismiss() } catch { self.error = PresentedError(error) }
                    }
                }
            }
        }
        .appBackground()
        .navigationTitle(isNew ? "Nouvelle dépense" : "Dépense")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer") { save() }.fontWeight(.semibold).disabled(expense.amountTTC <= 0)
            }
        }
        .onChange(of: expense.amountTTC) { _, _ in applyRate() }
        .onChange(of: vatRate) { _, _ in applyRate() }
        .onChange(of: photoItem) { _, item in loadPhoto(item) }
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScanner { image in
                showScanner = false
                if let image { expense.receiptJPEG = ReceiptProcessor.jpeg(from: image) }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showReceipt) {
            if let data = expense.receiptJPEG, let image = UIImage(data: data) {
                NavigationStack {
                    ScrollView { Image(uiImage: image).resizable().scaledToFit().padding() }
                        .navigationTitle("Justificatif")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { showReceipt = false } } }
                }
            }
        }
        .errorAlert($error)
    }

    @ViewBuilder
    private var receiptButtons: some View {
        if let data = expense.receiptJPEG, let image = UIImage(data: data) {
            HStack(spacing: Theme.Space.m) {
                Button { showReceipt = true } label: {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: 64, height: 84).clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Voir le justificatif")
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("Justificatif joint").font(.subheadline.weight(.medium))
                    Button("Retirer", role: .destructive) { expense.receiptJPEG = nil }.font(.footnote)
                }
            }
        } else {
            if VNDocumentCameraViewController.isSupported {
                Button { showScanner = true } label: { Label("Scanner le ticket", systemImage: "doc.viewfinder") }
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Choisir une photo", systemImage: "photo")
            }
        }
    }

    private func applyRate() {
        guard let vatRate else { return }
        expense.vatAmount = ExpenseRecord.vat(fromTTC: expense.amountTTC, rate: vatRate)
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task { @MainActor in
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                expense.receiptJPEG = ReceiptProcessor.jpeg(from: image)
            }
            photoItem = nil
        }
    }

    private func save() {
        do {
            try store.save(expense: expense)
            dismiss()
        } catch {
            self.error = PresentedError(error)
        }
    }
}

/// Scanner de documents d'iOS (recadrage et redressement automatiques, sur l'appareil).
struct DocumentScanner: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: (UIImage?) -> Void
        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            onFinish(scan.pageCount > 0 ? scan.imageOfPage(at: 0) : nil)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { onFinish(nil) }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { onFinish(nil) }
    }
}

/// Justificatifs : réduits à 1600 px et compressés en JPEG pour limiter la taille des sauvegardes.
enum ReceiptProcessor {
    static func jpeg(from image: UIImage, maxDimension: CGFloat = 1600) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.7)
    }
}
