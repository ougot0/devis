import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Contenu complet d'une sauvegarde. Format documenté dans docs/SAUVEGARDE.md.
public struct BackupSnapshot: Codable, Sendable, Equatable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var createdAt: Date
    public var appVersion: String
    public var company: CompanyProfile
    public var customers: [CustomerRecord]
    public var catalog: [CatalogItem]
    public var documents: [DocumentRecord]
    public var numbering: [String: NumberingState]
    public var numberingSchemes: [String: NumberingScheme]
    /// Réglages d'apparence et préférences de l'application (JSON opaque pour le cœur).
    public var settings: Data?
    public var logo: Data?

    public init(createdAt: Date = Date(), appVersion: String, company: CompanyProfile, customers: [CustomerRecord], catalog: [CatalogItem], documents: [DocumentRecord], numbering: [String: NumberingState], numberingSchemes: [String: NumberingScheme] = [:], settings: Data? = nil, logo: Data? = nil) {
        self.formatVersion = Self.currentFormatVersion
        self.createdAt = createdAt
        self.appVersion = appVersion
        self.company = company
        self.customers = customers
        self.catalog = catalog
        self.documents = documents
        self.numbering = numbering
        self.numberingSchemes = numberingSchemes
        self.settings = settings
        self.logo = logo
    }
}

/// Enveloppe du fichier « .devisminute » (JSON).
public struct BackupEnvelope: Codable, Sendable {
    public struct Encryption: Codable, Sendable, Equatable {
        public var algorithm: String
        public var kdf: String
        public var iterations: Int
        public var salt: Data
    }

    public var format: String
    public var version: Int
    public var createdAt: Date
    public var documentCount: Int
    public var customerCount: Int
    public var encryption: Encryption?
    /// SHA-256 (hex) du contenu JSON en clair : vérifié à la restauration.
    public var payloadSHA256: String
    /// Contenu : JSON en clair, ou nonce + texte chiffré + étiquette AES-GCM.
    public var payload: Data

    public static let formatIdentifier = "devisminute-backup"
}

public enum BackupError: Error, Equatable, LocalizedError {
    case notABackup
    case unsupportedVersion(Int)
    case passwordRequired
    case wrongPasswordOrCorrupted
    case integrityCheckFailed
    case invalidContent(String)
    case weakPassword

    public var errorDescription: String? {
        switch self {
        case .notABackup: return "Ce fichier n'est pas une sauvegarde DevisMinute."
        case .unsupportedVersion(let version): return "Cette sauvegarde (format \(version)) a été créée par une version plus récente de l'application. Mettez DevisMinute à jour."
        case .passwordRequired: return "Cette sauvegarde est protégée par un mot de passe."
        case .wrongPasswordOrCorrupted: return "Mot de passe incorrect, ou fichier endommagé."
        case .integrityCheckFailed: return "Le contrôle d'intégrité a échoué : le fichier a été modifié ou endommagé. Aucune donnée n'a été restaurée."
        case .invalidContent(let detail): return "Contenu invalide : \(detail)"
        case .weakPassword: return "Le mot de passe doit comporter au moins 8 caractères."
        }
    }
}

/// Résultat de la vérification d'une sauvegarde avant restauration.
public struct BackupInspection: Sendable {
    public var snapshot: BackupSnapshot
    /// Anomalies non bloquantes (sceaux de factures invalides, références orphelines…).
    public var warnings: [String]
}

/// Création, chiffrement et vérification des sauvegardes. Tout est local.
public enum BackupService {
    /// PBKDF2-HMAC-SHA256 : 600 000 itérations (recommandation OWASP 2023).
    public static let defaultIterations = 600_000

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.dataEncodingStrategy = .base64
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        decoder.dataDecodingStrategy = .base64
        return decoder
    }

    /// Produit le fichier de sauvegarde. Avec un mot de passe, le contenu est chiffré (AES-256-GCM).
    public static func makeArchive(_ snapshot: BackupSnapshot, password: String?, iterations: Int = defaultIterations) throws -> Data {
        let plain = try encoder().encode(snapshot)
        let digest = DocumentSealer.hash(of: plain)
        var encryption: BackupEnvelope.Encryption?
        var payload = plain
        if let password {
            guard password.count >= 8 else { throw BackupError.weakPassword }
            var salt = Data(count: 16)
            for index in 0..<16 { salt[index] = UInt8.random(in: 0...255) }
            let key = PBKDF2.deriveKey(password: password, salt: salt, iterations: iterations, length: 32)
            let sealed = try AES.GCM.seal(plain, using: SymmetricKey(data: key), authenticating: Data(digest.utf8))
            guard let combined = sealed.combined else { throw BackupError.invalidContent("chiffrement") }
            payload = combined
            encryption = .init(algorithm: "AES-256-GCM", kdf: "PBKDF2-HMAC-SHA256", iterations: iterations, salt: salt)
        }
        let envelope = BackupEnvelope(
            format: BackupEnvelope.formatIdentifier,
            version: BackupSnapshot.currentFormatVersion,
            createdAt: snapshot.createdAt,
            documentCount: snapshot.documents.count,
            customerCount: snapshot.customers.count,
            encryption: encryption,
            payloadSHA256: digest,
            payload: payload
        )
        let envelopeEncoder = encoder()
        envelopeEncoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try envelopeEncoder.encode(envelope)
    }

    /// Lit l'enveloppe sans déchiffrer (pour savoir si un mot de passe est nécessaire).
    public static func readEnvelope(_ data: Data) throws -> BackupEnvelope {
        guard let envelope = try? decoder().decode(BackupEnvelope.self, from: data), envelope.format == BackupEnvelope.formatIdentifier else {
            throw BackupError.notABackup
        }
        guard envelope.version <= BackupSnapshot.currentFormatVersion else { throw BackupError.unsupportedVersion(envelope.version) }
        return envelope
    }

    /// Déchiffre, vérifie l'intégrité et la cohérence. Ne modifie aucune donnée.
    public static func inspect(_ data: Data, password: String?) throws -> BackupInspection {
        let envelope = try readEnvelope(data)
        var plain = envelope.payload
        if let encryption = envelope.encryption {
            guard let password, !password.isEmpty else { throw BackupError.passwordRequired }
            let key = PBKDF2.deriveKey(password: password, salt: encryption.salt, iterations: encryption.iterations, length: 32)
            do {
                let box = try AES.GCM.SealedBox(combined: envelope.payload)
                plain = try AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: Data(envelope.payloadSHA256.utf8))
            } catch {
                throw BackupError.wrongPasswordOrCorrupted
            }
        }
        guard DocumentSealer.hash(of: plain) == envelope.payloadSHA256 else { throw BackupError.integrityCheckFailed }
        let snapshot: BackupSnapshot
        do {
            snapshot = try decoder().decode(BackupSnapshot.self, from: plain).normalized()
        } catch {
            throw BackupError.invalidContent(String(describing: error))
        }
        guard snapshot.formatVersion <= BackupSnapshot.currentFormatVersion else { throw BackupError.unsupportedVersion(snapshot.formatVersion) }
        return BackupInspection(snapshot: snapshot, warnings: try validate(snapshot))
    }

    /// Contrôles de cohérence. Lève une erreur pour les incohérences graves.
    public static func validate(_ snapshot: BackupSnapshot) throws -> [String] {
        var warnings: [String] = []
        let documentIDs = snapshot.documents.map(\.id)
        guard Set(documentIDs).count == documentIDs.count else { throw BackupError.invalidContent("identifiants de documents en double") }
        let customerIDs = Set(snapshot.customers.map(\.id))
        guard customerIDs.count == snapshot.customers.count else { throw BackupError.invalidContent("identifiants de clients en double") }
        var issuedNumbers: Set<String> = []
        for record in snapshot.documents where record.isIssuedInvoice {
            let key = "\(record.document.kind == .creditNote ? "A" : "F")|\(record.document.number)"
            guard !record.document.number.isEmpty, issuedNumbers.insert(key).inserted else {
                throw BackupError.invalidContent("numéro de facture vide ou en double (\(record.document.number))")
            }
            if let seal = record.seal {
                if !DocumentSealer.verify(record.document, seal: seal) {
                    warnings.append("La facture \(record.document.number) ne correspond plus à son sceau d'intégrité.")
                }
            } else {
                warnings.append("La facture \(record.document.number) n'a pas de sceau d'intégrité.")
            }
        }
        for record in snapshot.documents {
            if let customerID = record.customerID, !customerIDs.contains(customerID) {
                warnings.append("Le document \(record.document.number.isEmpty ? record.document.kind.title : record.document.number) référence un client absent de la sauvegarde (les coordonnées figées dans le document sont conservées).")
            }
        }
        return warnings
    }
}

extension BackupSnapshot {
    /// Élimine d'éventuels artefacts binaires de décodage des `Decimal` (ex. 0,1000000000000000055)
    /// en arrondissant à 6 décimales : les montants métier n'en ont jamais plus de 4.
    func normalized() -> BackupSnapshot {
        func n(_ value: Decimal) -> Decimal { Money.round(value, scale: 6) }
        func n(_ discount: Discount) -> Discount {
            switch discount {
            case .none: return .none
            case .percent(let value): return .percent(n(value))
            case .amount(let value): return .amount(n(value))
            }
        }
        var copy = self
        copy.catalog = catalog.map { item in
            var item = item
            item.price = n(item.price)
            item.vatRate = n(item.vatRate)
            item.unitCost = item.unitCost.map(n)
            return item
        }
        copy.company.shareCapital = company.shareCapital.map(n)
        copy.documents = documents.map { record in
            var record = record
            record.document.lines = record.document.lines.map { line in
                var line = line
                line.quantity = n(line.quantity)
                line.unitPriceHT = n(line.unitPriceHT)
                line.vatRate = n(line.vatRate)
                line.discount = n(line.discount)
                line.unitCost = line.unitCost.map(n)
                return line
            }
            record.document.globalDiscount = n(record.document.globalDiscount)
            switch record.document.depositRequest {
            case .none: break
            case .percent(let value): record.document.depositRequest = .percent(n(value))
            case .amount(let value): record.document.depositRequest = .amount(n(value))
            }
            record.document.depositDeductions = record.document.depositDeductions.map { deposit in
                var deposit = deposit
                deposit.amountTTC = n(deposit.amountTTC)
                return deposit
            }
            record.document.seller.shareCapital = record.document.seller.shareCapital.map(n)
            record.payments = record.payments.map { payment in
                var payment = payment
                payment.amount = n(payment.amount)
                return payment
            }
            return record
        }
        return copy
    }
}

/// PBKDF2-HMAC-SHA256 (RFC 8018), implémenté sur HMAC de CryptoKit.
public enum PBKDF2 {
    public static func deriveKey(password: String, salt: Data, iterations: Int, length: Int) -> Data {
        let key = SymmetricKey(data: Data(password.precomposedStringWithCanonicalMapping.utf8))
        var derived = Data()
        var blockIndex: UInt32 = 1
        while derived.count < length {
            var saltBlock = salt
            saltBlock.append(contentsOf: [UInt8(blockIndex >> 24), UInt8((blockIndex >> 16) & 0xFF), UInt8((blockIndex >> 8) & 0xFF), UInt8(blockIndex & 0xFF)])
            var u = Data(HMAC<SHA256>.authenticationCode(for: saltBlock, using: key))
            var block = [UInt8](u)
            if iterations > 1 {
                for _ in 1..<iterations {
                    u = Data(HMAC<SHA256>.authenticationCode(for: u, using: key))
                    for (index, byte) in u.enumerated() { block[index] ^= byte }
                }
            }
            derived.append(contentsOf: block)
            blockIndex += 1
        }
        return derived.prefix(length)
    }
}
