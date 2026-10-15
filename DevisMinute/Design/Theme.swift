import SwiftUI
import DevisCore

/// Direction artistique DevisMinute : fond ivoire, texte anthracite, bleu pétrole,
/// une couleur secondaire (ocre) réservée aux actions importantes.
/// Cartes à grands coins arrondis sur l'accueil, pastilles d'état teintées, pas d'ombres portées.
enum Theme {
    static let ivory = Color("Ivory")
    static let ink = Color("Ink")
    static let petrol = Color("Petrol")
    static let neutral = Color("Neutral")
    static let ochre = Color("Ochre")
    static let hairline = Color("Hairline")
    static let surface = Color("Surface")
    static let danger = Color(red: 0.62, green: 0.23, blue: 0.16)
    static let success = Color(red: 0.18, green: 0.42, blue: 0.33)

    /// Espacements (grille de 4 points).
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }
}

extension Font {
    /// Montants : chiffres tabulaires pour l'alignement des colonnes.
    static func amount(_ style: Font.TextStyle = .body, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .default, weight: weight).monospacedDigit()
    }

    /// Titre de section discret en petites capitales.
    static let sectionLabel = Font.system(.caption, design: .default, weight: .semibold)
}

/// Étiquette de section : petites capitales grises, sans fond.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.sectionLabel)
            .tracking(0.6)
            .foregroundStyle(Theme.neutral)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Pastille d'état textuelle (couleur + libellé : jamais la couleur seule).
struct StatusBadge: View {
    let text: String
    let tone: Tone

    enum Tone { case neutral, info, success, warning, danger }

    var color: Color {
        switch tone {
        case .neutral: return Theme.neutral
        case .info: return Theme.petrol
        case .success: return Theme.success
        case .warning: return Theme.ochre
        case .danger: return Theme.danger
        }
    }

    var symbol: String {
        switch tone {
        case .neutral: return "circle.dashed"
        case .info: return "clock"
        case .success: return "checkmark"
        case .warning: return "hourglass"
        case .danger: return "exclamationmark"
        }
    }

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold))
        }
        .labelStyle(BadgeLabelStyle())
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.13), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("État : \(text)")
    }
}

private struct BadgeLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}

/// Montant formaté en euros.
struct AmountText: View {
    let value: Decimal
    var style: Font.TextStyle = .body
    var weight: Font.Weight = .semibold

    var body: some View {
        Text(Money.format(value))
            .font(.amount(style, weight: weight))
            .accessibilityLabel(Money.format(value).replacingOccurrences(of: "\u{202F}", with: " "))
    }
}

/// Bouton principal : aplat pétrole, coins légèrement arrondis.
struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.petrol

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(tint.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Bouton secondaire : contour fin.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(Theme.petrol)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.petrol.opacity(configuration.isPressed ? 0.4 : 0.8), lineWidth: 1))
    }
}

/// Carte de l'accueil : surface claire, grands coins arrondis, fin liseré.
struct CardModifier: ViewModifier {
    var fill: Color = Theme.surface

    func body(content: Content) -> some View {
        content
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.hairline.opacity(fill == Theme.surface ? 1 : 0), lineWidth: 1))
    }
}

extension View {
    func card(fill: Color = Theme.surface) -> some View { modifier(CardModifier(fill: fill)) }

    /// Fond ivoire de l'application.
    func appBackground() -> some View {
        scrollContentBackground(.hidden).background(Theme.ivory)
    }
}
