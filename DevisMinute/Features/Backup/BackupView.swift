import SwiftUI
import UniformTypeIdentifiers
import DevisCore

/// Sauvegarde complète, restauration vérifiée, exports CSV et imports.
struct BackupView: View {
    @Environment(DataStore.self) private var store
    @Environment(PurchaseManager.self) private var purchases

    @State private var usePassword = true
    @State private var password = ""
    @State private var passwordConfirmation = ""
    @State private var exportFile: ExportFile?
    @State private var exportName = ""
    @State private var exportType: UTType = .json
    @State private var showExporter = false
    @State private var importKind: ImportKind?
    @State private var showImporter = false
    @State private var pendingRestore: PendingRestore?
    @State private var restorePassword = ""
    @State private var askPassword = false
    @State private var inspectionItem: InspectionItem?
    @State private var message: String?
    @State private var error: PresentedError?
    @State private var working = false

    enum ImportKind { case backup, customers, catalog }

    struct PendingRestore: Identifiable {
        let id = UUID()
        let data: Data
        let encrypted: Bool
    }

    var body: some View {
        Form {
            Section {
                Toggle("Protéger par un mot de passe", isOn: $usePassword)
                if usePassword {
                    SecureField("Mot de passe (8 caractères minimum)", text: $password)
                        .textContentType(.newPassword)
                    SecureField("Confirmation", text: $passwordConfirmation)
                        .textContentType(.newPassword)
                }
                Button { createBackup() } label: {
                    if working { ProgressView() } else { Label("Créer une sauvegarde", systemImage: "externaldrive.badge.plus") }
                }
                .disabled(working || (usePassword && (password.count < 8 || password != passwordConfirmation)))
            } header: {
                Text("Sauvegarde complète")
            } footer: {
                Text("Le fichier contient toutes vos données : entreprise, clients, catalogue, devis, factures, paiements et réglages. Avec un mot de passe, il est chiffré (AES-256) : sans ce mot de passe, il est impossible de le restaurer. Conservez-le hors de l'iPhone (Fichiers, iCloud Drive, ordinateur).")
            }

            Section {
                Button { importKind = .backup; showImporter = true } label: { Label("Restaurer une sauvegarde", systemImage: "arrow.counterclockwise") }
            } footer: {
                Text("Le fichier est vérifié (intégrité, cohérence des factures) avant toute modification. La restauration remplace l'ensemble des données actuelles.")
            }

            Section {
                if purchases.isUnlocked(.csvExport) {
                    Button("Factures, avoirs et règlements (CSV)") { exportCSV(CSVExporter.invoices(store.allRecords()), name: "factures") }
                    Button("Ventilation de la TVA (CSV)") { exportCSV(CSVExporter.vatBreakdown(store.allRecords()), name: "tva") }
                    Button("Encaissements (CSV)") { exportCSV(CSVExporter.payments(store.allRecords()), name: "encaissements") }
                    Button("Devis (CSV)") { exportCSV(CSVExporter.quotes(store.allRecords()), name: "devis") }
                    Button("Clients (CSV)") { exportCSV(CSVExporter.customers(store.allCustomers()), name: "clients") }
                    Button("Catalogue (CSV)") { exportCSV(CSVExporter.catalog(store.allCatalogItems()), name: "catalogue") }
                } else {
                    NavigationLink("Exports CSV — version complète") { PremiumView() }
                }
            } header: {
                Text("Exports pour tableur ou comptable")
            } footer: {
                Text("Séparateur « ; », virgule décimale, encodage UTF-8 : s'ouvre directement dans Excel ou Numbers. Ces fichiers ne sont pas chiffrés : partagez-les avec précaution.")
            }

            Section {
                Button("Importer des clients (CSV)") { importKind = .customers; showImporter = true }
                Button("Importer un catalogue (CSV)") { importKind = .catalog; showImporter = true }
            } header: {
                Text("Importer")
            } footer: {
                Text("Clients : colonnes Nom, Contact, Adresse, Code postal, Ville, Email, Téléphone, SIREN, TVA, Type. Catalogue : Nom, Prix (obligatoires), Description, Catégorie, Taux TVA, Unité, Coût de revient, Prix TTC (oui/non).")
            }
        }
        .appBackground()
        .navigationTitle("Sauvegarde")
        .fileExporter(isPresented: $showExporter, document: exportFile, contentType: exportType, defaultFilename: exportName) { result in
            switch result {
            case .success: message = "Fichier enregistré."
            case .failure(let failure): error = PresentedError(failure)
            }
            password = ""
            passwordConfirmation = ""
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: importKind == .backup ? [.json, .data] : [.commaSeparatedText, .plainText, .data]) { result in
            handleImport(result)
        }
        .alert("Mot de passe de la sauvegarde", isPresented: $askPassword) {
            SecureField("Mot de passe", text: $restorePassword)
            Button("Annuler", role: .cancel) { pendingRestore = nil; restorePassword = "" }
            Button("Vérifier") { inspectPending() }
        }
        .sheet(item: $inspectionItem, onDismiss: { pendingRestore = nil }) { item in
            NavigationStack {
                RestoreConfirmationView(inspection: item.inspection) { confirm in
                    if confirm { restore(item.inspection.snapshot) }
                }
            }
        }
        .alert("DevisMinute", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(message ?? "") }
        .errorAlert($error)
    }

    struct InspectionItem: Identifiable {
        let id = UUID()
        let inspection: BackupInspection
    }

    // MARK: Actions

    private func createBackup() {
        working = true
        let snapshot = store.makeSnapshot(appVersion: AppConfiguration.appVersion)
        let secret = usePassword ? password : nil
        Task.detached(priority: .userInitiated) {
            do {
                let data = try BackupService.makeArchive(snapshot, password: secret)
                await MainActor.run {
                    exportFile = ExportFile(data: data)
                    exportType = .json
                    exportName = "Sauvegarde DevisMinute \(DocumentExportService.dateStamp())"
                    working = false
                    showExporter = true
                }
            } catch {
                await MainActor.run {
                    self.error = PresentedError(error)
                    working = false
                }
            }
        }
    }

    private func exportCSV(_ data: Data, name: String) {
        exportFile = ExportFile(data: data)
        exportType = .commaSeparatedText
        exportName = "DevisMinute \(name) \(DocumentExportService.dateStamp())"
        showExporter = true
    }

    private func readFile(_ url: URL) throws -> Data {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }

    private func handleImport(_ result: Result<URL, Error>) {
        do {
            let data = try readFile(result.get())
            switch importKind {
            case .backup:
                let envelope = try BackupService.readEnvelope(data)
                pendingRestore = PendingRestore(data: data, encrypted: envelope.encryption != nil)
                if envelope.encryption == nil { inspectPending() } else { askPassword = true }
            case .customers:
                let imported = CSVImporter.customers(data)
                try store.importCustomers(imported.items)
                message = "\(imported.items.count) client(s) importé(s)." + skippedText(imported.skipped)
            case .catalog:
                let imported = CSVImporter.catalog(data)
                try store.importCatalog(imported.items)
                message = "\(imported.items.count) élément(s) importé(s)." + skippedText(imported.skipped)
            case .none:
                break
            }
        } catch {
            self.error = PresentedError(error)
        }
    }

    private func skippedText(_ skipped: [(line: Int, reason: String)]) -> String {
        guard !skipped.isEmpty else { return "" }
        let details = skipped.prefix(5).map { "ligne \($0.line) : \($0.reason)" }.joined(separator: "\n")
        return "\n\(skipped.count) ligne(s) ignorée(s) :\n\(details)"
    }

    private func inspectPending() {
        guard let pending = pendingRestore else { return }
        let secret = pending.encrypted ? restorePassword : nil
        restorePassword = ""
        working = true
        Task.detached(priority: .userInitiated) {
            do {
                let result = try BackupService.inspect(pending.data, password: secret)
                await MainActor.run {
                    inspectionItem = InspectionItem(inspection: result)
                    working = false
                }
            } catch {
                await MainActor.run {
                    self.error = PresentedError(error)
                    pendingRestore = nil
                    working = false
                }
            }
        }
    }

    private func restore(_ snapshot: BackupSnapshot) {
        do {
            try store.restore(snapshot)
            message = "Restauration terminée : \(snapshot.documents.count) document(s), \(snapshot.customers.count) client(s)."
        } catch {
            self.error = PresentedError(error)
        }
    }
}

/// Récapitulatif avant restauration.
struct RestoreConfirmationView: View {
    @Environment(\.dismiss) private var dismiss
    let inspection: BackupInspection
    let onDecision: (Bool) -> Void

    var body: some View {
        let snapshot = inspection.snapshot
        Form {
            Section("Contenu vérifié") {
                LabeledContent("Créée le", value: snapshot.createdAt.formatted(date: .long, time: .shortened))
                LabeledContent("Entreprise", value: snapshot.company.displayName)
                LabeledContent("Documents", value: "\(snapshot.documents.count)")
                LabeledContent("Factures émises", value: "\(snapshot.documents.filter(\.isIssuedInvoice).count)")
                LabeledContent("Clients", value: "\(snapshot.customers.count)")
                LabeledContent("Catalogue", value: "\(snapshot.catalog.count)")
                Label("Intégrité du fichier vérifiée", systemImage: "checkmark.seal").foregroundStyle(Theme.success)
            }
            if !inspection.warnings.isEmpty {
                Section("Avertissements") {
                    ForEach(inspection.warnings, id: \.self) { Text($0).font(.footnote).foregroundStyle(Theme.ochre) }
                }
            }
            Section {
                Button("Remplacer mes données par cette sauvegarde", role: .destructive) {
                    onDecision(true)
                    dismiss()
                }
            } footer: {
                Text("Toutes les données actuelles de l'application seront remplacées. Pensez à créer d'abord une sauvegarde de l'état actuel si nécessaire.")
            }
        }
        .navigationTitle("Restaurer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annuler") { onDecision(false); dismiss() }
            }
        }
    }
}
