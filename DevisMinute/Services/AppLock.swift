import Foundation
import LocalAuthentication
import Observation

/// Verrouillage facultatif de l'application par Face ID / Touch ID / code de l'appareil.
@MainActor
@Observable
final class AppLock {
    private(set) var isUnlocked = false
    var errorMessage: String?

    var biometryLabel: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "le code de l'appareil"
        }
    }

    func lock() { isUnlocked = false }

    func unlock() async {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // Aucun code configuré sur l'appareil : le verrou ne peut pas s'appliquer.
            isUnlocked = true
            return
        }
        do {
            isUnlocked = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Déverrouiller vos devis et factures")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
