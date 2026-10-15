import Foundation

/// Signature manuscrite du client, recueillie à l'écran pour accepter un devis.
/// C'est une signature électronique simple : elle prouve l'accord du client mais n'est pas
/// une signature électronique qualifiée (aucun certificat, aucun tiers de confiance).
public struct QuoteSignature: Codable, Sendable, Equatable {
    /// Mention recopiée sur le devis signé.
    public static let acceptanceMention = "Devis reçu avant l'exécution des travaux, bon pour accord"

    public var signerName: String
    public var signedAt: Date
    /// Lieu de signature (facultatif).
    public var place: String
    /// Tracé de la signature, JPEG sur fond blanc.
    public var imageJPEG: Data
    /// Empreinte SHA-256 du devis au moment de la signature.
    public var documentHash: String

    public init(signerName: String, signedAt: Date, place: String = "", imageJPEG: Data, documentHash: String) {
        self.signerName = signerName
        self.signedAt = signedAt
        self.place = place
        self.imageJPEG = imageJPEG
        self.documentHash = documentHash
    }

    /// Signe `document` : l'empreinte lie la signature au contenu exact du devis.
    public static func make(for document: BusinessDocument, signerName: String, place: String = "", imageJPEG: Data, signedAt: Date = Date()) throws -> QuoteSignature {
        let name = signerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard document.kind == .quote else { throw SignatureError.notAQuote }
        guard !name.isEmpty else { throw SignatureError.missingSignerName }
        guard !imageJPEG.isEmpty else { throw SignatureError.missingDrawing }
        return QuoteSignature(
            signerName: name,
            signedAt: signedAt,
            place: place.trimmingCharacters(in: .whitespacesAndNewlines),
            imageJPEG: imageJPEG,
            documentHash: DocumentSealer.hash(of: DocumentSealer.canonicalRepresentation(of: document))
        )
    }

    /// Vrai si le devis n'a pas changé depuis la signature.
    public func matches(_ document: BusinessDocument) -> Bool {
        documentHash == DocumentSealer.hash(of: DocumentSealer.canonicalRepresentation(of: document))
    }
}

public enum SignatureError: Error, LocalizedError, Equatable {
    case notAQuote
    case missingSignerName
    case missingDrawing
    case cannotSign(status: String)

    public var errorDescription: String? {
        switch self {
        case .notAQuote: return "Seul un devis peut être signé."
        case .missingSignerName: return "Indiquez le nom de la personne qui signe."
        case .missingDrawing: return "Le client doit signer dans le cadre."
        case .cannotSign(let status): return "Un devis « \(status) » ne peut plus être signé."
        }
    }
}
