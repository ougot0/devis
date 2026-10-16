import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Compte en ligne (e-mail et mot de passe) géré par Supabase Auth, via son API REST.
/// Ce module construit les requêtes et interprète les réponses ; l'application les envoie.
/// Seuls l'e-mail et le mot de passe (chiffré par Supabase) quittent l'iPhone : les devis,
/// factures et clients restent sur l'appareil.
public struct AuthConfig: Sendable, Equatable {
    public var baseURL: URL
    /// Clé publique (« publishable ») du projet : faite pour être intégrée à l'application.
    public var apiKey: String

    public init(baseURL: URL, apiKey: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
    }

    /// Projet Supabase « DevisMinute » (région Paris).
    public static let devisMinute = AuthConfig(
        baseURL: URL(string: "https://acdkuxswjrvarxldtcjc.supabase.co")!,
        apiKey: "sb_publishable_DIlGzFPo1IU2ozOIr9E2fQ_gIUL3Ivd"
    )
}

/// Session ouverte après connexion (jetons conservés dans le trousseau par l'application).
public struct AuthSession: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var userID: String
    public var email: String

    public init(accessToken: String, refreshToken: String, expiresAt: Date, userID: String, email: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.userID = userID
        self.email = email
    }

    /// Vrai si le jeton expire dans moins de `margin` secondes.
    public func needsRefresh(now: Date = Date(), margin: TimeInterval = 300) -> Bool {
        expiresAt.timeIntervalSince(now) < margin
    }
}

public enum AuthOutcome: Sendable, Equatable {
    case signedIn(AuthSession)
    /// Inscription enregistrée : l'utilisateur doit confirmer son adresse avant de se connecter.
    case confirmationRequired(email: String)
    case done
}

public enum AuthError: Error, LocalizedError, Equatable {
    case invalidEmail
    case weakPassword(minimum: Int)
    case invalidCredentials
    case emailNotConfirmed
    case alreadyRegistered
    case rateLimited
    case sessionExpired
    case network
    case server(String)

    public var errorDescription: String? {
        switch self {
        case .invalidEmail: return "Cette adresse e-mail n'est pas valide."
        case .weakPassword(let minimum): return "Choisissez un mot de passe d'au moins \(minimum) caractères, avec des lettres et des chiffres."
        case .invalidCredentials: return "E-mail ou mot de passe incorrect."
        case .emailNotConfirmed: return "Confirmez d'abord votre adresse : ouvrez le lien reçu par e-mail, puis reconnectez-vous."
        case .alreadyRegistered: return "Un compte existe déjà avec cette adresse. Connectez-vous ou utilisez « Mot de passe oublié »."
        case .rateLimited: return "Trop de tentatives. Réessayez dans quelques minutes."
        case .sessionExpired: return "Votre session a expiré. Reconnectez-vous."
        case .network: return "Connexion impossible. Vérifiez votre accès à Internet et réessayez."
        case .server(let message): return "Le service de compte a répondu : \(message)"
        }
    }
}

public enum AuthAPI {
    public static let minimumPasswordLength = 8

    // MARK: Validation locale

    public static func normalizedEmail(_ email: String) throws -> String {
        let value = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."), !parts[1].hasPrefix("."), !parts[1].hasSuffix("."),
              !value.contains(" ") else { throw AuthError.invalidEmail }
        return value
    }

    public static func validatePassword(_ password: String) throws {
        let hasLetter = password.contains { $0.isLetter }
        let hasDigit = password.contains { $0.isNumber }
        guard password.count >= minimumPasswordLength, hasLetter, hasDigit else {
            throw AuthError.weakPassword(minimum: minimumPasswordLength)
        }
    }

    // MARK: Requêtes

    private static func request(_ config: AuthConfig, path: String, query: String? = nil, body: [String: String]?, token: String? = nil) -> URLRequest {
        var components = URLComponents(url: config.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.percentEncodedQuery = query
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue(config.apiKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) }
        return request
    }

    public static func signUp(_ config: AuthConfig, email: String, password: String) throws -> URLRequest {
        let email = try normalizedEmail(email)
        try validatePassword(password)
        return request(config, path: "auth/v1/signup", body: ["email": email, "password": password])
    }

    public static func signIn(_ config: AuthConfig, email: String, password: String) throws -> URLRequest {
        let email = try normalizedEmail(email)
        guard !password.isEmpty else { throw AuthError.invalidCredentials }
        return request(config, path: "auth/v1/token", query: "grant_type=password", body: ["email": email, "password": password])
    }

    public static func refresh(_ config: AuthConfig, refreshToken: String) -> URLRequest {
        request(config, path: "auth/v1/token", query: "grant_type=refresh_token", body: ["refresh_token": refreshToken])
    }

    public static func recoverPassword(_ config: AuthConfig, email: String) throws -> URLRequest {
        request(config, path: "auth/v1/recover", body: ["email": try normalizedEmail(email)])
    }

    public static func resendConfirmation(_ config: AuthConfig, email: String) throws -> URLRequest {
        request(config, path: "auth/v1/resend", body: ["type": "signup", "email": try normalizedEmail(email)])
    }

    public static func signOut(_ config: AuthConfig, accessToken: String) -> URLRequest {
        request(config, path: "auth/v1/logout", body: nil, token: accessToken)
    }

    /// Fonction serveur `delete-account` : supprime le compte de l'utilisateur authentifié.
    public static func deleteAccount(_ config: AuthConfig, accessToken: String) -> URLRequest {
        request(config, path: "functions/v1/delete-account", body: [:], token: accessToken)
    }

    // MARK: Réponses

    /// Interprète la réponse d'inscription, de connexion ou de rafraîchissement.
    public static func parseSession(status: Int, data: Data, now: Date = Date()) throws -> AuthOutcome {
        guard (200..<300).contains(status) else { throw error(status: status, data: data) }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AuthError.server("réponse illisible") }
        if let access = json["access_token"] as? String, let refresh = json["refresh_token"] as? String,
           let user = json["user"] as? [String: Any], let id = user["id"] as? String {
            let expiresAt: Date
            if let absolute = number(json["expires_at"]) {
                expiresAt = Date(timeIntervalSince1970: absolute)
            } else {
                expiresAt = now.addingTimeInterval(number(json["expires_in"]) ?? 3600)
            }
            return .signedIn(AuthSession(accessToken: access, refreshToken: refresh, expiresAt: expiresAt, userID: id, email: user["email"] as? String ?? ""))
        }
        // Inscription avec confirmation par e-mail : seul l'utilisateur est renvoyé.
        let user = (json["user"] as? [String: Any]) ?? json
        if user["id"] != nil {
            // Adresse déjà inscrite : Supabase renvoie un utilisateur sans identité, sans rien envoyer.
            if let identities = user["identities"] as? [Any], identities.isEmpty { throw AuthError.alreadyRegistered }
            return .confirmationRequired(email: user["email"] as? String ?? "")
        }
        throw AuthError.server("réponse inattendue")
    }

    /// Réponses sans contenu utile (mot de passe oublié, déconnexion, suppression).
    public static func parseEmpty(status: Int, data: Data) throws -> AuthOutcome {
        guard (200..<300).contains(status) else { throw error(status: status, data: data) }
        return .done
    }

    public static func error(status: Int, data: Data) -> AuthError {
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let code = (json["error_code"] as? String) ?? (json["error"] as? String) ?? ""
        let message = (json["msg"] as? String) ?? (json["error_description"] as? String) ?? (json["message"] as? String) ?? ""
        switch code {
        case "invalid_credentials", "invalid_grant":
            return message.lowercased().contains("not confirmed") ? .emailNotConfirmed : .invalidCredentials
        case "email_not_confirmed": return .emailNotConfirmed
        case "user_already_exists", "email_exists": return .alreadyRegistered
        case "weak_password": return .weakPassword(minimum: minimumPasswordLength)
        case "email_address_invalid", "validation_failed": return .invalidEmail
        case "over_email_send_rate_limit", "over_request_rate_limit", "over_sms_send_rate_limit": return .rateLimited
        case "session_not_found", "refresh_token_not_found", "refresh_token_already_used", "bad_jwt", "invalid_token": return .sessionExpired
        default: break
        }
        if status == 429 { return .rateLimited }
        if status == 401 { return .sessionExpired }
        return .server(message.isEmpty ? "erreur \(status)" : message)
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }
}
