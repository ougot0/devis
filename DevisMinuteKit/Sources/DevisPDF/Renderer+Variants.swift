import Foundation
import DevisCore

/// En-têtes des six modèles « variantes » (le reste de la page suit leur modèle de base).
extension RenderSession {

    /// Montant mis en avant : total TTC (devis, avoir) ou net à payer (facture).
    private var highlightedAmount: (label: String, value: Decimal) {
        switch document.kind {
        case .quote: return (document.chargesVAT ? "TOTAL TTC" : "TOTAL", totals.totalTTC)
        case .creditNote: return ("MONTANT DE L'AVOIR", totals.totalTTC)
        default: return ("NET À PAYER", request.payment?.balance ?? totals.netToPay)
        }
    }

    private var keyDateLine: String {
        switch document.kind {
        case .quote: return document.validUntil.map { "Valable jusqu'au \(DateFormatting.short($0))" } ?? ""
        case .creditNote: return "Émis le \(DateFormatting.short(document.issueDate))"
        default: return document.dueDate.map { "À régler avant le \(DateFormatting.short($0))" } ?? ""
        }
    }

    private func referencesLine() -> String {
        metaRows().filter { $0.0 != "N°" }.map { "\($0.0) : \($0.1)" }.joined(separator: "   ·   ")
    }

    /// Bande de signalisation (modèle Chantier) : blocs alternés couleur / anthracite.
    func drawHazardStripe(y top: Double) {
        let height = 10.0
        let block = 22.0
        var x = 0.0
        var index = 0
        while x < pageWidth {
            page.fillRect(x: x, y: top, width: block, height: height, color: index.isMultiple(of: 2) ? accent : ink)
            x += block
            index += 1
        }
    }

    // 9. Nature — filet de couleur, nom en romaine, encart client teinté.
    func headerNature() {
        page.fillRect(x: 0, y: 0, width: pageWidth, height: 5, color: accent)
        let top = y
        let logoSize = drawLogo(x: marginLeft, y: top, maxWidth: 110, maxHeight: 44)
        var cursor = top + (logoSize.height > 0 ? logoSize.height + 8 : 0)
        cursor += page.paragraph(document.seller.displayName, x: marginLeft, top: cursor, width: contentWidth * 0.5, style: TextStyle(font: fonts.heading, size: 16, color: accent))
        page.text(titleText, x: marginLeft, baseline: top + 26, width: contentWidth, style: TextStyle(font: fonts.heading, size: 28, color: ink), alignment: .right)
        page.text("N° \(numberText)", x: marginLeft, baseline: top + 42, width: contentWidth, style: TextStyle(font: fonts.body, size: 10, color: accent), alignment: .right)
        page.text(keyDateLine, x: marginLeft, baseline: top + 56, width: contentWidth, style: small, alignment: .right)
        y = max(cursor, top + 62) + 8
        page.line(from: (marginLeft, y), to: (right, y), color: accent, lineWidth: 0.9)
        page.line(from: (marginLeft, y + 3), to: (right, y + 3), color: accent.tinted(0.6), lineWidth: 0.4)
        y += 16

        let gap = 18.0
        let columnWidth = (contentWidth - gap) / 2
        let sellerHeight = drawPartyBlock(caption: "Émetteur", name: document.seller.displayName, lines: sellerLines(), x: marginLeft, top: y + 10, width: columnWidth, captionStyle: TextStyle(font: fonts.bodyBold, size: 7, color: accent))
        let padding = 12.0
        let customerX = marginLeft + columnWidth + gap
        let customerHeight = partyHeight(caption: "Client", name: document.customer.name, lines: customerLines(), width: columnWidth - 2 * padding) + 2 * padding
        page.fillRect(x: customerX, y: y, width: columnWidth, height: customerHeight, color: accent.tinted(0.9))
        drawPartyBlock(caption: "Client", name: document.customer.name, lines: customerLines(), x: customerX + padding, top: y + padding, width: columnWidth - 2 * padding, captionStyle: TextStyle(font: fonts.bodyBold, size: 7, color: accent))
        y += max(sellerHeight + 10, customerHeight) + 12
        y += page.paragraph(referencesLine(), x: marginLeft, top: y, width: contentWidth, style: small)
        y += 16
    }

    // 10. Prestige — bandeau sombre pleine largeur, titre doré centré.
    func headerPrestige() {
        let band = 128.0
        page.fillRect(x: 0, y: 0, width: pageWidth, height: band, color: ink)
        page.fillRect(x: 0, y: band, width: pageWidth, height: 3, color: accent)
        if logo != nil {
            page.fillRect(x: marginLeft, y: 24, width: 62, height: 52, color: .white)
            drawLogo(x: marginLeft + 4, y: 28, maxWidth: 54, maxHeight: 44, alignment: .center)
        }
        page.text(document.seller.displayName, x: marginLeft, baseline: 52, width: contentWidth, style: TextStyle(font: fonts.heading, size: 19, color: .white), alignment: .center, shrinkToFit: true)
        let contact = [document.seller.email.trimmed, document.seller.phone.trimmed, document.seller.website.trimmed].filter { !$0.isEmpty }.joined(separator: "   ·   ")
        if !contact.isEmpty {
            page.text(TextLayout.truncate(contact, style: small, width: contentWidth * 0.7), x: marginLeft, baseline: 68, width: contentWidth, style: TextStyle(font: fonts.body, size: 8, color: PDFColor(hex: "#C9C6BE")!), alignment: .center)
        }
        let spaced = titleText.uppercased().map(String.init).joined(separator: " ")
        page.text(spaced, x: marginLeft, baseline: 98, width: contentWidth, style: TextStyle(font: fonts.heading, size: 13, color: accent), alignment: .center, shrinkToFit: true)
        page.text("N° \(numberText)  —  \(DateFormatting.long(document.issueDate))", x: marginLeft, baseline: 114, width: contentWidth, style: TextStyle(font: fonts.body, size: 8.5, color: .white), alignment: .center)

        y = band + 26
        let gap = 30.0
        let columnWidth = (contentWidth - gap) / 2
        let captionStyle = TextStyle(font: fonts.bodyBold, size: 7, color: accent)
        let h1 = drawPartyBlock(caption: "Émetteur", name: document.seller.displayName, lines: sellerLines(), x: marginLeft, top: y, width: columnWidth, captionStyle: captionStyle)
        let h2 = drawPartyBlock(caption: "Client", name: document.customer.name, lines: customerLines(), x: marginLeft + columnWidth + gap, top: y, width: columnWidth, captionStyle: captionStyle)
        y += max(h1, h2) + 14
        page.line(from: (marginLeft, y), to: (right, y), color: accent, lineWidth: 0.5)
        y += 6
        y += page.paragraph(referencesLine(), x: marginLeft, top: y, width: contentWidth, style: small, alignment: .center)
        y += 18
    }

    // 11. Chantier — bande de signalisation, titre dans un bloc anthracite.
    func headerChantier() {
        let top = y
        let blockWidth = contentWidth * 0.42
        let blockHeight = 64.0
        page.fillRect(x: marginLeft, y: top, width: blockWidth, height: blockHeight, color: ink)
        page.text(titleText.uppercased(), x: marginLeft + 12, baseline: top + 28, width: blockWidth - 24, style: TextStyle(font: fonts.heading, size: 20, color: .white), alignment: .left, shrinkToFit: true)
        page.text("N° \(numberText)", x: marginLeft + 12, baseline: top + 46, width: blockWidth - 24, style: TextStyle(font: fonts.bodyBold, size: 10, color: accent), alignment: .left)
        page.text("du \(DateFormatting.short(document.issueDate))", x: marginLeft + 12, baseline: top + 57, width: blockWidth - 24, style: TextStyle(font: fonts.body, size: 7.5, color: PDFColor(hex: "#C9C6BE")!), alignment: .left)

        let sellerX = marginLeft + blockWidth + 16
        let sellerWidth = right - sellerX
        let logoSize = drawLogo(x: sellerX, y: top, maxWidth: 90, maxHeight: 36, alignment: .left)
        let textX = sellerX + (logoSize.width > 0 ? logoSize.width + 10 : 0)
        let sellerHeight = drawPartyBlock(caption: "", name: document.seller.displayName, lines: sellerLines(), x: textX, top: top, width: right - textX, nameStyle: TextStyle(font: fonts.heading, size: bodySize + 3, color: ink))
        y = top + max(blockHeight, sellerHeight, logoSize.height) + 16

        let customerWidth = contentWidth * 0.52
        let customerHeight = partyHeight(caption: "Client / chantier", name: document.customer.name, lines: customerLines(), width: customerWidth - 16)
        page.fillRect(x: marginLeft, y: y, width: 4, height: customerHeight, color: accent)
        drawPartyBlock(caption: "Client / chantier", name: document.customer.name, lines: customerLines(), x: marginLeft + 14, top: y, width: customerWidth - 16, captionStyle: TextStyle(font: fonts.bodyBold, size: 7, color: accent))
        let metaX = marginLeft + customerWidth + 18
        let metaHeight = drawMeta(x: metaX, top: y, width: right - metaX)
        _ = sellerWidth
        y += max(customerHeight, metaHeight) + 18
    }

    // 12. Pastel — grand encart teinté avec le montant à payer.
    func headerPastel() {
        let top = y
        let logoSize = drawLogo(x: marginLeft, y: top, maxWidth: 100, maxHeight: 34)
        page.text(document.seller.displayName, x: marginLeft, baseline: top + (logoSize.height > 0 ? logoSize.height + 14 : 12), width: contentWidth * 0.6, style: TextStyle(font: fonts.heading, size: 13, color: ink), alignment: .left, shrinkToFit: true)
        y = top + (logoSize.height > 0 ? logoSize.height + 26 : 26)

        let panelHeight = 96.0
        page.fillRect(x: marginLeft, y: y, width: contentWidth, height: panelHeight, color: accent.tinted(0.86))
        page.text(titleText, x: marginLeft + 18, baseline: y + 38, width: contentWidth * 0.5, style: TextStyle(font: fonts.heading, size: 30, color: ink), alignment: .left, shrinkToFit: true)
        page.text("N° \(numberText) · \(DateFormatting.short(document.issueDate))", x: marginLeft + 18, baseline: y + 58, font: fonts.body, size: 9, color: muted)
        let highlight = highlightedAmount
        page.text(highlight.label, x: marginLeft, baseline: y + 26, width: contentWidth - 18, style: TextStyle(font: fonts.bodyBold, size: 7, color: accent), alignment: .right)
        page.text(Money.format(highlight.value), x: marginLeft + contentWidth * 0.5, baseline: y + 54, width: contentWidth * 0.5 - 18, style: TextStyle(font: fonts.heading, size: 24, color: accent), alignment: .right, shrinkToFit: true)
        page.text(keyDateLine, x: marginLeft, baseline: y + 74, width: contentWidth - 18, style: TextStyle(font: fonts.body, size: 8, color: muted), alignment: .right)
        y += panelHeight + 24

        let gap = 24.0
        let columnWidth = (contentWidth - gap) / 2
        let captionStyle = TextStyle(font: fonts.body, size: 7.5, color: accent)
        let h1 = drawPartyBlock(caption: "De", name: document.seller.displayName, lines: sellerLines(), x: marginLeft, top: y, width: columnWidth, captionStyle: captionStyle)
        let h2 = drawPartyBlock(caption: "Pour", name: document.customer.name, lines: customerLines(), x: marginLeft + columnWidth + gap, top: y, width: columnWidth, captionStyle: captionStyle)
        y += max(h1, h2) + 12
        y += page.paragraph(referencesLine(), x: marginLeft, top: y, width: contentWidth, style: small)
        y += 22
    }

    // 13. Ardoise — colonne de couleur pour l'émetteur, références à droite.
    func headerArdoise() {
        let top = y
        let columnWidth = contentWidth * 0.4
        let padding = 14.0
        let innerWidth = columnWidth - 2 * padding
        let onFill = accentOnFill
        let nameStyle = TextStyle(font: fonts.heading, size: 14, color: onFill)
        let detailStyle = TextStyle(font: fonts.body, size: bodySize - 0.5, color: onFill.tinted(0.12))
        let logoHeight: Double = logo != nil ? 46 : 0
        var contentHeight = logoHeight > 0 ? logoHeight + 10 : 0
        contentHeight += TextLayout.height(document.seller.displayName, style: nameStyle, width: innerWidth) + 4
        for line in sellerLines() { contentHeight += TextLayout.height(line, style: detailStyle, width: innerWidth) }
        let boxHeight = max(contentHeight + 2 * padding, 120)
        page.fillRect(x: marginLeft, y: top, width: columnWidth, height: boxHeight, color: accent)
        var cursor = top + padding
        if logo != nil {
            page.fillRect(x: marginLeft + padding, y: cursor, width: 64, height: logoHeight, color: .white)
            drawLogo(x: marginLeft + padding + 4, y: cursor + 4, maxWidth: 56, maxHeight: logoHeight - 8, alignment: .center)
            cursor += logoHeight + 10
        }
        cursor += page.paragraph(document.seller.displayName, x: marginLeft + padding, top: cursor, width: innerWidth, style: nameStyle) + 4
        for line in sellerLines() { cursor += page.paragraph(line, x: marginLeft + padding, top: cursor, width: innerWidth, style: detailStyle) }

        let rightX = marginLeft + columnWidth + 22
        let rightWidth = right - rightX
        page.text(titleText.uppercased(), x: rightX, baseline: top + 24, width: rightWidth, style: TextStyle(font: fonts.heading, size: 24, color: accent), alignment: .right, shrinkToFit: true)
        var rightCursor = top + 36
        rightCursor += drawMeta(x: rightX, top: rightCursor, width: rightWidth) + 12
        page.line(from: (rightX, rightCursor), to: (right, rightCursor), color: hairline, lineWidth: 0.6)
        rightCursor += 10
        rightCursor += drawPartyBlock(caption: "Facturé à", name: document.customer.name, lines: customerLines(), x: rightX, top: rightCursor, width: rightWidth, captionStyle: TextStyle(font: fonts.bodyBold, size: 7, color: accent))
        y = max(top + boxHeight, rightCursor) + 22
    }

    // 14. Compact — en-tête sur deux lignes, petite typographie.
    func headerCompact() {
        let top = y
        let logoSize = drawLogo(x: marginLeft, y: top, maxWidth: 60, maxHeight: 24)
        let nameX = marginLeft + (logoSize.width > 0 ? logoSize.width + 8 : 0)
        page.text(document.seller.displayName, x: nameX, baseline: top + 12, width: contentWidth * 0.55, style: TextStyle(font: fonts.bodyBold, size: 11, color: ink), alignment: .left, shrinkToFit: true)
        page.text("\(titleText.uppercased()) \(numberText)", x: marginLeft, baseline: top + 12, width: contentWidth, style: TextStyle(font: fonts.heading, size: 12, color: accent), alignment: .right)
        let sellerLine = sellerLines().joined(separator: " · ")
        var cursor = top + max(logoSize.height, 16) + 2
        cursor += page.paragraph(sellerLine, x: marginLeft, top: cursor, width: contentWidth, style: TextStyle(font: fonts.body, size: 7, color: muted))
        cursor += 4
        page.fillRect(x: marginLeft, y: cursor, width: contentWidth, height: 1.5, color: accent)
        y = cursor + 10
        let columnWidth = contentWidth * 0.55
        let customerHeight = drawPartyBlock(caption: "Client", name: document.customer.name, lines: customerLines(), x: marginLeft, top: y, width: columnWidth - 10)
        let metaX = marginLeft + columnWidth + 10
        let metaHeight = drawMeta(x: metaX, top: y, width: right - metaX, rowHeight: 10.5)
        y += max(customerHeight, metaHeight) + 12
    }
}
