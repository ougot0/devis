import Foundation
import DevisCore

/// Génère le PDF d'un devis, d'une facture ou d'un avoir, entièrement sur l'appareil.
///
/// Mise en page multipage : en-tête de tableau répété, lignes trop longues découpées
/// entre deux pages, bloc des totaux jamais coupé, pied de page « page x / n » sur chaque page.
public enum DocumentPDFRenderer {

    public static func render(_ request: RenderRequest, deflate: ((Data) -> Data?)? = nil) -> RenderResult {
        let session = RenderSession(request: request)
        session.builder.deflate = deflate
        session.run()
        let document = request.document
        let title = "\(document.kind.title) \(document.number.isEmpty ? "brouillon" : document.number)"
        let metadata = PDFMetadata(
            title: title,
            author: document.seller.displayName,
            subject: "\(title) — \(document.customer.name)",
            keywords: [document.kind.title, document.number, document.customer.name].filter { !$0.isEmpty }.joined(separator: ", "),
            creationDate: request.generatedAt
        )
        return RenderResult(data: session.builder.build(metadata: metadata), pageCount: session.builder.pages.count, warnings: session.warnings)
    }

    /// Nom de fichier conseillé : « Facture F-2026-0001 - Client.pdf ».
    public static func suggestedFileName(for document: BusinessDocument) -> String {
        let number = document.number.isEmpty ? "brouillon" : document.number
        var name = "\(document.kind.title) \(number)"
        if !document.customer.name.trimmed.isEmpty { name += " - \(document.customer.name.trimmed)" }
        let forbidden = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = name.unicodeScalars.map { forbidden.contains($0) ? "-" : String($0) }.joined()
        return String(cleaned.prefix(120)) + ".pdf"
    }
}

// MARK: - Session de rendu

final class RenderSession {
    let request: RenderRequest
    let document: BusinessDocument
    let totals: DocumentTotals
    /// Modèle de base (tableau, totaux, marges, pied de page).
    let template: DocumentTemplate
    /// Modèle choisi (en-tête et décor propres aux variantes).
    let style: DocumentTemplate
    let fonts: FontPairing
    let accent: PDFColor
    let builder = PDFDocumentBuilder()
    var warnings: [String] = []

    // Palette neutre (direction artistique DevisMinute).
    let ink = PDFColor(hex: "#252A2B")!
    let muted = PDFColor(hex: "#6E7371")!
    let hairline = PDFColor(hex: "#D5D2CA")!
    let wash = PDFColor(hex: "#F3F1EC")!

    let pageWidth = PDFDocumentBuilder.a4Width
    let pageHeight = PDFDocumentBuilder.a4Height
    var marginLeft: Double
    var marginRight: Double
    let marginTop: Double = 40
    let footerHeight: Double = 50

    var page: PDFPage!
    var y: Double = 0
    var logo: Int?
    var logoImage: PDFImage?

    init(request: RenderRequest) {
        self.request = request
        self.document = request.document
        self.totals = DocumentCalculator.totals(for: request.document)
        self.template = request.appearance.template.layout
        self.style = request.appearance.template
        self.fonts = request.appearance.fontPairing
        self.accent = request.appearance.accentColor
        switch template {
        case .creatif: marginLeft = 64; marginRight = 44
        case .minimal: marginLeft = 56; marginRight = 56
        case .elegant: marginLeft = 54; marginRight = 54
        case .technique: marginLeft = 36; marginRight = 36
        default: marginLeft = 44; marginRight = 44
        }
    }

    var contentWidth: Double { pageWidth - marginLeft - marginRight }
    var right: Double { pageWidth - marginRight }
    var bottomLimit: Double { pageHeight - footerHeight - 12 }

    // MARK: Styles

    var bodySize: Double { template == .technique ? 8 : (template == .minimal ? 8.5 : 9) }
    var body: TextStyle { TextStyle(font: fonts.body, size: bodySize, color: ink) }
    var bodyBold: TextStyle { TextStyle(font: fonts.bodyBold, size: bodySize, color: ink) }
    var small: TextStyle { TextStyle(font: fonts.body, size: bodySize - 1.5, color: muted) }
    var label: TextStyle { TextStyle(font: fonts.bodyBold, size: 6.8, color: muted) }
    var accentOnFill: PDFColor { accent.luminance > 0.45 ? ink : .white }

    // MARK: Déroulé

    func run() {
        prepareLogo()
        checkCharacters()
        newPage(first: true)
        drawFirstPageHeader()
        if request.isDraft { drawDraftBanner() }
        drawSubject()
        drawTable()
        drawTotals()
        drawClosingBlocks()
        drawPhotos()
        drawFooters()
    }

    private func prepareLogo() {
        guard request.appearance.showLogo, let data = request.logoJPEG else { return }
        if let image = PDFImage(jpegData: data) {
            logo = builder.register(image: image)
            logoImage = image
        } else {
            warnings.append("Le logo n'a pas pu être lu (format JPEG attendu) ; il n'est pas imprimé.")
        }
    }

    private func checkCharacters() {
        var texts = [document.customer.name, document.title, document.notes, document.specialConditions, document.seller.displayName]
        for line in document.lines { texts.append(line.designation); texts.append(line.details) }
        if texts.contains(where: WinAnsi.hasUnsupportedCharacters) {
            warnings.append("Certains caractères (emoji, alphabets non latins) ne peuvent pas être imprimés et sont remplacés par « ? ».")
        }
    }

    func newPage(first: Bool) {
        page = builder.newPage()
        y = marginTop
        if template == .creatif {
            page.fillRect(x: 0, y: 0, width: 18, height: pageHeight, color: accent)
        }
        if template == .corporate && !first {
            page.fillRect(x: 0, y: 0, width: pageWidth, height: 6, color: accent)
        }
        if style == .chantier { drawHazardStripe(y: 0) }
        if style == .prestige && !first { page.fillRect(x: 0, y: 0, width: pageWidth, height: 8, color: ink) }
        if style == .nature && !first { page.fillRect(x: 0, y: 0, width: pageWidth, height: 5, color: accent) }
        if !first { drawContinuationHeader() }
    }

    /// Garantit `height` points disponibles ; sinon passe à la page suivante.
    /// Retourne `true` si une nouvelle page a été créée.
    @discardableResult
    func ensureSpace(_ height: Double) -> Bool {
        if y + height <= bottomLimit { return false }
        newPage(first: false)
        return true
    }

    // MARK: Données communes

    var titleText: String {
        switch document.kind {
        case .quote: return "Devis"
        case .invoice: return "Facture"
        case .depositInvoice: return "Facture d'acompte"
        case .creditNote: return "Avoir"
        }
    }

    var numberText: String { document.number.isEmpty ? "Brouillon" : document.number }

    func sellerLines() -> [String] {
        let seller = document.seller
        var lines: [String] = []
        if seller.legalIdentity != seller.displayName && !seller.legalIdentity.isEmpty { lines.append(seller.legalIdentity) }
        lines.append(contentsOf: seller.address.lines)
        if !seller.phone.trimmed.isEmpty { lines.append("Tél. \(seller.phone.trimmed)") }
        if !seller.email.trimmed.isEmpty { lines.append(seller.email.trimmed) }
        if !seller.website.trimmed.isEmpty { lines.append(seller.website.trimmed) }
        if !seller.siret.trimmed.isEmpty {
            lines.append("SIRET \(LegalMentionsBuilder.formatSiret(seller.siret))")
        } else if !seller.siren.trimmed.isEmpty {
            lines.append("SIREN \(LegalMentionsBuilder.formatSiren(seller.siren))")
        }
        if seller.isVATRegistered && !seller.vatNumber.trimmed.isEmpty { lines.append("TVA \(seller.vatNumber.trimmed)") }
        return lines
    }

    func customerLines() -> [String] {
        let customer = document.customer
        var lines: [String] = []
        if !customer.contactName.trimmed.isEmpty { lines.append("À l'attention de \(customer.contactName.trimmed)") }
        lines.append(contentsOf: customer.address.lines)
        if !customer.siren.trimmed.isEmpty { lines.append("SIREN \(LegalMentionsBuilder.formatSiren(customer.siren))") }
        if !customer.vatNumber.trimmed.isEmpty { lines.append("TVA \(customer.vatNumber.trimmed)") }
        if let delivery = customer.deliveryAddress, !delivery.isEmpty {
            lines.append("Livraison : " + delivery.lines.joined(separator: ", "))
        }
        return lines
    }

    func metaRows() -> [(String, String)] {
        var rows: [(String, String)] = [("N°", numberText), ("Date", DateFormatting.short(document.issueDate))]
        switch document.kind {
        case .quote:
            if let valid = document.validUntil { rows.append(("Valable jusqu'au", DateFormatting.short(valid))) }
        case .invoice, .depositInvoice:
            if let service = document.serviceDate { rows.append(("Date de prestation", DateFormatting.short(service))) }
            if let due = document.dueDate { rows.append(("Échéance", DateFormatting.short(due))) }
            if !document.sourceQuoteNumber.isEmpty { rows.append(("Devis", document.sourceQuoteNumber)) }
        case .creditNote:
            if !document.correctedInvoiceNumber.isEmpty { rows.append(("Facture d'origine", document.correctedInvoiceNumber)) }
        }
        if !document.purchaseOrderReference.trimmed.isEmpty { rows.append(("Réf. commande", document.purchaseOrderReference.trimmed)) }
        if document.kind != .quote { rows.append(("Opération", document.operationNatureLabel)) }
        return rows
    }

    /// Dessine le logo dans la boîte donnée (proportions conservées). Retourne la taille réelle.
    @discardableResult
    func drawLogo(x: Double, y top: Double, maxWidth: Double, maxHeight: Double, alignment: TextAlignment = .left) -> (width: Double, height: Double) {
        guard let logo, let image = logoImage else { return (0, 0) }
        let ratio = Double(image.pixelWidth) / Double(image.pixelHeight)
        var width = maxWidth
        var height = width / ratio
        if height > maxHeight {
            height = maxHeight
            width = height * ratio
        }
        let originX: Double
        switch alignment {
        case .left: originX = x
        case .right: originX = x + maxWidth - width
        case .center: originX = x + (maxWidth - width) / 2
        }
        page.image(logo, x: originX, y: top, width: width, height: height)
        return (width, height)
    }

    /// Bloc libellé + lignes ; retourne la hauteur.
    @discardableResult
    func drawPartyBlock(caption: String, name: String, lines: [String], x: Double, top: Double, width: Double, captionStyle: TextStyle? = nil, nameStyle: TextStyle? = nil) -> Double {
        var cursor = top
        if !caption.isEmpty {
            let style = captionStyle ?? label
            page.text(caption.uppercased(), x: x, baseline: cursor + style.size, font: style.font, size: style.size, color: style.color)
            cursor += style.size + 5
        }
        let nameStyle = nameStyle ?? bodyBold.with(size: bodySize + 1.5)
        cursor += page.paragraph(name, x: x, top: cursor, width: width, style: nameStyle)
        cursor += 1
        let detailStyle = body.with(color: ink)
        for line in lines {
            cursor += page.paragraph(line, x: x, top: cursor, width: width, style: detailStyle)
        }
        return cursor - top
    }

    func partyHeight(caption: String, name: String, lines: [String], width: Double) -> Double {
        var height = caption.isEmpty ? 0 : label.size + 5
        height += TextLayout.height(name, style: bodyBold.with(size: bodySize + 1.5), width: width) + 1
        for line in lines { height += TextLayout.height(line, style: body, width: width) }
        return height
    }

    /// Tableau de métadonnées libellé / valeur aligné à droite.
    @discardableResult
    func drawMeta(x: Double, top: Double, width: Double, labelStyle: TextStyle? = nil, valueStyle: TextStyle? = nil, rowHeight: Double = 12) -> Double {
        let labelStyle = labelStyle ?? small
        let valueStyle = valueStyle ?? bodyBold
        var cursor = top
        for (key, value) in metaRows() {
            page.text(key, x: x, baseline: cursor + 9, width: width * 0.45, style: labelStyle, alignment: .left)
            page.text(value, x: x + width * 0.45, baseline: cursor + 9, width: width * 0.55, style: valueStyle, alignment: .right, shrinkToFit: true)
            cursor += rowHeight
        }
        return cursor - top
    }

    func drawDraftBanner() {
        let height = 18.0
        ensureSpace(height + 8)
        page.fillRect(x: marginLeft, y: y, width: contentWidth, height: height, color: PDFColor(hex: "#F6E3DE")!)
        page.text("BROUILLON — document non émis, sans valeur comptable ni numéro définitif", x: marginLeft, baseline: y + 12, width: contentWidth, style: bodyBold.with(size: 8, color: PDFColor(hex: "#9A3B2A")!), alignment: .center)
        y += height + 10
    }

    func drawSubject() {
        let subject = document.title.trimmed
        guard !subject.isEmpty else { return }
        let style = bodyBold.with(size: bodySize + 1)
        let height = TextLayout.height("Objet : " + subject, style: style, width: contentWidth)
        ensureSpace(height + 10)
        page.paragraph("Objet : " + subject, x: marginLeft, top: y, width: contentWidth, style: style)
        y += height + 10
    }

    func drawContinuationHeader() {
        let text = "\(titleText) \(numberText) — \(document.customer.name) (suite)"
        page.text(TextLayout.truncate(text, style: small, width: contentWidth), x: marginLeft, baseline: y + 8, font: small.font, size: small.size, color: muted)
        page.line(from: (marginLeft, y + 14), to: (right, y + 14), color: hairline)
        y += 24
    }

    // MARK: Pieds de page

    func drawFooters() {
        let count = builder.pages.count
        let legal = LegalMentionsBuilder.sellerLegalLine(document.seller)
        let style = TextStyle(font: fonts.body, size: 6.5, color: muted)
        for (index, footerPage) in builder.pages.enumerated() {
            let top = pageHeight - footerHeight + 6
            let pageLabel = count > 1 ? "Page \(index + 1) / \(count)" : ""
            let pageLabelWidth = pageLabel.isEmpty ? 0 : style.font.width(of: pageLabel, size: style.size) + 12
            let textWidth = contentWidth - pageLabelWidth
            var lines = TextLayout.wrap(legal, style: style, width: textWidth)
            if lines.count > 3 { lines = Array(lines.prefix(3)) }
            switch template {
            case .elegant, .creatif:
                footerPage.line(from: (marginLeft + contentWidth * 0.3, top - 4), to: (right - contentWidth * 0.3, top - 4), color: hairline)
                footerPage.lines(lines, x: marginLeft + pageLabelWidth / 2, top: top, width: textWidth, style: style, alignment: .center)
            case .minimal:
                footerPage.lines(lines, x: marginLeft, top: top, width: textWidth, style: style)
            case .corporate:
                footerPage.fillRect(x: 0, y: pageHeight - 6, width: pageWidth, height: 6, color: accent)
                footerPage.line(from: (marginLeft, top - 4), to: (right, top - 4), color: hairline)
                footerPage.lines(lines, x: marginLeft, top: top, width: textWidth, style: style)
            default:
                footerPage.line(from: (marginLeft, top - 4), to: (right, top - 4), color: hairline)
                footerPage.lines(lines, x: marginLeft, top: top, width: textWidth, style: style)
            }
            if !pageLabel.isEmpty {
                footerPage.text(pageLabel, x: right - pageLabelWidth, baseline: top + 7, width: pageLabelWidth, style: style, alignment: .right)
            }
        }
    }
}
