import SwiftUI
import StoreKit

/// Présentation de la version complète (achat unique, sans abonnement ni publicité).
struct PremiumView: View {
    @Environment(PurchaseManager.self) private var purchases

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text(purchases.isPremium ? "Version complète active" : "Version complète")
                        .font(.title3.weight(.semibold))
                    Text("Un achat unique, sans abonnement et sans publicité. La création, l'émission et la sauvegarde de vos documents restent toujours gratuites.")
                        .font(.footnote).foregroundStyle(Theme.neutral)
                }
                .padding(.vertical, Theme.Space.xs)
            }
            Section("Inclus") {
                ForEach(PremiumFeature.allCases, id: \.self) { feature in
                    Label(feature.label, systemImage: purchases.isPremium ? "checkmark" : "lock")
                }
            }
            if AppConfiguration.monetization == .freemium && !purchases.isPremium {
                Section {
                    Button {
                        Task { await purchases.purchase() }
                    } label: {
                        if purchases.isLoading {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text(purchases.product.map { "Débloquer pour \($0.displayPrice)" } ?? "Offre indisponible")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: Theme.ochre))
                    .disabled(purchases.product == nil || purchases.isLoading)
                    .listRowBackground(Color.clear)
                    Button("Restaurer un achat") { Task { await purchases.restore() } }
                } footer: {
                    if let error = purchases.lastError { Text(error).foregroundStyle(Theme.danger) }
                }
            }
        }
        .navigationTitle("Version complète")
        .appBackground()
    }
}

/// Écran affiché à la place d'une fonction réservée à la version complète.
struct PremiumRequiredView: View {
    let feature: PremiumFeature

    var body: some View {
        ContentUnavailableView {
            Label(feature.label, systemImage: "lock")
        } description: {
            Text("Cette fonction fait partie de la version complète (achat unique).")
        } actions: {
            NavigationLink("Découvrir la version complète") { PremiumView() }
        }
    }
}
