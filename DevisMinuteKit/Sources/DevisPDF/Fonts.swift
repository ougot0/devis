import Foundation

/// Polices PDF standard (« base 14 ») : présentes dans tous les lecteurs PDF, sans embarquement.
/// Encodage WinAnsi : couvre le français (accents, œ, €, guillemets typographiques).
public enum StandardFont: String, Sendable, CaseIterable {
    case helvetica = "Helvetica"
    case helveticaBold = "Helvetica-Bold"
    case timesRoman = "Times-Roman"
    case timesBold = "Times-Bold"
    case timesItalic = "Times-Italic"
    case courier = "Courier"
    case courierBold = "Courier-Bold"

    var widths: [UInt16] {
        switch self {
        case .helvetica: return StandardFontMetrics.helvetica
        case .helveticaBold: return StandardFontMetrics.helveticaBold
        case .timesRoman: return StandardFontMetrics.timesRoman
        case .timesBold: return StandardFontMetrics.timesBold
        case .timesItalic: return StandardFontMetrics.timesItalic
        case .courier: return StandardFontMetrics.courier
        case .courierBold: return StandardFontMetrics.courierBold
        }
    }

    /// Hauteur des capitales / jambage, en em (approximation AFM).
    var ascent: Double {
        switch self {
        case .helvetica, .helveticaBold: return 0.718
        case .timesRoman, .timesBold, .timesItalic: return 0.683
        case .courier, .courierBold: return 0.629
        }
    }

    /// Largeur d'un texte, en points.
    public func width(of text: String, size: Double) -> Double {
        let table = widths
        var total = 0
        for byte in WinAnsi.encode(text) { total += Int(table[Int(byte)]) }
        return Double(total) * size / 1000
    }

    var resourceName: String {
        switch self {
        case .helvetica: return "F1"
        case .helveticaBold: return "F2"
        case .timesRoman: return "F3"
        case .timesBold: return "F4"
        case .timesItalic: return "F5"
        case .courier: return "F6"
        case .courierBold: return "F7"
        }
    }
}

/// Familles proposées à l'utilisateur pour personnaliser ses documents.
public enum FontPairing: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Linéale (Helvetica) : sobre et très lisible.
    case sans
    /// Romaine (Times) : classique, éditoriale.
    case serif
    /// Titres romains, texte linéal.
    case serifHeadings
    /// Titres et références à chasse fixe (Courier), texte linéal : aspect technique.
    case technical

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .sans: return "Linéale (Helvetica)"
        case .serif: return "Romaine (Times)"
        case .serifHeadings: return "Titres romains, texte linéal"
        case .technical: return "Technique (Courier + Helvetica)"
        }
    }

    var body: StandardFont { self == .serif ? .timesRoman : .helvetica }
    var bodyBold: StandardFont { self == .serif ? .timesBold : .helveticaBold }
    var heading: StandardFont {
        switch self {
        case .sans: return .helveticaBold
        case .serif, .serifHeadings: return .timesBold
        case .technical: return .courierBold
        }
    }
    var headingRegular: StandardFont {
        switch self {
        case .sans: return .helvetica
        case .serif, .serifHeadings: return .timesRoman
        case .technical: return .courier
        }
    }
    var italic: StandardFont { self == .sans || self == .technical ? .helvetica : .timesItalic }
    var mono: StandardFont { self == .technical ? .courier : body }
}

/// Encodage WinAnsi (proche de Windows-1252) utilisé par les polices standard.
public enum WinAnsi {
    private static let specials: [UInt32: UInt8] = [
        0x20AC: 0x80, 0x201A: 0x82, 0x0192: 0x83, 0x201E: 0x84, 0x2026: 0x85, 0x2020: 0x86,
        0x2021: 0x87, 0x02C6: 0x88, 0x2030: 0x89, 0x0160: 0x8A, 0x2039: 0x8B, 0x0152: 0x8C,
        0x017D: 0x8E, 0x2018: 0x91, 0x2019: 0x92, 0x201C: 0x93, 0x201D: 0x94, 0x2022: 0x95,
        0x2013: 0x96, 0x2014: 0x97, 0x02DC: 0x98, 0x2122: 0x99, 0x0161: 0x9A, 0x203A: 0x9B,
        0x0153: 0x9C, 0x017E: 0x9E, 0x0178: 0x9F,
        // Espaces insécables (formatage français des nombres) → espace insécable WinAnsi.
        0x202F: 0xA0, 0x2009: 0x20, 0x2007: 0xA0,
        // Signes courants hors WinAnsi : équivalents visuels.
        0x2212: 0x2D, 0x2010: 0x2D, 0x2011: 0x2D, 0x2032: 0x27, 0x2033: 0x22,
    ]

    /// Encode une chaîne ; les caractères non représentables deviennent « ? ».
    public static func encode(_ text: String) -> [UInt8] {
        var bytes: [UInt8] = []
        let normalized = text.precomposedStringWithCanonicalMapping
        bytes.reserveCapacity(normalized.unicodeScalars.count)
        for scalar in normalized.unicodeScalars {
            let value = scalar.value
            if value == 0x09 { bytes.append(0x20); continue }
            if value < 0x20 { continue }
            if value < 0x80 || (value >= 0xA0 && value <= 0xFF) {
                bytes.append(UInt8(value))
            } else if let mapped = specials[value] {
                bytes.append(mapped)
            } else if (0x0300...0x036F).contains(value) {
                continue // diacritique combinant isolé : ignoré (le texte est normalisé en amont)
            } else {
                bytes.append(0x3F)
            }
        }
        return bytes
    }

    /// Indique si un texte contient des caractères non imprimables avec les polices standard.
    public static func hasUnsupportedCharacters(_ text: String) -> Bool {
        let normalized = text.precomposedStringWithCanonicalMapping
        return normalized.unicodeScalars.contains { scalar in
            let value = scalar.value
            if value < 0x80 || (value >= 0xA0 && value <= 0xFF) { return false }
            return specials[value] == nil
        }
    }
}
