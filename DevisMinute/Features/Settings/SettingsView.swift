import SwiftUI
import PhotosUI
import DevisCore
import DevisPDF

/// Réglages de l'entreprise et des documents.
struct SettingsView: View {
    @Environment(AppDataStore.self) private var store
    @Environment(AppLock.self) private var appLock

    var body: some View {
        List {
            Section {
                NavigationLink("Informations de l'entreprise") { CompanySettingsView() }
                NavigationLink("Modèles et apparence") { AppearanceSettingsView() }
                NavigationLink("Numérotation") { NumberingSettingsView() }
            }
            AppIconSection()
            DueRemindersSection()
            Section {
                Toggle("Verrouiller avec \(appLock.biometryLabel)", isOn: Binding(get: { store.appLockEnabled }, set: { try? store.setAppLock($0) }))
            } header: {
                Text("Confidentialité")
            } footer: {
                Text("Vos données restent sur cet iPhone, chiffrées par iOS lorsque l'appareil est verrouillé. Aucune donnée n'est envoyée à un serveur.")
            }
            Section {
                LabeledContent("Version", value: AppConfiguration.appVersion)
            }
        }
        .navigationTitle("Réglages")
        .appBackground()
    }
}

struct CompanySettingsView: View {
    @Environment(AppDataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var profile = CompanyProfile()
    @State private var loaded = false
    @State private var error: PresentedError?

    var body: some View {
        Form {
            LegalStatusSection(profile: $profile)
            IdentitySection(profile: $profile)
            ContactSection(profile: $profile)
            BankSection(profile: $profile)
            OnlinePaymentSection(profile: $profile)
            PaymentTermsSection(profile: $profile)
            MentionsSection(profile: $profile)
            Section {
                Text("Les modifications s'appliquent aux nouveaux documents et aux brouillons. Les factures déjà émises conservent les informations en vigueur lors de leur émission.")
                    .font(.footnote).foregroundStyle(Theme.neutral)
            }
        }
        .appBackground()
        .navigationTitle("Entreprise")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer") {
                    do {
                        try store.updateCompany(profile)
                        dismiss()
                    } catch {
                        self.error = PresentedError(error)
                    }
                }
                .fontWeight(.semibold)
            }
        }
        .errorAlert($error)
        .onAppear {
            if !loaded { profile = store.company; loaded = true }
        }
    }
}

/// Choix du modèle, de la couleur, de la typographie et du logo, avec aperçu réel.
struct AppearanceSettingsView: View {
    @Environment(AppDataStore.self) private var store
    @Environment(PurchaseManager.self) private var purchases
    @State private var appearance = DocumentAppearance()
    @State private var accent = Color.accentColor
    @State private var photoItem: PhotosPickerItem?
    @State private var preview: Data?
    @State private var showPreview = false
    @State private var error: PresentedError?

    /// Modèles disponibles sans la version complète (mode freemium).
    static let freeTemplates: Set<DocumentTemplate> = [.classique, .minimal]

    var body: some View {
        Form {
            Section("Modèle") {
                ForEach(DocumentTemplate.allCases) { template in
                    let locked = !purchases.isUnlocked(.allTemplates) && !Self.freeTemplates.contains(template)
                    Button {
                        guard !locked else { return }
                        appearance = DocumentAppearance(template: template, showBankDetails: appearance.showBankDetails, showSignatureBlock: appearance.showSignatureBlock, showLogo: appearance.showLogo)
                        accent = Color(hex: appearance.accentHex)
                        save()
                    } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.name).foregroundStyle(locked ? Theme.neutral : Theme.ink)
                                Text(template.summary).font(.footnote).foregroundStyle(Theme.neutral)
                            }
                            Spacer()
                            if appearance.template == template {
                                Image(systemName: "checkmark").foregroundStyle(Theme.petrol)
                            } else if locked {
                                Image(systemName: "lock").foregroundStyle(Theme.neutral)
                            }
                        }
                    }
                    .accessibilityAddTraits(appearance.template == template ? .isSelected : [])
                }
                Button { renderPreview() } label: { Label("Aperçu avec un document d'exemple", systemImage: "eye") }
            }
            Section("Personnalisation") {
                ColorPicker("Couleur principale", selection: $accent, supportsOpacity: false)
                    .onChange(of: accent) { _, color in
                        appearance.accentHex = color.hexString
                        save()
                    }
                Picker("Typographie", selection: $appearance.fontPairing) {
                    ForEach(FontPairing.allCases) { Text($0.label).tag($0) }
                }
                .onChange(of: appearance.fontPairing) { _, _ in save() }
                Toggle("Coordonnées bancaires sur les factures", isOn: $appearance.showBankDetails)
                    .onChange(of: appearance.showBankDetails) { _, _ in save() }
                Toggle("Zone « Bon pour accord » sur les devis", isOn: $appearance.showSignatureBlock)
                    .onChange(of: appearance.showSignatureBlock) { _, _ in save() }
                Toggle("Afficher le logo", isOn: $appearance.showLogo)
                    .onChange(of: appearance.showLogo) { _, _ in save() }
            }
            Section("Logo") {
                let hasLogo = store.logoJPEG != nil
                if let logo = store.logoJPEG, let image = UIImage(data: logo) {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 70)
                        .accessibilityLabel("Logo actuel")
                }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(hasLogo ? "Remplacer le logo" : "Choisir un logo", systemImage: "photo")
                }
                if store.logoJPEG != nil {
                    Button("Retirer le logo", role: .destructive) { try? store.updateLogo(nil) }
                }
            }
        }
        .appBackground()
        .navigationTitle("Apparence")
        .sheet(isPresented: $showPreview) {
            if let preview {
                NavigationStack {
                    PDFKitView(data: preview)
                        .navigationTitle("Aperçu")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { showPreview = false } } }
                }
            }
        }
        .errorAlert($error)
        .onAppear {
            appearance = store.appearance
            accent = Color(hex: appearance.accentHex)
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { @MainActor in
                if let data = try? await item.loadTransferable(type: Data.self), let jpeg = LogoProcessor.jpeg(from: data) {
                    do { try store.updateLogo(jpeg) } catch { self.error = PresentedError(error) }
                } else {
                    error = PresentedError(message: "Cette image n'a pas pu être importée.")
                }
            }
        }
    }

    private func save() {
        do { try store.updateAppearance(appearance) } catch { self.error = PresentedError(error) }
    }

    /// Aperçu sur un document d'exemple (non enregistré), avec les vraies informations de l'entreprise.
    private func renderPreview() {
        let calendar = Calendar.devisMinute
        let today = Date()
        let chargesVAT = store.company.isVATRegistered
        let sample = BusinessDocument(
            kind: .quote,
            number: "EXEMPLE",
            issueDate: today,
            validUntil: calendar.date(byAdding: .day, value: 30, to: today),
            title: "Document d'exemple",
            seller: store.company,
            customer: CustomerSnapshot(kind: .business, name: "Client exemple", address: PostalAddress(line1: "1 rue de l'Exemple", postalCode: "75000", city: "Paris")),
            lines: [
                .section("Prestations"),
                DocumentLine(designation: "Prestation principale", details: "Description détaillée de la prestation.", quantity: 2, unit: "jour", unitPriceHT: 450, vatRate: chargesVAT ? 20 : 0),
                DocumentLine(designation: "Fourniture", quantity: 3, unit: "u", unitPriceHT: Decimal.exact("39.90"), vatRate: chargesVAT ? 20 : 0, nature: .goods),
            ]
        )
        let result = DocumentPDFRenderer.render(RenderRequest(document: sample, appearance: appearance, logoJPEG: store.logoJPEG, isDraft: false), deflate: DocumentExportService.deflate)
        preview = result.data
        showPreview = true
    }
}

/// Formats de numérotation.
struct NumberingSettingsView: View {
    @Environment(AppDataStore.self) private var store
    @State private var patterns: [NumberingSeries: String] = [:]
    @State private var resets: [NumberingSeries: Bool] = [:]
    @State private var error: PresentedError?
    @State private var resumeNumber = ""
    @State private var resumeDate = Date()
    @State private var confirmResume = false
    @State private var resumedMessage: String?

    var body: some View {
        Form {
            ForEach([NumberingSeries.quote, .invoice, .creditNote], id: \.self) { series in
                Section {
                    TextField("Format", text: Binding(get: { patterns[series] ?? "" }, set: { patterns[series] = $0 }))
                        .font(.body.monospaced())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                    Toggle("Repartir à 1 chaque année", isOn: Binding(get: { resets[series] ?? true }, set: { resets[series] = $0 }))
                    let scheme = NumberingScheme(pattern: patterns[series] ?? "", resetsYearly: resets[series] ?? true)
                    if let validationError = validationMessage(scheme) {
                        Text(validationError).font(.footnote).foregroundStyle(Theme.danger)
                    } else {
                        LabeledContent("Prochain numéro", value: NumberingService.preview(scheme: scheme, state: store.state(for: series), issueDate: Date()))
                    }
                    Button("Enregistrer ce format") { save(series) }
                        .disabled(validationMessage(scheme) != nil)
                } header: {
                    Text(title(series))
                }
            }
            Section {
                if let suggestion = store.suggestedResume(for: .invoice) {
                    Button("Utiliser la dernière facture importée : \(suggestion.number)") {
                        resumeNumber = suggestion.number
                        resumeDate = suggestion.date
                    }
                }
                TextField("Dernier numéro émis, ex. F-2026-0057", text: $resumeNumber)
                    .font(.body.monospaced())
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                DatePicker("Date de cette facture", selection: $resumeDate, in: ...Date(), displayedComponents: .date)
                if !resumeNumber.trimmed.isEmpty {
                    if NumberingService.sequence(in: resumeNumber.trimmed, scheme: store.scheme(for: .invoice)) == nil {
                        Text("Ce numéro ne suit pas le format des factures (\(store.scheme(for: .invoice).pattern)). Modifiez d'abord le format ci-dessus pour qu'il corresponde.")
                            .font(.footnote).foregroundStyle(Theme.danger)
                    }
                }
                Button("Continuer la numérotation après ce numéro") { confirmResume = true }
                    .disabled(NumberingService.sequence(in: resumeNumber.trimmed, scheme: store.scheme(for: .invoice)) == nil)
                if let resumedMessage {
                    Label(resumedMessage, systemImage: "checkmark.circle").font(.footnote).foregroundStyle(Theme.success)
                }
            } header: {
                Text("Reprendre une numérotation existante")
            } footer: {
                Text("Vous facturiez déjà avec un autre logiciel ? Indiquez le dernier numéro de facture émis : la prochaine facture DevisMinute portera le numéro suivant, sans trou ni doublon.")
            }
            Section {
                Text("Jetons : {AAAA} année, {AA} année sur 2 chiffres, {MM} mois, {N} compteur, {N:4} compteur sur 4 chiffres.\nLes factures sont numérotées à l'émission, dans l'ordre chronologique et sans rupture. Changer de format ne renumérote jamais les documents existants.")
                    .font(.footnote).foregroundStyle(Theme.neutral)
            }
        }
        .appBackground()
        .navigationTitle("Numérotation")
        .errorAlert($error)
        .confirmationDialog("Continuer après \(resumeNumber.trimmed) ?", isPresented: $confirmResume, titleVisibility: .visible) {
            Button("Confirmer") { resume() }
        } message: {
            Text("Vérifiez bien : ce réglage ne peut pas revenir en arrière.")
        }
        .onAppear {
            for series in [NumberingSeries.quote, .invoice, .creditNote] {
                let scheme = store.scheme(for: series)
                patterns[series] = scheme.pattern
                resets[series] = scheme.resetsYearly
            }
        }
    }

    private func resume() {
        do {
            try store.resumeNumbering(series: .invoice, afterNumber: resumeNumber, issuedOn: resumeDate)
            resumedMessage = "Prochaine facture : \(store.nextNumberPreview(for: .invoice))"
        } catch {
            self.error = PresentedError(error)
        }
    }

    private func title(_ series: NumberingSeries) -> String {
        switch series {
        case .quote: return "Devis"
        case .invoice: return "Factures et factures d'acompte"
        case .creditNote: return "Avoirs"
        }
    }

    private func validationMessage(_ scheme: NumberingScheme) -> String? {
        do {
            try scheme.validate()
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription
        }
    }

    private func save(_ series: NumberingSeries) {
        do {
            try store.updateScheme(NumberingScheme(pattern: patterns[series] ?? "", resetsYearly: resets[series] ?? true), for: series)
        } catch {
            self.error = PresentedError(error)
        }
    }
}

extension Color {
    init(hex: String) {
        let color = PDFColor(hex: hex) ?? PDFColor(hex: "#245A64")!
        self.init(red: color.red, green: color.green, blue: color.blue)
    }

    var hexString: String {
        let uiColor = UIColor(self)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return PDFColor(red: Double(min(max(red, 0), 1)), green: Double(min(max(green, 0), 1)), blue: Double(min(max(blue, 0), 1))).hex
    }
}

/// Choix de l'icône de l'application sur l'écran d'accueil.
struct AppIconSection: View {
    @State private var current = UIApplication.shared.alternateIconName
    @State private var error: PresentedError?

    private struct Option: Identifiable {
        let name: String?
        let label: String
        let preview: String
        var id: String { name ?? "default" }
    }

    private let options = [
        Option(name: nil, label: "Pétrole", preview: "IconPreview-Petrole"),
        Option(name: "AppIcon-Ivoire", label: "Ivoire", preview: "IconPreview-Ivoire"),
        Option(name: "AppIcon-Nuit", label: "Nuit", preview: "IconPreview-Nuit"),
    ]

    var body: some View {
        Section("Icône de l'app") {
            HStack(spacing: Theme.Space.l) {
                ForEach(options) { option in
                    Button { select(option.name) } label: {
                        VStack(spacing: Theme.Space.xs) {
                            Image(option.preview)
                                .resizable()
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(current == option.name ? Theme.petrol : .clear, lineWidth: 3)
                                        .padding(-4)
                                )
                            Text(option.label)
                                .font(.caption.weight(current == option.name ? .semibold : .regular))
                                .foregroundStyle(current == option.name ? Theme.petrol : Theme.neutral)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Icône \(option.label)")
                    .accessibilityAddTraits(current == option.name ? .isSelected : [])
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Space.s)
        }
        .errorAlert($error)
    }

    private func select(_ name: String?) {
        guard UIApplication.shared.supportsAlternateIcons, name != current else { return }
        Task { @MainActor in
            do {
                try await UIApplication.shared.setAlternateIconName(name)
                current = name
            } catch {
                self.error = PresentedError(error)
            }
        }
    }
}

/// Activation des notifications d'échéance.
struct DueRemindersSection: View {
    @Environment(AppDataStore.self) private var store
    @State private var enabled = ReminderScheduler.isEnabled
    @State private var denied = false

    var body: some View {
        Section {
            Toggle("Rappels d'échéance", isOn: Binding(get: { enabled }, set: { update($0) }))
                .tint(Theme.petrol)
            if denied {
                Text("Les notifications sont refusées : autorisez-les dans Réglages › Notifications › DevisMinute.")
                    .font(.footnote).foregroundStyle(Theme.danger)
            }
        } header: {
            Text("Relances")
        } footer: {
            Text("Une notification le matin de l'échéance de chaque facture impayée, puis 7 jours après si elle n'est toujours pas réglée. Tout est calculé sur l'iPhone.")
        }
    }

    private func update(_ value: Bool) {
        Task { @MainActor in
            if value {
                enabled = await ReminderScheduler.enable()
                denied = !enabled
            } else {
                await ReminderScheduler.disable()
                enabled = false
            }
            await ReminderScheduler.refresh(records: store.allRecords())
        }
    }
}
