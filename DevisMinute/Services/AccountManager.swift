import Foundation
import AuthenticationServices
import Security
import Observation
import DevisCore

/// Compte DevisMinute, au choix :
/// - **avec Apple** : identifiant Apple anonyme, nom et e-mail fournis par Apple, gardés sur l'appareil ;
/// - **avec un e-mail** : compte en ligne (Supabase Auth, projet hébergé à Paris), avec confirmation
///   de l'adresse et mot de passe oublié. Seuls l'e-mail et le mot de passe quittent l'iPhone.
/// Les achats restent liés à l'identifiant Apple de l'App Store. Créer un compte est facultatif
/// (règle 5.1.1 de l'App Store) et sa suppression se fait dans l'app.
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
    /// Session du compte e-mail.
    private(set) var online: AuthSession?
    private(set) var isWorking = false
    var lastError: String?
    var lastInfo: String?
    private let config = AuthConfig.devisMinute

    private static let keychainService = "com.devisminute.app.account"
    private static let keychainKey = "apple-account"

    init() {
        account = Self.load()
        online = Self.load(AuthSession.self, key: Self.onlineKey)
    }

    var isSignedIn: Bool { account != nil || online != nil }

    /// Nom affiché (compte Apple) ou adresse e-mail (compte e-mail).
    var displayName: String? {
        if let online { return online.email }
        if let account { return account.name.isEmpty ? "Compte Apple" : account.name }
        return nil
    }

    // MARK: Compte e-mail

    private static let onlineKey = "email-session"

    private func send(_ request: URLRequest) async throws -> (Int, Data) {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
        } catch {
            throw AuthError.network
        }
    }

    private func run(_ work: () async throws -> Void) async {
        isWorking = true
        lastError = nil
        lastInfo = nil
        do { try await work() } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isWorking = false
    }

    private func store(_ session: AuthSession) {
        Self.save(session, key: Self.onlineKey)
        online = session
    }

    func signUp(email: String, password: String) async {
        await run {
            let (status, data) = try await send(try AuthAPI.signUp(config, email: email, password: password))
            switch try AuthAPI.parseSession(status: status, data: data) {
            case .signedIn(let session): store(session)
            case .confirmationRequired(let address):
                lastInfo = "Compte créé. Ouvrez le lien envoyé à \(address.isEmpty ? email : address) pour confirmer votre adresse, puis connectez-vous."
            case .done: break
            }
        }
    }

    func signIn(email: String, password: String) async {
        await run {
            let (status, data) = try await send(try AuthAPI.signIn(config, email: email, password: password))
            if case .signedIn(let session) = try AuthAPI.parseSession(status: status, data: data) { store(session) }
        }
    }

    func resetPassword(email: String) async {
        await run {
            let (status, data) = try await send(try AuthAPI.recoverPassword(config, email: email))
            _ = try AuthAPI.parseEmpty(status: status, data: data)
            lastInfo = "Si un compte existe pour cette adresse, un e-mail pour choisir un nouveau mot de passe vient d'être envoyé."
        }
    }

    func resendConfirmation(email: String) async {
        await run {
            let (status, data) = try await send(try AuthAPI.resendConfirmation(config, email: email))
            _ = try AuthAPI.parseEmpty(status: status, data: data)
            lastInfo = "E-mail de confirmation renvoyé."
        }
    }

    /// Renouvelle le jeton s'il expire bientôt ; ferme la session si elle n'est plus valable.
    func refreshOnlineSession() async {
        guard let session = online, session.needsRefresh() else { return }
        do {
            let (status, data) = try await send(AuthAPI.refresh(config, refreshToken: session.refreshToken))
            if case .signedIn(let renewed) = try AuthAPI.parseSession(status: status, data: data) { store(renewed) }
        } catch AuthError.network {
            // Hors ligne : on garde la session, elle sera renouvelée plus tard.
        } catch {
            clearOnline()
        }
    }

    private func clearOnline() {
        Self.delete(key: Self.onlineKey)
        online = nil
    }

    /// Jeton valable pour un appel authentifié.
    private func validToken() async throws -> String {
        await refreshOnlineSession()
        guard let token = online?.accessToken else { throw AuthError.sessionExpired }
        return token
    }

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
        if let token = online?.accessToken {
            let request = AuthAPI.signOut(config, accessToken: token)
            Task { _ = try? await URLSession.shared.data(for: request) }
        }
        clearOnline()
    }

    /// Supprime le compte (et, pour un compte e-mail, sur le serveur). Les devis et factures ne sont pas touchés.
    func deleteAccount() async {
        if online != nil {
            await run {
                let (status, data) = try await send(AuthAPI.deleteAccount(config, accessToken: try await validToken()))
                _ = try AuthAPI.parseEmpty(status: status, data: data)
                clearOnline()
                Self.delete()
                account = nil
            }
        } else {
            signOut()
        }
    }

    // MARK: Trousseau

    private static func baseQuery(key: String = keychainKey) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: keychainService,
         kSecAttrAccount as String: key]
    }

    private static func load() -> Account? { load(Account.self, key: keychainKey) }

    private static func save(_ account: Account) { save(account, key: keychainKey) }

    private static func delete() { delete(key: keychainKey) }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        var query = baseQuery(key: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        delete(key: key)
        var query = baseQuery(key: key)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func delete(key: String) {
        SecItemDelete(baseQuery(key: key) as CFDictionary)
    }
}
