import XCTest
@testable import DevisCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class OnlineAccountTests: XCTestCase {
    private let config = AuthConfig(baseURL: URL(string: "https://exemple.supabase.co")!, apiKey: "sb_publishable_test")

    func testValidation() {
        XCTAssertEqual(try AuthAPI.normalizedEmail("  Camille@Exemple.FR "), "camille@exemple.fr")
        for bad in ["camille", "camille@", "@exemple.fr", "camille@exemple", "ca mille@exemple.fr", "camille@exemple."] {
            XCTAssertThrowsError(try AuthAPI.normalizedEmail(bad), bad)
        }
        XCTAssertThrowsError(try AuthAPI.validatePassword("court1"))
        XCTAssertThrowsError(try AuthAPI.validatePassword("seulementdeslettres"))
        XCTAssertNoThrow(try AuthAPI.validatePassword("devis2026ok"))
    }

    func testRequestsCarryKeyAndBody() throws {
        let signUp = try AuthAPI.signUp(config, email: "Camille@exemple.fr", password: "devis2026ok")
        XCTAssertEqual(signUp.url?.absoluteString, "https://exemple.supabase.co/auth/v1/signup")
        XCTAssertEqual(signUp.httpMethod, "POST")
        XCTAssertEqual(signUp.value(forHTTPHeaderField: "apikey"), "sb_publishable_test")
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(signUp.httpBody)) as? [String: String]
        XCTAssertEqual(body?["email"], "camille@exemple.fr")
        let signIn = try AuthAPI.signIn(config, email: "camille@exemple.fr", password: "x")
        XCTAssertEqual(signIn.url?.absoluteString, "https://exemple.supabase.co/auth/v1/token?grant_type=password")
        let delete = AuthAPI.deleteAccount(config, accessToken: "jeton")
        XCTAssertEqual(delete.url?.absoluteString, "https://exemple.supabase.co/functions/v1/delete-account")
        XCTAssertEqual(delete.value(forHTTPHeaderField: "Authorization"), "Bearer jeton")
    }

    func testSessionParsing() throws {
        let json = #"{"access_token":"a","token_type":"bearer","expires_in":3600,"expires_at":1792140000,"refresh_token":"r","user":{"id":"u1","email":"camille@exemple.fr"}}"#
        guard case .signedIn(let session) = try AuthAPI.parseSession(status: 200, data: Data(json.utf8)) else { return XCTFail() }
        XCTAssertEqual(session.userID, "u1")
        XCTAssertEqual(session.expiresAt, Date(timeIntervalSince1970: 1_792_140_000))
        XCTAssertTrue(session.needsRefresh(now: Date(timeIntervalSince1970: 1_792_139_900)))
        XCTAssertFalse(session.needsRefresh(now: Date(timeIntervalSince1970: 1_792_130_000)))
    }

    func testSignUpWaitingForConfirmation() throws {
        let pending = #"{"id":"u1","email":"camille@exemple.fr","identities":[{"id":"i1"}],"confirmation_sent_at":"2026-10-16T08:00:00Z"}"#
        XCTAssertEqual(try AuthAPI.parseSession(status: 200, data: Data(pending.utf8)), .confirmationRequired(email: "camille@exemple.fr"))
        let existing = #"{"id":"u1","email":"camille@exemple.fr","identities":[]}"#
        XCTAssertThrowsError(try AuthAPI.parseSession(status: 200, data: Data(existing.utf8))) { XCTAssertEqual($0 as? AuthError, .alreadyRegistered) }
    }

    func testErrorsAreTranslated() {
        func error(_ status: Int, _ json: String) -> AuthError { AuthAPI.error(status: status, data: Data(json.utf8)) }
        XCTAssertEqual(error(400, #"{"code":400,"error_code":"invalid_credentials","msg":"Invalid login credentials"}"#), .invalidCredentials)
        XCTAssertEqual(error(400, #"{"code":400,"error_code":"email_not_confirmed","msg":"Email not confirmed"}"#), .emailNotConfirmed)
        XCTAssertEqual(error(422, #"{"code":422,"error_code":"user_already_exists","msg":"User already registered"}"#), .alreadyRegistered)
        XCTAssertEqual(error(400, #"{"error":"invalid_grant","error_description":"Invalid login credentials"}"#), .invalidCredentials)
        XCTAssertEqual(error(429, "{}"), .rateLimited)
        XCTAssertEqual(error(500, #"{"msg":"boom"}"#), .server("boom"))
        XCTAssertNotNil(AuthError.invalidCredentials.errorDescription)
    }
}
