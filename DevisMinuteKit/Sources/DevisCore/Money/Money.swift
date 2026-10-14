import Foundation

/// Règles d'arrondi financières de DevisMinute.
///
/// Tous les montants sont des `Decimal` (base 10) : aucun `Double` n'intervient
/// dans un calcul financier, ce qui évite les erreurs de représentation binaire
/// (0,1 + 0,2 = 0,30000000000000004).
///
/// Règles appliquées (documentées dans docs/CALCULS.md) :
/// - **R1** — Prix unitaires : saisis avec au plus 4 décimales (`unitPriceScale`).
/// - **R2** — Montant HT de chaque ligne : quantité × prix unitaire − remise de ligne,
///   arrondi au centime, au demi supérieur (« arrondi commercial », 0,005 → 0,01).
/// - **R3** — Remise globale : calculée sur le sous-total HT, arrondie au centime,
///   puis répartie entre les taux de TVA au prorata des bases (méthode du plus fort reste)
///   pour que la somme des bases soit exactement le total HT.
/// - **R4** — TVA : calculée **par taux**, sur la base HT totale de ce taux, arrondie au centime.
/// - **R5** — TTC = total HT + total TVA (jamais recalculé ligne par ligne).
/// - Les montants négatifs sont arrondis symétriquement (au demi « loin de zéro »).
public enum Money {
    /// Nombre de décimales des montants (centimes).
    public static let scale = 2
    /// Nombre de décimales maximal d'un prix unitaire ou d'une quantité.
    public static let unitPriceScale = 4

    /// Arrondit au centime, demi loin de zéro (0,005 → 0,01 ; −0,005 → −0,01).
    public static func round(_ value: Decimal, scale: Int = Money.scale) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, scale, .plain)
        return result
    }

    /// Analyse une saisie utilisateur (« 1 234,56 », « 1234.56 », « 12,5 € »).
    /// Retourne `nil` si la chaîne n'est pas un nombre valide.
    public static func parse(_ text: String) -> Decimal? {
        var cleaned = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "0"..."9", "-": cleaned.unicodeScalars.append(scalar)
            case ",", ".": cleaned.append(".")
            case " ", "\u{00A0}", "\u{202F}", "€", "%": continue
            default: return nil
            }
        }
        guard !cleaned.isEmpty else { return nil }
        // Une seule virgule décimale autorisée.
        guard cleaned.filter({ $0 == "." }).count <= 1 else { return nil }
        guard cleaned.dropFirst().contains("-") == false else { return nil }
        if cleaned == "-" || cleaned == "." || cleaned == "-." { return nil }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Valeur fixe à `scale` décimales, en notation « 1234.50 » (pour CSV, XML, empreintes).
    public static func plainString(_ value: Decimal, scale: Int = Money.scale) -> String {
        let rounded = Money.round(value, scale: scale)
        let negative = rounded < 0
        let absolute = negative ? -rounded : rounded
        var integerPart = Decimal()
        var copy = absolute
        NSDecimalRound(&integerPart, &copy, 0, .down)
        let fraction = absolute - integerPart
        var fractionDigits = ""
        if scale > 0 {
            var scaled = fraction
            for _ in 0..<scale { scaled *= 10 }
            let fractionInt = NSDecimalNumber(decimal: Money.round(scaled, scale: 0)).intValue
            fractionDigits = String(fractionInt)
            while fractionDigits.count < scale { fractionDigits = "0" + fractionDigits }
        }
        let integerString = NSDecimalNumber(decimal: integerPart).stringValue
        let body = scale > 0 ? "\(integerString).\(fractionDigits)" : integerString
        return negative && rounded != 0 ? "-" + body : body
    }

    /// Format français : « 1 234,56 € » (espace fine insécable comme séparateur de milliers).
    public static func format(_ value: Decimal, currencySymbol: String = "€", scale: Int = Money.scale) -> String {
        let plain = plainString(value, scale: scale)
        let negative = plain.hasPrefix("-")
        let digits = negative ? String(plain.dropFirst()) : plain
        let parts = digits.split(separator: ".", omittingEmptySubsequences: false)
        let integer = String(parts[0])
        var grouped = ""
        for (index, character) in integer.reversed().enumerated() {
            if index > 0 && index % 3 == 0 { grouped.append("\u{202F}") }
            grouped.append(character)
        }
        grouped = String(grouped.reversed())
        var result = (negative ? "-" : "") + grouped
        if parts.count > 1 { result += "," + parts[1] }
        if !currencySymbol.isEmpty { result += "\u{00A0}" + currencySymbol }
        return result
    }

    /// Format d'une quantité ou d'un taux : supprime les zéros inutiles (« 1,5 », « 20 », « 5,5 »).
    public static func formatQuantity(_ value: Decimal, maxScale: Int = Money.unitPriceScale) -> String {
        var plain = plainString(value, scale: maxScale)
        if plain.contains(".") {
            while plain.hasSuffix("0") { plain.removeLast() }
            if plain.hasSuffix(".") { plain.removeLast() }
        }
        return plain.replacingOccurrences(of: ".", with: ",")
    }

    /// Répartit `total` entre des poids, au centime, méthode du plus fort reste.
    /// La somme des parts est exactement `Money.round(total)`.
    public static func allocate(_ total: Decimal, weights: [Decimal]) -> [Decimal] {
        guard !weights.isEmpty else { return [] }
        let target = Money.round(total)
        let weightSum = weights.reduce(Decimal(0), +)
        guard weightSum != 0 else {
            var parts = Array(repeating: Decimal(0), count: weights.count)
            parts[0] = target
            return parts
        }
        var parts: [Decimal] = []
        var remainders: [(index: Int, remainder: Decimal)] = []
        for (index, weight) in weights.enumerated() {
            let exact = target * weight / weightSum
            var input = exact
            var truncated = Decimal()
            NSDecimalRound(&truncated, &input, scale, target >= 0 ? .down : .up)
            parts.append(truncated)
            remainders.append((index, abs(exact - truncated)))
        }
        var difference = target - parts.reduce(Decimal(0), +)
        let cent = Decimal(sign: target >= 0 ? .plus : .minus, exponent: -scale, significand: 1)
        let order = remainders.sorted { lhs, rhs in
            lhs.remainder == rhs.remainder ? lhs.index < rhs.index : lhs.remainder > rhs.remainder
        }
        var cursor = 0
        while difference != 0 && !order.isEmpty {
            parts[order[cursor % order.count].index] += cent
            difference -= cent
            cursor += 1
        }
        return parts
    }
}

extension Decimal {
    /// Raccourci lisible pour les littéraux décimaux exacts : `"19.99".dec`.
    /// À n'utiliser qu'avec des constantes (plante si la chaîne est invalide).
    public static func exact(_ string: String) -> Decimal {
        guard let value = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) else {
            preconditionFailure("Littéral décimal invalide : \(string)")
        }
        return value
    }
}
