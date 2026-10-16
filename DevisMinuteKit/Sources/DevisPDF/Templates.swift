import Foundation
import DevisCore

/// Les 14 modèles de documents. Chacun a sa propre composition d'en-tête ; les six derniers
/// reprennent le tableau et les totaux d'un modèle de base (`layout`).
/// Tous impriment les mêmes mentions obligatoires.
public enum DocumentTemplate: String, Codable, Sendable, CaseIterable, Identifiable {
    case classique
    case corporate
    case minimal
    case artisan
    case creatif
    case elegant
    case technique
    case moderne
    case nature
    case prestige
    case chantier
    case pastel
    case ardoise
    case compact

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .classique: return "Classique"
        case .corporate: return "Corporate"
        case .minimal: return "Minimal"
        case .artisan: return "Artisan"
        case .creatif: return "Créatif"
        case .elegant: return "Élégant"
        case .technique: return "Technique"
        case .moderne: return "Moderne"
        case .nature: return "Nature"
        case .prestige: return "Prestige"
        case .chantier: return "Chantier"
        case .pastel: return "Pastel"
        case .ardoise: return "Ardoise"
        case .compact: return "Compact"
        }
    }

    public var summary: String {
        switch self {
        case .classique: return "Sobre et universel. Logo à gauche, références à droite, tableau à filets fins."
        case .corporate: return "Bandeau de couleur, tableau à en-tête plein, encadré des totaux. Entreprises et consultants."
        case .minimal: return "Très épuré : aucune couleur de fond, quatre colonnes, beaucoup d'air."
        case .artisan: return "En-tête encadré, tableau quadrillé avec unités, zone « Bon pour accord » marquée. Bâtiment et métiers manuels."
        case .creatif: return "Grand titre, bande verticale de couleur, total mis en avant. Designers et freelances."
        case .elegant: return "Composition centrée, romaine, doubles filets. Services premium."
        case .technique: return "Dense et précis : lignes numérotées, sous-totaux par section, récapitulatif de TVA détaillé."
        case .moderne: return "Encart de synthèse en tête, blocs teintés, en-têtes de colonnes en petites capitales."
        case .nature: return "Vert tilleul, titres romains, encart client teinté. Paysagistes, bien-être, commerces de proximité."
        case .prestige: return "Bandeau sombre pleine largeur, titre doré centré. Architectes, conseil, événementiel."
        case .chantier: return "Bande de signalisation, titre en bloc noir, tableau quadrillé. BTP, plomberie, électricité."
        case .pastel: return "Grand encart pastel avec le total à payer, mise en page aérée. Photographes, coachs, créateurs."
        case .ardoise: return "Colonne ardoise pour l'émetteur, références alignées à droite. Agences et indépendants."
        case .compact: return "Tout tient sur une page : en-tête sur deux lignes, petite typographie. Dépannage, livraisons."
        }
    }

    public var defaultAccentHex: String {
        switch self {
        case .classique: return "#245A64"
        case .corporate: return "#1F3A5F"
        case .minimal: return "#252A2B"
        case .artisan: return "#8A4B2A"
        case .creatif: return "#C2492F"
        case .elegant: return "#6B5B3E"
        case .technique: return "#245A64"
        case .moderne: return "#2E6B5E"
        case .nature: return "#4E7A3A"
        case .prestige: return "#A67C2E"
        case .chantier: return "#D9661F"
        case .pastel: return "#8A6FB0"
        case .ardoise: return "#3B4A54"
        case .compact: return "#245A64"
        }
    }

    public var defaultFontPairing: FontPairing {
        switch self {
        case .classique, .corporate, .minimal, .artisan, .moderne, .chantier, .ardoise, .compact: return .sans
        case .creatif, .nature, .pastel: return .serifHeadings
        case .elegant, .prestige: return .serif
        case .technique: return .technical
        }
    }

    /// Modèle de base dont sont repris le tableau, les totaux, les marges et le pied de page.
    public var layout: DocumentTemplate {
        switch self {
        case .nature: return .moderne
        case .prestige: return .elegant
        case .chantier: return .artisan
        case .pastel: return .minimal
        case .ardoise: return .classique
        case .compact: return .technique
        default: return self
        }
    }
}

/// Personnalisation des documents choisie par l'utilisateur.
public struct DocumentAppearance: Codable, Sendable, Equatable {
    public var template: DocumentTemplate
    public var accentHex: String
    public var fontPairing: FontPairing
    public var showBankDetails: Bool
    /// Zone « Bon pour accord » sur les devis.
    public var showSignatureBlock: Bool
    public var showLogo: Bool

    public init(template: DocumentTemplate = .classique, accentHex: String? = nil, fontPairing: FontPairing? = nil, showBankDetails: Bool = true, showSignatureBlock: Bool = true, showLogo: Bool = true) {
        self.template = template
        self.accentHex = accentHex ?? template.defaultAccentHex
        self.fontPairing = fontPairing ?? template.defaultFontPairing
        self.showBankDetails = showBankDetails
        self.showSignatureBlock = showSignatureBlock
        self.showLogo = showLogo
    }

    public var accentColor: PDFColor { PDFColor(hex: accentHex) ?? PDFColor(hex: template.defaultAccentHex)! }
}

/// Situation de règlement imprimée sur une facture (facultatif).
public struct PaymentSummary: Sendable, Equatable {
    public var paid: Decimal
    public var credited: Decimal
    public var balance: Decimal

    public init(paid: Decimal, credited: Decimal = 0, balance: Decimal) {
        self.paid = paid
        self.credited = credited
        self.balance = balance
    }
}

/// Demande de rendu PDF.
public struct RenderRequest: Sendable {
    public var document: BusinessDocument
    public var appearance: DocumentAppearance
    /// Logo au format JPEG (l'application convertit les PNG en JPEG sur fond blanc).
    public var logoJPEG: Data?
    public var payment: PaymentSummary?
    /// Document non émis : un bandeau « Brouillon » est imprimé.
    public var isDraft: Bool
    /// QR code du lien de paiement (`document.paymentLink`), en JPEG, généré par l'application.
    public var paymentQRCodeJPEG: Data?
    /// Signature du client : imprimée dans la zone « Bon pour accord » d'un devis.
    public var signature: QuoteSignature?
    public var generatedAt: Date

    public init(document: BusinessDocument, appearance: DocumentAppearance, logoJPEG: Data? = nil, payment: PaymentSummary? = nil, isDraft: Bool = false, generatedAt: Date = Date(), paymentQRCodeJPEG: Data? = nil, signature: QuoteSignature? = nil) {
        self.paymentQRCodeJPEG = paymentQRCodeJPEG
        self.signature = signature
        self.document = document
        self.appearance = appearance
        self.logoJPEG = logoJPEG
        self.payment = payment
        self.isDraft = isDraft
        self.generatedAt = generatedAt
    }
}

public struct RenderResult: Sendable {
    public var data: Data
    public var pageCount: Int
    /// Avertissements (caractères non imprimables, logo illisible…).
    public var warnings: [String]
}
