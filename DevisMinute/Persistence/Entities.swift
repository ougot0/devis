import Foundation
import SwiftData
import DevisCore

/// Persistance SwiftData.
///
/// Choix d'architecture : le contenu métier (valeurs `Codable` de DevisCore) est stocké en JSON
/// dans `payload`, et seuls les champs utiles aux listes, au tri et à la recherche sont dupliqués
/// en colonnes. Avantages : le contenu d'une facture émise est exactement celui qui a été scellé,
/// les `Decimal` ne transitent jamais par un `Double`, et le schéma SwiftData reste minimal
/// (migrations plus simples).
enum PayloadCoding {
    static func encode<T: Encodable>(_ value: T) -> Data {
        (try? BackupService.encoder().encode(value)) ?? Data()
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? BackupService.decoder().decode(type, from: data)
    }
}

/// Réglages de l'entreprise (une seule instance).
@Model
final class SettingsEntity {
    var profile: Data
    var appearance: Data
    @Attribute(.externalStorage) var logoJPEG: Data?
    /// `[série: NumberingState]`
    var numbering: Data
    /// `[série: NumberingScheme]`
    var schemes: Data
    /// Dernier sceau de chaque série : `[série: hash]`.
    var sealHeads: Data
    var onboardingCompleted: Bool
    var appLockEnabled: Bool
    var createdAt: Date

    init() {
        profile = PayloadCoding.encode(CompanyProfile())
        appearance = Data()
        logoJPEG = nil
        numbering = PayloadCoding.encode([String: NumberingState]())
        schemes = PayloadCoding.encode([String: NumberingScheme]())
        sealHeads = PayloadCoding.encode([String: String]())
        onboardingCompleted = false
        appLockEnabled = false
        createdAt = Date()
    }
}

@Model
final class CustomerEntity {
    @Attribute(.unique) var id: UUID
    var name: String
    var kindRaw: String
    var city: String
    var searchText: String
    var isArchived: Bool
    var createdAt: Date
    var payload: Data

    init(record: CustomerRecord) {
        id = record.id
        name = ""
        kindRaw = ""
        city = ""
        searchText = ""
        isArchived = false
        createdAt = record.createdAt
        payload = Data()
        apply(record)
    }

    func apply(_ record: CustomerRecord) {
        let snapshot = record.snapshot
        name = snapshot.name
        kindRaw = snapshot.kind.rawValue
        city = snapshot.address.city
        isArchived = record.isArchived
        searchText = [snapshot.name, snapshot.contactName, snapshot.address.city, snapshot.email, snapshot.phone, snapshot.siren, record.notes]
            .joined(separator: " ").lowercased()
        payload = PayloadCoding.encode(record)
    }

    var record: CustomerRecord? { PayloadCoding.decode(CustomerRecord.self, from: payload) }
}

@Model
final class CatalogEntity {
    @Attribute(.unique) var id: UUID
    var name: String
    var category: String
    var searchText: String
    var isArchived: Bool
    var payload: Data

    init(item: CatalogItem) {
        id = item.id
        name = ""
        category = ""
        searchText = ""
        isArchived = false
        payload = Data()
        apply(item)
    }

    func apply(_ item: CatalogItem) {
        name = item.name
        category = item.category
        isArchived = item.isArchived
        searchText = [item.name, item.details, item.category].joined(separator: " ").lowercased()
        payload = PayloadCoding.encode(item)
    }

    var item: CatalogItem? { PayloadCoding.decode(CatalogItem.self, from: payload) }
}

/// Groupe d'affichage : devis d'un côté, factures/acomptes/avoirs de l'autre.
enum DocumentGroup: String {
    case quotes
    case invoices

    static func of(_ kind: DocumentKind) -> DocumentGroup { kind == .quote ? .quotes : .invoices }
}

@Model
final class DocumentEntity {
    @Attribute(.unique) var id: UUID
    var group: String
    var kindRaw: String
    var number: String
    var issueDate: Date
    var customerName: String
    var customerID: UUID?
    /// Statut de devis ou de facture (`QuoteStatus` / `InvoiceStatus`).
    var statusRaw: String
    var isIssued: Bool
    /// Total TTC en centimes (affichage et tri uniquement).
    var totalCents: Int
    var searchText: String
    var updatedAt: Date
    @Attribute(.externalStorage) var payload: Data

    init(record: DocumentRecord) {
        id = record.id
        group = ""
        kindRaw = ""
        number = ""
        issueDate = record.document.issueDate
        customerName = ""
        customerID = nil
        statusRaw = ""
        isIssued = false
        totalCents = 0
        searchText = ""
        updatedAt = record.updatedAt
        payload = Data()
        apply(record)
    }

    func apply(_ record: DocumentRecord) {
        let document = record.document
        group = DocumentGroup.of(document.kind).rawValue
        kindRaw = document.kind.rawValue
        number = document.number
        issueDate = document.issueDate
        customerName = document.customer.name
        customerID = record.customerID
        statusRaw = record.quoteStatus?.rawValue ?? record.invoiceStatus?.rawValue ?? ""
        isIssued = record.isIssuedInvoice
        let total = DocumentCalculator.totals(for: document).totalTTC
        totalCents = NSDecimalNumber(decimal: Money.round(total * 100, scale: 0)).intValue
        searchText = ([document.number, document.customer.name, document.title] + document.lines.map(\.designation))
            .joined(separator: " ").lowercased()
        updatedAt = record.updatedAt
        payload = PayloadCoding.encode(record)
    }

    var record: DocumentRecord? { PayloadCoding.decode(DocumentRecord.self, from: payload) }
}

enum AppSchema {
    static let models: [any PersistentModel.Type] = [SettingsEntity.self, CustomerEntity.self, CatalogEntity.self, DocumentEntity.self]
}
