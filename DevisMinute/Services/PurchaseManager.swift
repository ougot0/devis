import Foundation
import StoreKit
import Observation

/// Modèle commercial. La stratégie définitive sera choisie avant publication :
/// - `.paidUpfront` : application payante (≈ 9,99 €), tout est inclus, aucun achat intégré ;
/// - `.freemium` : application gratuite, fonctions avancées débloquées par **un achat unique**
///   (produit non consommable, jamais d'abonnement).
///
/// Quel que soit le modèle, ne sont **jamais** limitées : la création et l'émission de devis
/// et factures, les mentions légales, la sauvegarde et la restauration des données.
enum MonetizationMode {
    case paidUpfront
    case freemium
}

enum AppConfiguration {
    /// À ajuster avant la soumission (voir docs/PUBLICATION.md).
    static let monetization: MonetizationMode = .freemium
    static let premiumProductID = "com.devisminute.app.premium"
    static var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

/// Fonctions réservées à la version complète en mode freemium.
enum PremiumFeature: String, CaseIterable {
    case allTemplates
    case statistics
    case csvExport
    case structuredExport

    var label: String {
        switch self {
        case .allTemplates: return "Les 14 modèles de documents"
        case .statistics: return "Statistiques détaillées"
        case .csvExport: return "Exports CSV"
        case .structuredExport: return "Export des données structurées (XML CII)"
        }
    }
}

/// Achats intégrés StoreKit 2 (achat unique non consommable).
@MainActor
@Observable
final class PurchaseManager {
    private(set) var product: Product?
    private(set) var isPremium = false
    private(set) var isLoading = false
    var lastError: String?
    private var updatesTask: Task<Void, Never>?

    init() {
        if AppConfiguration.monetization == .paidUpfront { isPremium = true }
        #if DEBUG
        if DemoSupport.screen != nil { isPremium = true }
        #endif
    }

    func start() {
        guard AppConfiguration.monetization == .freemium else { return }
        #if DEBUG
        if DemoSupport.screen != nil { return }
        #endif
        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                    await self?.refreshEntitlements()
                }
            }
        }
        Task {
            await loadProduct()
            await refreshEntitlements()
        }
    }

    func isUnlocked(_ feature: PremiumFeature) -> Bool { isPremium }

    func loadProduct() async {
        do {
            product = try await Product.products(for: [AppConfiguration.premiumProductID]).first
        } catch {
            lastError = "Impossible de charger l'offre : \(error.localizedDescription)"
        }
    }

    func refreshEntitlements() async {
        guard AppConfiguration.monetization == .freemium else { isPremium = true; return }
        var unlocked = false
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement,
               transaction.productID == AppConfiguration.premiumProductID,
               transaction.revocationDate == nil {
                unlocked = true
            }
        }
        isPremium = unlocked
    }

    func purchase() async {
        guard let product else {
            lastError = "L'offre n'est pas disponible pour le moment. Vérifiez votre connexion."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refreshEntitlements()
                } else {
                    lastError = "L'achat n'a pas pu être vérifié."
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func restore() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            lastError = error.localizedDescription
        }
    }
}
