import Foundation

/// Style de texte.
public struct TextStyle: Sendable {
    public var font: StandardFont
    public var size: Double
    public var color: PDFColor
    /// Interligne, en multiple de la taille.
    public var leading: Double

    public init(font: StandardFont, size: Double, color: PDFColor = .black, leading: Double = 1.25) {
        self.font = font
        self.size = size
        self.color = color
        self.leading = leading
    }

    public var lineHeight: Double { size * leading }

    public func with(font: StandardFont? = nil, size: Double? = nil, color: PDFColor? = nil) -> TextStyle {
        TextStyle(font: font ?? self.font, size: size ?? self.size, color: color ?? self.color, leading: leading)
    }
}

public enum TextAlignment: Sendable {
    case left, right, center
}

/// Mise en forme du texte : césure aux espaces, coupure des mots trop longs, retours à la ligne.
public enum TextLayout {

    /// Découpe un texte en lignes tenant dans `width`.
    public static func wrap(_ text: String, style: TextStyle, width: Double) -> [String] {
        let maxWidth = max(width, style.size)
        var result: [String] = []
        let paragraphs = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        for paragraph in paragraphs {
            let words = paragraph.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            if words.isEmpty {
                result.append("")
                continue
            }
            var current = ""
            for word in words {
                let candidate = current.isEmpty ? word : current + " " + word
                if style.font.width(of: candidate, size: style.size) <= maxWidth {
                    current = candidate
                    continue
                }
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
                if style.font.width(of: word, size: style.size) <= maxWidth {
                    current = word
                } else {
                    // Mot plus long que la colonne (URL, IBAN, référence) : coupure au caractère.
                    var chunk = ""
                    for character in word {
                        let next = chunk + String(character)
                        if style.font.width(of: next, size: style.size) > maxWidth && !chunk.isEmpty {
                            result.append(chunk)
                            chunk = String(character)
                        } else {
                            chunk = next
                        }
                    }
                    current = chunk
                }
            }
            if !current.isEmpty { result.append(current) }
        }
        // Supprime les lignes vides finales.
        while let last = result.last, last.isEmpty, result.count > 1 { result.removeLast() }
        return result
    }

    /// Hauteur d'un texte mis en forme.
    public static func height(_ text: String, style: TextStyle, width: Double) -> Double {
        guard !text.isEmpty else { return 0 }
        return Double(wrap(text, style: style, width: width).count) * style.lineHeight
    }

    /// Tronque un texte sur une ligne avec « … » s'il dépasse.
    public static func truncate(_ text: String, style: TextStyle, width: Double) -> String {
        if style.font.width(of: text, size: style.size) <= width { return text }
        var characters = Array(text)
        while !characters.isEmpty && style.font.width(of: String(characters) + "…", size: style.size) > width {
            characters.removeLast()
        }
        return String(characters) + "…"
    }

    /// Plus grande taille (≥ `minimum`) pour laquelle le texte tient sur une ligne.
    public static func fittingSize(_ text: String, style: TextStyle, width: Double, minimum: Double = 6) -> Double {
        var size = style.size
        while size > minimum && style.font.width(of: text, size: size) > width { size -= 0.25 }
        return size
    }
}

extension PDFPage {
    /// Texte aligné dans une boîte de largeur `width` ; réduit la taille si nécessaire pour tenir.
    func text(_ string: String, x: Double, baseline: Double, width: Double, style: TextStyle, alignment: TextAlignment, shrinkToFit: Bool = false) {
        var size = style.size
        var string = string
        if shrinkToFit {
            size = TextLayout.fittingSize(string, style: style, width: width)
            if style.font.width(of: string, size: size) > width {
                string = TextLayout.truncate(string, style: style.with(size: size), width: width)
            }
        }
        let textWidth = style.font.width(of: string, size: size)
        let originX: Double
        switch alignment {
        case .left: originX = x
        case .right: originX = x + width - textWidth
        case .center: originX = x + (width - textWidth) / 2
        }
        text(string, x: originX, baseline: baseline, font: style.font, size: size, color: style.color)
    }

    /// Dessine des lignes déjà découpées à partir du haut `top`. Retourne la hauteur utilisée.
    @discardableResult
    func lines(_ lines: [String], x: Double, top: Double, width: Double, style: TextStyle, alignment: TextAlignment = .left) -> Double {
        var baseline = top + style.size * style.font.ascent + (style.lineHeight - style.size) / 2
        for line in lines {
            text(line, x: x, baseline: baseline, width: width, style: style, alignment: alignment)
            baseline += style.lineHeight
        }
        return Double(lines.count) * style.lineHeight
    }

    /// Met en forme et dessine un paragraphe. Retourne la hauteur utilisée.
    @discardableResult
    func paragraph(_ text: String, x: Double, top: Double, width: Double, style: TextStyle, alignment: TextAlignment = .left) -> Double {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return 0 }
        return lines(TextLayout.wrap(text, style: style, width: width), x: x, top: top, width: width, style: style, alignment: alignment)
    }
}
