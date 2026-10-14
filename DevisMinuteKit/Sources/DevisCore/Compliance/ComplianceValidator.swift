import Foundation

/// Gravité d'un point de contrôle.
public enum ComplianceSeverity: String, Sendable, Comparable {
    /// Empêche l'émission de la facture.
    case blocking
    /// Signalé, l'utilisateur peut continuer.
    case warning
    /// Information (ex. obligation à venir).
    case info

    private var order: Int { self == .blocking ? 0 : (self == .warning ? 1 : 2) }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.order < rhs.order }
}

/// Résultat d'un contrôle de mentions.
public struct ComplianceIssue: Sendable, Equatable, Identifiable {
    public var code: String
    public var severity: ComplianceSeverity
    public var message: String
    public var id: String { code }
}

/// Contrôle des mentions obligatoires avant émission.
///
/// Ce contrôle est une **aide** : il ne garantit pas la conformité juridique d'un document.
/// Les règles sont listées dans docs/CONFORMITE.md avec leurs sources.
public enum ComplianceValidator {

    /// Date de généralisation de l'émission électronique pour les PME et micro-entreprises
    /// (1er septembre 2027, service-public.fr F39785, vérifiée le 07/08/2026).
    public static let smeEInvoicingIssuanceDate: Date = {
        var components = DateComponents()
        components.year = 2027
        components.month = 9
        components.day = 1
        return Calendar.devisMinute.date(from: components) ?? Date.distantFuture
    }()

    public static func validate(_ document: BusinessDocument, today: Date = Date()) -> [ComplianceIssue] {
        var issues: [ComplianceIssue] = []
        let seller = document.seller
        let customer = document.customer
        let totals = DocumentCalculator.totals(for: document)
        let isInvoice = document.kind.isInvoiceLike

        func add(_ code: String, _ severity: ComplianceSeverity, _ message: String) {
            issues.append(ComplianceIssue(code: code, severity: severity, message: message))
        }

        // Émetteur
        if seller.legalIdentity.trimmed.isEmpty || seller.legalIdentity == "EI" {
            add("seller.name", .blocking, "Renseignez votre nom ou votre dénomination sociale.")
        }
        if seller.address.isEmpty {
            add("seller.address", .blocking, "Renseignez l'adresse de votre entreprise.")
        }
        let sirenDigits = seller.siren.filter(\.isNumber)
        let siretDigits = seller.siret.filter(\.isNumber)
        if sirenDigits.isEmpty && siretDigits.isEmpty {
            add("seller.siren", isInvoice ? .blocking : .warning, "Le numéro SIREN ou SIRET de l'entreprise est obligatoire.")
        } else {
            if !sirenDigits.isEmpty && !Identifiers.isValidSIREN(sirenDigits) {
                add("seller.siren.invalid", .warning, "Le SIREN saisi ne semble pas valide (9 chiffres, clé de Luhn).")
            }
            if !siretDigits.isEmpty && !Identifiers.isValidSIRET(siretDigits) {
                add("seller.siret.invalid", .warning, "Le SIRET saisi ne semble pas valide (14 chiffres, clé de Luhn).")
            }
        }
        if seller.legalForm.isCompany {
            if seller.shareCapital == nil || seller.shareCapital == 0 {
                add("seller.capital", .warning, "Indiquez le montant du capital social de la société.")
            }
            if seller.registry == .none {
                add("seller.registry", .warning, "Indiquez la ville d'immatriculation au RCS (mention « RCS Ville »).")
            }
        }
        if seller.isVATRegistered && seller.vatNumber.trimmed.isEmpty && isInvoice && totals.totalHT > 150 {
            add("seller.vat", .blocking, "Votre numéro de TVA intracommunautaire est obligatoire (facture de plus de 150 € HT).")
        }

        // Client
        if customer.name.trimmed.isEmpty {
            add("customer.name", .blocking, "Indiquez le nom ou la raison sociale du client.")
        }
        if customer.address.isEmpty {
            add("customer.address", customer.kind == .individual ? .warning : .blocking, "Renseignez l'adresse du client.")
        }
        if customer.kind.isProfessional && customer.siren.filter(\.isNumber).isEmpty && customer.address.country.lowercased() == "france" {
            let mandatory = today >= smeEInvoicingIssuanceDate
            add("customer.siren", mandatory ? .blocking : .info,
                "Le SIREN du client professionnel devient une mention obligatoire avec la facturation électronique (1er septembre 2027 pour les PME et micro-entreprises).")
        }
        if seller.isVATRegistered && customer.kind == .business && customer.vatNumber.trimmed.isEmpty && isInvoice && totals.totalHT > 150 {
            add("customer.vat", .warning, "Le numéro de TVA intracommunautaire du client professionnel doit figurer sur la facture s'il en dispose.")
        }
        if document.reverseCharge && customer.vatNumber.trimmed.isEmpty {
            add("customer.vat.reverseCharge", .warning, "En autoliquidation, le numéro de TVA du client est indispensable.")
        }

        // Contenu
        if document.itemLines.isEmpty {
            add("lines.empty", .blocking, "Ajoutez au moins une ligne chiffrée.")
        }
        for (index, line) in document.itemLines.enumerated() {
            if line.designation.trimmed.isEmpty {
                add("line.\(index).designation", .blocking, "La ligne \(index + 1) n'a pas de désignation.")
            }
            if line.quantity <= 0 {
                add("line.\(index).quantity", .warning, "La ligne \(index + 1) a une quantité nulle ou négative.")
            }
            if line.unitPriceHT < 0 {
                add("line.\(index).price", .warning, "La ligne \(index + 1) a un prix négatif : utilisez plutôt une remise ou un avoir.")
            }
            if seller.isVATRegistered && !document.reverseCharge && !VATRates.isKnownFrenchRate(line.vatRate) {
                add("line.\(index).vat", .warning, "Le taux de TVA de la ligne \(index + 1) (\(Money.formatQuantity(line.vatRate)) %) n'est pas un taux français usuel.")
            }
        }

        // Dates
        if isInvoice && document.kind != .creditNote {
            if document.dueDate == nil {
                add("invoice.dueDate", .blocking, "Indiquez la date d'échéance du paiement.")
            } else if let due = document.dueDate, due < document.issueDate {
                add("invoice.dueDate.before", .blocking, "L'échéance ne peut pas précéder la date d'émission.")
            }
            if let due = document.dueDate, document.isBusinessToBusiness {
                let days = Calendar.devisMinute.dateComponents([.day], from: document.issueDate, to: due).day ?? 0
                if days > 60 {
                    add("invoice.dueDate.limit", .warning, "Entre professionnels, le délai de paiement ne peut en principe excéder 60 jours après l'émission (art. L441-10 du Code de commerce).")
                }
            }
            if document.serviceDate == nil {
                add("invoice.serviceDate", .warning, "Indiquez la date de la vente ou de la prestation.")
            }
        }
        if document.kind == .quote, document.validUntil == nil {
            add("quote.validity", .warning, "Indiquez une date de validité pour le devis.")
        }
        if document.kind == .creditNote && document.correctedInvoiceNumber.trimmed.isEmpty {
            add("credit.reference", .blocking, "Un avoir doit mentionner la facture qu'il corrige.")
        }
        if totals.netToPay < 0 {
            add("totals.negative", .blocking, "Le net à payer est négatif : vérifiez les acomptes déduits.")
        }
        return issues.sorted { $0.severity < $1.severity }
    }

    public static func hasBlockingIssues(_ issues: [ComplianceIssue]) -> Bool {
        issues.contains { $0.severity == .blocking }
    }
}

/// Taux de TVA applicables en France métropolitaine (CGI art. 278 et suivants).
public enum VATRates {
    public static let standard: [Decimal] = [20, 10, Decimal.exact("5.5"), Decimal.exact("2.1"), 0]
    /// Taux applicables en Corse et dans les DOM (non proposés par défaut).
    public static let other: [Decimal] = [Decimal.exact("8.5"), Decimal.exact("13"), Decimal.exact("0.9"), Decimal.exact("1.75"), Decimal.exact("1.05")]

    public static func isKnownFrenchRate(_ rate: Decimal) -> Bool {
        standard.contains(rate) || other.contains(rate)
    }
}

/// Contrôles de format des identifiants d'entreprise.
public enum Identifiers {
    /// SIREN : 9 chiffres, clé de Luhn.
    public static func isValidSIREN(_ value: String) -> Bool {
        let digits = value.filter(\.isNumber)
        return digits.count == 9 && digits.count == value.filter({ !$0.isWhitespace }).count && luhn(digits)
    }

    /// SIRET : 14 chiffres, clé de Luhn (exception documentée : établissements de La Poste).
    public static func isValidSIRET(_ value: String) -> Bool {
        let digits = value.filter(\.isNumber)
        guard digits.count == 14 else { return false }
        if digits.hasPrefix("356000000") {
            return digits.reduce(0) { $0 + Int(String($1))! } % 5 == 0
        }
        return luhn(digits)
    }

    /// Numéro de TVA intracommunautaire français : FR + clé (2 caractères) + SIREN.
    public static func isValidFrenchVATNumber(_ value: String) -> Bool {
        let compact = value.uppercased().filter { !$0.isWhitespace }
        guard compact.count == 13, compact.hasPrefix("FR") else { return false }
        let key = compact.dropFirst(2).prefix(2)
        let siren = String(compact.suffix(9))
        guard isValidSIREN(siren), let keyValue = Int(key), let sirenValue = Int(siren) else {
            // Les clés alphanumériques existent mais sont rares ; on accepte le format.
            return isValidSIREN(siren)
        }
        return keyValue == (12 + 3 * (sirenValue % 97)) % 97
    }

    /// Clé TVA calculée à partir d'un SIREN (aide à la saisie).
    public static func frenchVATNumber(fromSIREN siren: String) -> String? {
        let digits = siren.filter(\.isNumber)
        guard isValidSIREN(digits), let value = Int(digits) else { return nil }
        let key = (12 + 3 * (value % 97)) % 97
        return String(format: "FR%02d%@", key, digits)
    }

    /// IBAN : contrôle modulo 97 (ISO 13616).
    public static func isValidIBAN(_ value: String) -> Bool {
        let compact = value.uppercased().filter { !$0.isWhitespace }
        guard compact.count >= 15, compact.count <= 34, compact.allSatisfy({ $0.isLetter || $0.isNumber }) else { return false }
        let rearranged = compact.dropFirst(4) + compact.prefix(4)
        var remainder = 0
        for character in rearranged {
            guard let ascii = character.asciiValue else { return false }
            let digits: String
            if character.isNumber {
                digits = String(character)
            } else {
                digits = String(Int(ascii) - 55)
            }
            for digit in digits {
                remainder = (remainder * 10 + Int(String(digit))!) % 97
            }
        }
        return remainder == 1
    }

    private static func luhn(_ digits: String) -> Bool {
        var sum = 0
        for (index, character) in digits.reversed().enumerated() {
            guard var digit = Int(String(character)) else { return false }
            if index % 2 == 1 {
                digit *= 2
                if digit > 9 { digit -= 9 }
            }
            sum += digit
        }
        return sum % 10 == 0
    }
}
