import SwiftUI
import PhotosUI
import DevisCore
import DevisPDF

/// Assistant de configuration initiale : 4 étapes courtes, puis le premier devis.
struct OnboardingView: View {
    @Environment(DataStore.self) private var store
    @State private var step = 0
    @State private var profile = CompanyProfile()
    @State private var appearance = DocumentAppearance()
    @State private var logo: Data?
    @State private var photoItem: PhotosPickerItem?
    @State private var error: PresentedError?

    private let titles = ["Votre statut", "Votre entreprise", "Vos coordonnées", "Vos documents"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progress
                Form {
                    switch step {
                    case 0:
                        welcome
                        LegalStatusSection(profile: $profile)
                    case 1:
                        IdentitySection(profile: $profile)
                    case 2:
                        ContactSection(profile: $profile)
                        BankSection(profile: $profile)
                    default:
                        PaymentTermsSection(profile: $profile)
                        appearanceSection
                    }
                }
                .appBackground()
                footer
            }
            .background(Theme.ivory)
            .navigationTitle(titles[step])
            .navigationBarTitleDisplayMode(.inline)
            .errorAlert($error)
            .onChange(of: photoItem) { _, item in loadLogo(item) }
        }
    }

    private var progress: some View {
        HStack(spacing: 4) {
            ForEach(0..<titles.count, id: \.self) { index in
                Rectangle()
                    .fill(index <= step ? Theme.petrol : Theme.hairline)
                    .frame(height: 3)
            }
        }
        .padding(.horizontal)
        .padding(.top, Theme.Space.s)
        .accessibilityElement()
        .accessibilityLabel("Étape \(step + 1) sur \(titles.count)")
    }

    private var welcome: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Bienvenue dans DevisMinute")
                    .font(.title2.weight(.semibold))
                Text("Quatre étapes pour que vos devis et factures portent automatiquement les bonnes informations. Tout reste sur votre iPhone.")
                    .foregroundStyle(Theme.neutral)
            }
            .padding(.vertical, Theme.Space.s)
        }
    }

    private var appearanceSection: some View {
        Section {
            Picker("Modèle", selection: $appearance.template) {
                ForEach(DocumentTemplate.allCases) { Text($0.name).tag($0) }
            }
            .onChange(of: appearance.template) { _, template in
                appearance = DocumentAppearance(template: template)
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(logo == nil ? "Ajouter un logo" : "Changer de logo", systemImage: "photo")
            }
            if let logo, let image = UIImage(data: logo) {
                Image(uiImage: image).resizable().scaledToFit().frame(height: 60)
                    .accessibilityLabel("Aperçu du logo")
            }
        } header: {
            Text("Apparence")
        } footer: {
            Text("Modèles, couleurs et typographie restent modifiables dans les réglages.")
        }
    }

    private var footer: some View {
        HStack(spacing: Theme.Space.m) {
            if step > 0 {
                Button("Retour") { withAnimation(.easeOut(duration: 0.15)) { step -= 1 } }
                    .buttonStyle(SecondaryButtonStyle())
            }
            Button(step == titles.count - 1 ? "Terminer" : "Continuer") { next() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canContinue)
        }
        .padding()
        .background(Theme.ivory)
    }

    private var canContinue: Bool {
        switch step {
        case 1:
            let hasName = profile.legalForm.isIndividualEntrepreneur ? !profile.ownerName.trimmed.isEmpty : !(profile.legalName.trimmed.isEmpty && profile.tradeName.trimmed.isEmpty)
            return hasName
        case 2:
            return !profile.address.line1.trimmed.isEmpty && !profile.address.city.trimmed.isEmpty
        default:
            return true
        }
    }

    private func next() {
        if step < titles.count - 1 {
            withAnimation(.easeOut(duration: 0.15)) { step += 1 }
            return
        }
        if profile.tradeName.trimmed.isEmpty {
            profile.tradeName = profile.legalForm.isIndividualEntrepreneur ? profile.ownerName : profile.legalName
        }
        do {
            try store.completeOnboarding(profile, appearance: appearance, logo: logo)
        } catch {
            self.error = PresentedError(error)
        }
    }

    private func loadLogo(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task { @MainActor in
            if let data = try? await item.loadTransferable(type: Data.self), let jpeg = LogoProcessor.jpeg(from: data) {
                logo = jpeg
            } else {
                error = PresentedError(message: "Cette image n'a pas pu être importée.")
            }
        }
    }
}
