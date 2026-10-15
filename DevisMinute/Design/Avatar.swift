import SwiftUI

/// Pastille ronde avec les initiales, comme dans Contacts. La couleur est stable pour un même nom.
struct InitialsAvatar: View {
    let name: String
    var size: CGFloat = 36

    /// Teintes sourdes, accordées au pétrole et à l'ocre de l'application.
    static let palette: [Color] = [
        Color(red: 0.14, green: 0.35, blue: 0.39),
        Color(red: 0.71, green: 0.47, blue: 0.20),
        Color(red: 0.36, green: 0.42, blue: 0.62),
        Color(red: 0.55, green: 0.32, blue: 0.40),
        Color(red: 0.27, green: 0.49, blue: 0.38),
        Color(red: 0.60, green: 0.36, blue: 0.24),
        Color(red: 0.42, green: 0.36, blue: 0.56),
        Color(red: 0.33, green: 0.45, blue: 0.48),
    ]

    static func initials(of name: String) -> String {
        let words = name.split { !$0.isLetter && !$0.isNumber }.filter { !$0.isEmpty }
        let ignored: Set<String> = ["sarl", "sas", "sasu", "eurl", "sa", "sci", "ei", "le", "la", "les", "de", "des", "du", "et"]
        let meaningful = words.filter { !ignored.contains($0.lowercased()) }
        let source = meaningful.isEmpty ? words : meaningful
        let letters = source.prefix(2).compactMap(\.first).map { String($0).uppercased() }
        return letters.isEmpty ? "?" : letters.joined()
    }

    /// Hachage déterministe (le `hashValue` de Swift change à chaque lancement).
    static func color(for name: String) -> Color {
        var hash: UInt32 = 5381
        for byte in name.lowercased().utf8 { hash = (hash &* 33) &+ UInt32(byte) }
        return palette[Int(hash % UInt32(palette.count))]
    }

    var body: some View {
        let color = Self.color(for: name)
        Text(Self.initials(of: name))
            .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.16), in: Circle())
            .accessibilityHidden(true)
    }
}
