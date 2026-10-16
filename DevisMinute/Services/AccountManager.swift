import Foundation
import AuthenticationServices
import Security
import Observation

/// Compte DevisMinute avec « Se connecter avec Apple ».
///
/// Il n'y a pas de serveur : le compte identifie l'utilisateur sur cet appareil (identifiant
/// Apple anonyme, nom et e-mail fournis par Apple), conservé dans le trousseau. Les achats,
/// eux, sont liés à l'identifiant Apple de l'App Store et se restaurent sans ce compte.
/// Créer un compte reste facultatif (règle 5.1.1 de l'App Store) et sa suppression se fait dans l'app.
@MainActor
@Observable
final class AccountManager {
    struct Account: Codable, Equatable {
        var userID: String
        var name: String
        var email: String
        var createdAt: Date
    }

    private(set) var account: Account?
    var lastError: String?

    private static let keychainService = "com.devisminute.app.account"
    private static let keychainKey = "apple-account"

    init() {
        account = Self.load()
    }

    var isSignedIn: Bool { account != nil }

    /// Demande à « Se connecter avec Apple » le nom et l'e-mail.
    func configure(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
    }

    func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
            // Apple ne transmet le nom et l'e-mail qu'à la première connexion : on garde ceux déjà connus.
            let previous = Self.load()
            let name = [credential.fullName?.givenName, credential.fullName?.familyName].compactMap { $0 }.joined(separator: " ")
            let account = Account(
                userID: credential.user,
                name: name.isEmpty ? (previous?.userID == credential.user ? previous?.name ?? "" : "") : name,
                email: credential.email ?? (previous?.userID == credential.user ? previous?.email ?? "" : ""),
                createdAt: previous?.userID == credential.user ? previous?.createdAt ?? Date() : Date()
            )
            Self.save(account)
            self.account = account
            lastError = nil
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            lastError = "La connexion avec Apple n'a pas abouti. Réessayez dans un instant."
        }
    }

    /// Vérifie au lancement que l'autorisation n'a pas été retirée dans les réglages de l'identifiant Apple.
    func refreshCredentialState() async {
        guard let userID = account?.userID else { return }
        let state = await withCheckedContinuation { (continuation: CheckedContinuation<ASAuthorizationAppleIDProvider.CredentialState, Never>) in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { state, _ in continuation.resume(returning: state) }
        }
        if state == .revoked || state == .notFound { signOut() }
    }

    func signOut() {
        Self.delete()
        account = nil
    }

    /// Supprime le compte de l'appareil. Les devis et factures ne sont pas touchés.
    func deleteAccount() {
        signOut()
    }

    // MARK: Trousseau

    private static func baseQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: keychainService,
         kSecAttrAccount as String: keychainKey]
    }

    private static func load() -> Account? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Account.self, from: data)
    }

    private static func save(_ account: Account) {
        guard let data = try? JSONEncoder().encode(account) else { return }
        delete()
        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func delete() {
        SecItemDelete(baseQuery() as CFDictionary)
    }
}
