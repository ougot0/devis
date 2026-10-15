import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Sceau d'intégrité d'un document émis.
///
/// À l'émission, le contenu de la facture est sérialisé de manière canonique puis haché
/// (SHA-256). Chaque sceau inclut l'empreinte du document précédent de la même série :
/// toute modification ultérieure d'une facture, ou suppression d'une facture au milieu
/// de la chaîne, est détectable par `SealVerifier`.
///
/// Limite : il s'agit d'une protection d'intégrité **locale**. Elle ne constitue ni une
/// signature électronique qualifiée, ni une certification au sens de l'article 286 du CGI.
public struct DocumentSeal: Codable, Sendable, Equatable {
    public var documentID: UUID
    public var number: String
    public var sealedAt: Date
    /// Empreinte SHA-256 (hexadécimal) du contenu canonique.
    public var contentHash: String
    /// Empreinte du sceau précédent de la série (chaîne vide pour le premier).
    public var previousSealHash: String
    /// SHA-256(contentHash + previousSealHash + number).
    public var sealHash: String
    public var formatVersion: Int

    public static let currentFormatVersion = 1
}

public enum DocumentSealer {

    public static func seal(_ document: BusinessDocument, previousSealHash: String, sealedAt: Date) -> DocumentSeal {
        let contentHash = hash(of: canonicalRepresentation(of: document))
        let sealHash = hash(of: contentHash + "|" + previousSealHash + "|" + document.number)
        return DocumentSeal(
            documentID: document.id,
            number: document.number,
            sealedAt: sealedAt,
            contentHash: contentHash,
            previousSealHash: previousSealHash,
            sealHash: sealHash,
            formatVersion: DocumentSeal.currentFormatVersion
        )
    }

    /// Le document correspond-il toujours à son sceau ?
    public static func verify(_ document: BusinessDocument, seal: DocumentSeal) -> Bool {
        guard document.number == seal.number else { return false }
        let contentHash = hash(of: canonicalRepresentation(of: document))
        guard contentHash == seal.contentHash else { return false }
        return seal.sealHash == hash(of: contentHash + "|" + seal.previousSealHash + "|" + seal.number)
    }

    public static func hash(of string: String) -> String {
        hash(of: Data(string.utf8))
    }

    public static func hash(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Sérialisation canonique et stable (indépendante de la plateforme et de l'ordre des clés).
    /// Les montants sont écrits avec un nombre fixe de décimales, les dates au format ISO.
    public static func canonicalRepresentation(of document: BusinessDocument) -> String {
        var fields: [String] = []
        func put(_ key: String, _ value: String) {
            let escaped = value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "=", with: "\\=")
                .replacingOccurrences(of: ";", with: "\\;")
            fields.append("\(key)=\(escaped)")
        }
        func date(_ value: Date?) -> String { value.map(DateFormatting.iso) ?? "" }
        func amount(_ value: Decimal) -> String { Money.plainString(value, scale: 4) }
        func address(_ prefix: String, _ value: PostalAddress) {
            put("\(prefix).line1", value.line1)
            put("\(prefix).line2", value.line2)
            put("\(prefix).postalCode", value.postalCode)
            put("\(prefix).city", value.city)
            put("\(prefix).country", value.country)
        }
        func discount(_ value: Discount) -> String {
            switch value {
            case .none: return "none"
            case .percent(let rate): return "percent:\(amount(rate))"
            case .amount(let value): return "amount:\(amount(value))"
            }
        }

        put("v", "1")
        put("id", document.id.uuidString)
        put("kind", document.kind.rawValue)
        put("number", document.number)
        put("issueDate", date(document.issueDate))
        put("serviceDate", date(document.serviceDate))
        put("dueDate", date(document.dueDate))
        put("validUntil", date(document.validUntil))
        put("title", document.title)

        let seller = document.seller
        put("seller.legalIdentity", seller.legalIdentity)
        put("seller.tradeName", seller.tradeName)
        put("seller.legalForm", seller.legalForm.rawValue)
        put("seller.capital", seller.shareCapital.map(amount) ?? "")
        address("seller.address", seller.address)
        put("seller.siren", seller.siren)
        put("seller.siret", seller.siret)
        put("seller.vatRegime", seller.vatRegime.rawValue)
        put("seller.vatNumber", seller.vatNumber)
        put("seller.iban", seller.iban)

        let customer = document.customer
        put("customer.kind", customer.kind.rawValue)
        put("customer.name", customer.name)
        put("customer.contact", customer.contactName)
        address("customer.address", customer.address)
        if let delivery = customer.deliveryAddress { address("customer.delivery", delivery) }
        put("customer.siren", customer.siren)
        put("customer.vatNumber", customer.vatNumber)

        for (index, line) in document.lines.enumerated() {
            let prefix = "line\(index)"
            put("\(prefix).kind", line.kind.rawValue)
            put("\(prefix).designation", line.designation)
            put("\(prefix).details", line.details)
            put("\(prefix).quantity", amount(line.quantity))
            put("\(prefix).unit", line.unit)
            put("\(prefix).unitPriceHT", amount(line.unitPriceHT))
            put("\(prefix).vatRate", amount(line.vatRate))
            put("\(prefix).discount", discount(line.discount))
            put("\(prefix).nature", line.nature.rawValue)
        }
        put("globalDiscount", discount(document.globalDiscount))
        for (index, deposit) in document.depositDeductions.enumerated() {
            put("deposit\(index)", "\(deposit.invoiceNumber)|\(date(deposit.issueDate))|\(amount(deposit.amountTTC))")
        }
        put("reverseCharge", document.reverseCharge ? "1" : "0")
        put("purchaseOrder", document.purchaseOrderReference)
        put("sourceQuote", document.sourceQuoteNumber)
        put("correctedInvoice", document.correctedInvoiceNumber)
        put("paymentTerms", document.paymentTermsText)
        put("specialConditions", document.specialConditions)
        put("notes", document.notes)
        // Champs ajoutés après la v1 : écrits seulement s'ils sont renseignés, pour que
        // les sceaux des factures émises auparavant restent valides.
        if let link = document.paymentLink, !link.isEmpty { put("paymentLink", link) }

        let totals = DocumentCalculator.totals(for: document)
        put("totalHT", amount(totals.totalHT))
        put("totalVAT", amount(totals.totalVAT))
        put("totalTTC", amount(totals.totalTTC))
        put("netToPay", amount(totals.netToPay))
        return fields.joined(separator: ";")
    }
}

/// Vérification d'une chaîne de sceaux (écran « Intégrité des factures »).
public enum SealVerifier {
    public enum Problem: Equatable, Sendable {
        case contentModified(number: String)
        case brokenChain(number: String)
        case missingSeal(number: String)
    }

    /// - Parameter entries: documents émis d'une série, dans l'ordre d'émission.
    public static func verifyChain(_ entries: [(document: BusinessDocument, seal: DocumentSeal?)]) -> [Problem] {
        var problems: [Problem] = []
        var previous = ""
        for entry in entries {
            guard let seal = entry.seal else {
                problems.append(.missingSeal(number: entry.document.number))
                continue
            }
            if !DocumentSealer.verify(entry.document, seal: seal) {
                problems.append(.contentModified(number: entry.document.number))
            }
            if seal.previousSealHash != previous {
                problems.append(.brokenChain(number: entry.document.number))
            }
            previous = seal.sealHash
        }
        return problems
    }
}
