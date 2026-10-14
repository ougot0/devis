import Foundation

/// Série de numérotation (une par type de document).
public enum NumberingSeries: String, Codable, Sendable, CaseIterable {
    case quote
    /// Factures et factures d'acompte partagent la même séquence continue.
    case invoice
    case creditNote

    public static func series(for kind: DocumentKind) -> NumberingSeries {
        switch kind {
        case .quote: return .quote
        case .invoice, .depositInvoice: return .invoice
        case .creditNote: return .creditNote
        }
    }
}

/// Format de numéro. Jetons : `{AAAA}` année, `{AA}` année sur 2 chiffres,
/// `{MM}` mois, `{N}` séquence, `{N:4}` séquence complétée par des zéros.
public struct NumberingScheme: Codable, Sendable, Equatable {
    public var pattern: String
    /// Remise à 1 de la séquence au 1er janvier. Exige `{AAAA}` ou `{AA}` dans le motif
    /// pour que les numéros restent uniques.
    public var resetsYearly: Bool

    public init(pattern: String, resetsYearly: Bool) {
        self.pattern = pattern
        self.resetsYearly = resetsYearly
    }

    public static let defaultQuote = NumberingScheme(pattern: "D-{AAAA}-{N:4}", resetsYearly: true)
    public static let defaultInvoice = NumberingScheme(pattern: "F-{AAAA}-{N:4}", resetsYearly: true)
    public static let defaultCreditNote = NumberingScheme(pattern: "AV-{AAAA}-{N:4}", resetsYearly: true)

    public static func `default`(for series: NumberingSeries) -> NumberingScheme {
        switch series {
        case .quote: return .defaultQuote
        case .invoice: return .defaultInvoice
        case .creditNote: return .defaultCreditNote
        }
    }

    public var containsYear: Bool { pattern.contains("{AAAA}") || pattern.contains("{AA}") }
    public var containsSequence: Bool { pattern.range(of: #"\{N(:\d+)?\}"#, options: .regularExpression) != nil }

    /// Vérifie que le motif garantit des numéros uniques.
    public func validate() throws {
        guard containsSequence else { throw NumberingError.patternWithoutSequence }
        if resetsYearly && !containsYear { throw NumberingError.yearlyResetWithoutYear }
        guard pattern.count <= 40 else { throw NumberingError.patternTooLong }
    }

    public func format(sequence: Int, date: Date, calendar: Calendar = .devisMinute) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 1
        var result = pattern
            .replacingOccurrences(of: "{AAAA}", with: String(format: "%04d", year))
            .replacingOccurrences(of: "{AA}", with: String(format: "%02d", year % 100))
            .replacingOccurrences(of: "{MM}", with: String(format: "%02d", month))
        if let range = result.range(of: #"\{N:(\d+)\}"#, options: .regularExpression) {
            let token = String(result[range])
            let width = Int(token.dropFirst(3).dropLast()) ?? 1
            var digits = String(sequence)
            while digits.count < min(width, 9) { digits = "0" + digits }
            result.replaceSubrange(range, with: digits)
        }
        result = result.replacingOccurrences(of: "{N}", with: String(sequence))
        return result
    }
}

/// État persistant d'une série : dernier numéro attribué.
public struct NumberingState: Codable, Sendable, Equatable {
    public var lastSequence: Int
    public var lastYear: Int?
    /// Date d'émission du dernier document numéroté (contrôle chronologique).
    public var lastIssueDate: Date?
    public var lastNumber: String

    public init(lastSequence: Int = 0, lastYear: Int? = nil, lastIssueDate: Date? = nil, lastNumber: String = "") {
        self.lastSequence = lastSequence
        self.lastYear = lastYear
        self.lastIssueDate = lastIssueDate
        self.lastNumber = lastNumber
    }
}

public enum NumberingError: Error, Equatable, LocalizedError {
    case patternWithoutSequence
    case yearlyResetWithoutYear
    case patternTooLong
    case notChronological(lastIssueDate: Date, lastNumber: String)
    case duplicateNumber(String)

    public var errorDescription: String? {
        switch self {
        case .patternWithoutSequence:
            return "Le format de numérotation doit contenir le compteur {N}."
        case .yearlyResetWithoutYear:
            return "La remise à zéro annuelle impose l'année ({AAAA}) dans le format, sinon des numéros seraient en double."
        case .patternTooLong:
            return "Le format de numérotation est trop long (40 caractères maximum)."
        case .notChronological(let date, let number):
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "fr_FR")
            formatter.dateStyle = .medium
            formatter.timeZone = Calendar.devisMinute.timeZone
            return "La numérotation doit être chronologique : le document \(number) a été émis le \(formatter.string(from: date)). La date d'émission ne peut pas être antérieure."
        case .duplicateNumber(let number):
            return "Le numéro \(number) existe déjà."
        }
    }
}

/// Attribution de numéros chronologiques et continus.
///
/// Les factures ne reçoivent leur numéro qu'au moment de leur émission définitive :
/// un brouillon supprimé ne crée donc jamais de « trou » dans la séquence.
public enum NumberingService {

    /// Calcule le prochain numéro et le nouvel état, sans rien modifier.
    /// - Throws: `NumberingError.notChronological` si `issueDate` précède le dernier document.
    public static func next(
        scheme: NumberingScheme,
        state: NumberingState,
        issueDate: Date,
        existingNumbers: Set<String> = [],
        calendar: Calendar = .devisMinute
    ) throws -> (number: String, state: NumberingState) {
        try scheme.validate()
        if let last = state.lastIssueDate,
           calendar.startOfDay(for: issueDate) < calendar.startOfDay(for: last) {
            throw NumberingError.notChronological(lastIssueDate: last, lastNumber: state.lastNumber)
        }
        let year = calendar.component(.year, from: issueDate)
        var sequence = state.lastSequence + 1
        if scheme.resetsYearly, let lastYear = state.lastYear, year != lastYear {
            sequence = 1
        }
        let number = scheme.format(sequence: sequence, date: issueDate, calendar: calendar)
        if existingNumbers.contains(number) { throw NumberingError.duplicateNumber(number) }
        let newState = NumberingState(lastSequence: sequence, lastYear: year, lastIssueDate: issueDate, lastNumber: number)
        return (number, newState)
    }

    /// Aperçu du prochain numéro (affichage dans l'éditeur), sans contrôle chronologique.
    public static func preview(scheme: NumberingScheme, state: NumberingState, issueDate: Date, calendar: Calendar = .devisMinute) -> String {
        let year = calendar.component(.year, from: issueDate)
        var sequence = state.lastSequence + 1
        if scheme.resetsYearly, let lastYear = state.lastYear, year != lastYear { sequence = 1 }
        return scheme.format(sequence: sequence, date: issueDate, calendar: calendar)
    }

    /// Contrôle a posteriori d'une liste de numéros émis dans l'ordre :
    /// retourne les ruptures de séquence détectées (pour l'écran « Intégrité »).
    public static func gaps(in sequences: [Int]) -> [ClosedRange<Int>] {
        let sorted = sequences.sorted()
        var result: [ClosedRange<Int>] = []
        for (previous, current) in zip(sorted, sorted.dropFirst()) where current > previous + 1 {
            result.append((previous + 1)...(current - 1))
        }
        return result
    }
}
