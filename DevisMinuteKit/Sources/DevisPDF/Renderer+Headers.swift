import Foundation
import DevisCore

/// En-têtes de première page : une composition par modèle.
extension RenderSession {

    func drawFirstPageHeader() {
        switch template {
        case .classique: headerClassique()
        case .corporate: headerCorporate()
        case .minimal: headerMinimal()
        case .artisan: headerArtisan()
        case .creatif: headerCreatif()
        case .elegant: headerElegant()
        case .technique: headerTechnique()
        case .moderne: headerModerne()
        }
    }

    /// Bloc client et bloc émetteur côte à côte (gauche / droite), hauteur commune.
    private func partiesSideBySide(top: Double, leftCaption: String, rightCaption: String, gap: Double = 24, sellerOnLeft: Bool = true) -> Double {
        let columnWidth = (contentWidth - gap) / 2
        let seller = (document.seller.displayName, sellerLines())
        let customer = (document.customer.name, customerLines())
        let left = sellerOnLeft ? seller : customer
        let rightBlock = sellerOnLeft ? customer : seller
        let h1 = drawPartyBlock(caption: leftCaption, name: left.0, lines: left.1, x: marginLeft, top: top, width: columnWidth)
        let h2 = drawPartyBlock(caption: rightCaption, name: rightBlock.0, lines: rightBlock.1, x: marginLeft + columnWidth + gap, top: top, width: columnWidth)
        return max(h1, h2)
    }

    // 1. Classique — logo et émetteur à gauche, titre et références à droite, client encadré.
    private func headerClassique() {
        let top = y
        let leftWidth = contentWidth * 0.52
        var leftCursor = top
        let logoSize = drawLogo(x: marginLeft, y: top, maxWidth: 140, maxHeight: 56)
        if logoSize.height > 0 { leftCursor += logoSize.height + 10 }
        leftCursor += drawPartyBlock(caption: "", name: document.seller.displayName, lines: sellerLines(), x: marginLeft, top: leftCursor, width: leftWidth)

        let rightX = marginLeft + contentWidth * 0.58
        let rightWidth = right - rightX
        let titleStyle = TextStyle(font: fonts.heading, size: 24, color: accent)
        page.text(titleText.uppercased(), x: rightX, baseline: top + 22, width: rightWidth, style: titleStyle, alignment: .right, shrinkToFit: true)
        var rightCursor = top + 34
        rightCursor += drawMeta(x: rightX, top: rightCursor, width: rightWidth)
        rightCursor += 12

        let customerWidth = rightWidth
        let boxPadding = 9.0
        let innerHeight = partyHeight(caption: "Client", name: document.customer.name, lines: customerLines(), width: customerWidth - 2 * boxPadding)
        page.strokeRect(x: rightX, y: rightCursor, width: customerWidth, height: innerHeight + 2 * boxPadding, color: hairline, lineWidth: 0.7)
        drawPartyBlock(caption: "Client", name: document.customer.name, lines: customerLines(), x: rightX + boxPadding, top: rightCursor + boxPadding, width: customerWidth - 2 * boxPadding)
        rightCursor += innerHeight + 2 * boxPadding
        y = max(leftCursor, rightCursor) + 22
    }

    // 2. Corporate — bandeau plein pleine largeur, titre en blanc, parties en deux colonnes.
    private func headerCorporate() {
        let bandHeight = 92.0
        page.fillRect(x: 0, y: 0, width: pageWidth, height: bandHeight, color: accent)
        let onFill = accentOnFill
        var textX = marginLeft
        if logo != nil {
            // Pastille blanche pour garder le logo lisible sur le bandeau.
            page.fillRect(x: marginLeft, y: 18, width: 66, height: 56, color: .white)
            drawLogo(x: marginLeft + 5, y: 22, maxWidth: 56, maxHeight: 48, alignment: .center)
            textX += 80
        }
        page.text(document.seller.displayName, x: textX, baseline: 44, width: contentWidth * 0.55 - (textX - marginLeft), style: TextStyle(font: fonts.heading, size: 16, color: onFill), alignment: .left, shrinkToFit: true)
        let contact = [document.seller.email.trimmed, document.seller.phone.trimmed].filter { !$0.isEmpty }.joined(separator: "  ·  ")
        if !contact.isEmpty {
            page.text(TextLayout.truncate(contact, style: small, width: contentWidth * 0.5), x: textX, baseline: 60, font: fonts.body, size: 8, color: onFill.tinted(0.15))
        }
        page.text(titleText.uppercased(), x: marginLeft, baseline: 46, width: contentWidth, style: TextStyle(font: fonts.heading, size: 20, color: onFill), alignment: .right)
        page.text(numberText, x: marginLeft, baseline: 62, width: contentWidth, style: TextStyle(font: fonts.body, size: 10, color: onFill), alignment: .right)

        y = bandHeight + 22
        let gap = 20.0
        let columnWidth = (contentWidth - gap) / 3
        let captionStyle = TextStyle(font: fonts.bodyBold, size: 7, color: accent)
        let h1 = drawPartyBlock(caption: "Émetteur", name: document.seller.displayName, lines: sellerLines(), x: marginLeft, top: y, width: columnWidth, captionStyle: captionStyle)
        let h2 = drawPartyBlock(caption: "Destinataire", name: document.customer.name, lines: customerLines(), x: marginLeft + columnWidth + gap, top: y, width: columnWidth, captionStyle: captionStyle)
        page.text("RÉFÉRENCES", x: marginLeft + 2 * (columnWidth + gap), baseline: y + 7, font: captionStyle.font, size: captionStyle.size, color: captionStyle.color)
        let h3 = drawMeta(x: marginLeft + 2 * (columnWidth + gap), top: y + 12, width: columnWidth) + 12
        y += max(h1, h2, h3) + 24
    }

    // 3. Minimal — petite typographie, aucune couleur de fond, alignements stricts.
    private func headerMinimal() {
        let top = y
        let nameStyle = TextStyle(font: fonts.bodyBold, size: 10, color: ink)
        let logoSize = drawLogo(x: marginLeft, y: top, maxWidth: 90, maxHeight: 32)
        var cursor = top + (logoSize.height > 0 ? logoSize.height + 8 : 0)
        cursor += page.paragraph(document.seller.displayName, x: marginLeft, top: cursor, width: contentWidth / 2, style: nameStyle)
        let compact = TextStyle(font: fonts.body, size: 7.5, color: muted)
        for line in sellerLines() { cursor += page.paragraph(line, x: marginLeft, top: cursor, width: contentWidth / 2, style: compact) }

        let titleStyle = TextStyle(font: fonts.headingRegular, size: 13, color: ink)
        page.text("\(titleText) \(numberText)", x: marginLeft, baseline: top + 11, width: contentWidth, style: titleStyle, alignment: .right)
        var rightCursor = top + 22
        let metaValue = TextStyle(font: fonts.body, size: 7.5, color: ink)
        for (key, value) in metaRows() where key != "N°" {
            let text = "\(key)  \(value)"
            page.text(text, x: marginLeft, baseline: rightCursor + 8, width: contentWidth, style: metaValue, alignment: .right)
            rightCursor += 11
        }
        y = max(cursor, rightCursor) + 36

        let customerX = marginLeft + contentWidth * 0.5
        let height = drawPartyBlock(caption: "Pour", name: document.customer.name, lines: customerLines(), x: customerX, top: y, width: contentWidth * 0.5, captionStyle: TextStyle(font: fonts.body, size: 7, color: muted), nameStyle: TextStyle(font: fonts.bodyBold, size: 10, color: ink))
        y += height + 36
    }

    // 4. Artisan — en-tête encadré, bandeau de titre, références en grille.
    private func headerArtisan() {
        let top = y
        let boxPadding = 10.0
        let leftWidth = contentWidth * 0.56
        let logoWidth: Double = logo != nil ? 74 : 0
        let textWidth = leftWidth - 2 * boxPadding - (logoWidth > 0 ? logoWidth + 10 : 0)
        let sellerHeight = partyHeight(caption: "", name: document.seller.displayName, lines: sellerLines(), width: textWidth)
        let boxHeight = max(sellerHeight, logo != nil ? 60 : 0) + 2 * boxPadding
        page.strokeRect(x: marginLeft, y: top, width: leftWidth, height: boxHeight, color: accent, lineWidth: 1.2)
        if logo != nil { drawLogo(x: marginLeft + boxPadding, y: top + boxPadding, maxWidth: logoWidth, maxHeight: 60) }
        drawPartyBlock(caption: "", name: document.seller.displayName, lines: sellerLines(), x: marginLeft + boxPadding + (logoWidth > 0 ? logoWidth + 10 : 0), top: top + boxPadding, width: textWidth, nameStyle: TextStyle(font: fonts.heading, size: bodySize + 3, color: accent))

        let customerX = marginLeft + leftWidth + 14
        let customerWidth = right - customerX
        let customerHeight = drawPartyBlock(caption: "Client", name: document.customer.name, lines: customerLines(), x: customerX, top: top + 4, width: customerWidth)
        y = top + max(boxHeight, customerHeight + 4) + 16

        // Bandeau de titre
        let barHeight = 26.0
        page.fillRect(x: marginLeft, y: y, width: contentWidth, height: barHeight, color: accent)
        page.text("\(titleText.uppercased()) N° \(numberText)", x: marginLeft + 10, baseline: y + 17, font: fonts.heading, size: 12, color: accentOnFill)
        page.text("du \(DateFormatting.long(document.issueDate))", x: marginLeft, baseline: y + 17, width: contentWidth - 10, style: TextStyle(font: fonts.body, size: 9, color: accentOnFill), alignment: .right)
        y += barHeight

        // Grille de références
        let rows = metaRows().filter { $0.0 != "N°" && $0.0 != "Date" }
        if !rows.isEmpty {
            let cellWidth = contentWidth / Double(min(rows.count, 4))
            var index = 0
            while index < rows.count {
                let slice = Array(rows[index..<min(index + 4, rows.count)])
                for (offset, row) in slice.enumerated() {
                    let x = marginLeft + Double(offset) * cellWidth
                    page.strokeRect(x: x, y: y, width: cellWidth, height: 28, color: hairline, lineWidth: 0.6)
                    page.text(row.0.uppercased(), x: x + 6, baseline: y + 10, font: label.font, size: 6.5, color: muted)
                    page.text(row.1, x: x + 6, baseline: y + 22, width: cellWidth - 12, style: bodyBold, alignment: .left, shrinkToFit: true)
                }
                y += 28
                index += 4
            }
        }
        y += 16
    }

    // 5. Créatif — grand titre, bande verticale (dessinée par page), total mis en avant.
    private func headerCreatif() {
        let top = y
        let titleStyle = TextStyle(font: fonts.heading, size: 40, color: accent)
        page.text(titleText, x: marginLeft, baseline: top + 36, width: contentWidth * 0.65, style: titleStyle, alignment: .left, shrinkToFit: true)
        drawLogo(x: right - 120, y: top, maxWidth: 120, maxHeight: 50, alignment: .right)
        page.text("N° \(numberText)  ·  \(DateFormatting.long(document.issueDate))", x: marginLeft, baseline: top + 56, font: fonts.body, size: 10, color: muted)
        y = top + 78

        let columnWidth = contentWidth * 0.36
        let captionStyle = TextStyle(font: fonts.heading, size: 11, color: accent)
        let h1 = drawPartyBlock(caption: "", name: "De", lines: [], x: marginLeft, top: y, width: columnWidth, nameStyle: captionStyle)
        let h2 = drawPartyBlock(caption: "", name: "Pour", lines: [], x: marginLeft + columnWidth + 16, top: y, width: columnWidth, nameStyle: captionStyle)
        y += max(h1, h2) + 2
        let s = drawPartyBlock(caption: "", name: document.seller.displayName, lines: sellerLines(), x: marginLeft, top: y, width: columnWidth)
        let c = drawPartyBlock(caption: "", name: document.customer.name, lines: customerLines(), x: marginLeft + columnWidth + 16, top: y, width: columnWidth)

        // Encadré total à droite
        let boxX = marginLeft + 2 * columnWidth + 32
        let boxWidth = right - boxX
        let amountLabel = document.kind == .quote ? "Montant" : (document.kind == .creditNote ? "Montant de l'avoir" : "À régler")
        page.text(amountLabel.uppercased(), x: boxX, baseline: y + 8, font: label.font, size: 7, color: muted)
        let amount = document.kind == .quote || document.kind == .creditNote ? totals.totalTTC : (request.payment?.balance ?? totals.netToPay)
        page.text(Money.format(amount), x: boxX, baseline: y + 30, width: boxWidth, style: TextStyle(font: fonts.heading, size: 20, color: ink), alignment: .left, shrinkToFit: true)
        var metaCursor = y + 42
        for (key, value) in metaRows() where key != "N°" && key != "Date" {
            page.text("\(key) : \(value)", x: boxX, baseline: metaCursor + 8, width: boxWidth, style: small, alignment: .left, shrinkToFit: true)
            metaCursor += 11
        }
        y += max(s, c, metaCursor - y) + 28
    }

    // 6. Élégant — composition centrée, romaine, doubles filets.
    private func headerElegant() {
        let top = y
        var cursor = top
        let logoSize = drawLogo(x: marginLeft, y: cursor, maxWidth: contentWidth, maxHeight: 48, alignment: .center)
        if logoSize.height > 0 { cursor += logoSize.height + 10 }
        let spaced = document.seller.displayName.uppercased().map(String.init).joined(separator: "\u{2009}")
        page.text(spaced, x: marginLeft, baseline: cursor + 16, width: contentWidth, style: TextStyle(font: fonts.heading, size: 15, color: ink), alignment: .center, shrinkToFit: true)
        cursor += 24
        let contact = [document.seller.address.lines.joined(separator: ", "), document.seller.email.trimmed, document.seller.phone.trimmed].filter { !$0.isEmpty }.joined(separator: "  ·  ")
        cursor += page.paragraph(contact, x: marginLeft, top: cursor, width: contentWidth, style: small, alignment: .center)
        cursor += 8
        page.line(from: (marginLeft, cursor), to: (right, cursor), color: accent, lineWidth: 0.8)
        page.line(from: (marginLeft, cursor + 2.5), to: (right, cursor + 2.5), color: accent, lineWidth: 0.3)
        cursor += 22
        page.text(titleText, x: marginLeft, baseline: cursor + 12, width: contentWidth, style: TextStyle(font: .timesItalic, size: 20, color: accent), alignment: .center)
        cursor += 20
        page.text("n° \(numberText) — \(DateFormatting.long(document.issueDate))", x: marginLeft, baseline: cursor + 10, width: contentWidth, style: body.with(color: muted), alignment: .center)
        y = cursor + 30

        let gap = 40.0
        let columnWidth = (contentWidth - gap) / 2
        let captionStyle = TextStyle(font: .timesItalic, size: 9, color: accent)
        drawPartyBlock(caption: "", name: "À l'intention de", lines: [], x: marginLeft, top: y, width: columnWidth, nameStyle: captionStyle)
        let left = drawPartyBlock(caption: "", name: document.customer.name, lines: customerLines(), x: marginLeft, top: y + 14, width: columnWidth)
        var metaCursor = y
        for (key, value) in metaRows() where key != "N°" && key != "Date" {
            page.text(key, x: marginLeft + columnWidth + gap, baseline: metaCursor + 9, font: .timesItalic, size: 9, color: muted)
            page.text(value, x: marginLeft + columnWidth + gap, baseline: metaCursor + 9, width: columnWidth, style: body, alignment: .right, shrinkToFit: true)
            metaCursor += 13
        }
        var identity = metaCursor + 4
        let ids = sellerLines().filter { $0.hasPrefix("SIRET") || $0.hasPrefix("SIREN") || $0.hasPrefix("TVA") }
        for line in ids {
            identity += page.paragraph(line, x: marginLeft + columnWidth + gap, top: identity, width: columnWidth, style: small, alignment: .right)
        }
        y = max(y + 14 + left, identity) + 26
    }

    // 7. Technique — grille de références dense, police à chasse fixe.
    private func headerTechnique() {
        let top = y
        let logoSize = drawLogo(x: marginLeft, y: top, maxWidth: 100, maxHeight: 40)
        let nameX = marginLeft + (logoSize.width > 0 ? logoSize.width + 10 : 0)
        let nameWidth = contentWidth * 0.55 - (nameX - marginLeft)
        var cursor = top
        cursor += page.paragraph(document.seller.displayName, x: nameX, top: cursor, width: nameWidth, style: TextStyle(font: fonts.heading, size: 12, color: ink))
        let compact = TextStyle(font: fonts.body, size: 7.5, color: ink)
        for line in sellerLines() { cursor += page.paragraph(line, x: nameX, top: cursor, width: nameWidth, style: compact) }
        cursor = max(cursor, top + logoSize.height)

        // Cartouche de références (style plan technique)
        let boxX = marginLeft + contentWidth * 0.58
        let boxWidth = right - boxX
        let rows = metaRows()
        let rowHeight = 13.0
        page.fillRect(x: boxX, y: top, width: boxWidth, height: 16, color: accent)
        page.text(titleText.uppercased(), x: boxX + 6, baseline: top + 11.5, font: fonts.heading, size: 9.5, color: accentOnFill)
        var rowY = top + 16
        for (key, value) in rows {
            page.strokeRect(x: boxX, y: rowY, width: boxWidth, height: rowHeight, color: hairline, lineWidth: 0.5)
            page.line(from: (boxX + boxWidth * 0.42, rowY), to: (boxX + boxWidth * 0.42, rowY + rowHeight), color: hairline)
            page.text(key, x: boxX + 4, baseline: rowY + 9, font: fonts.body, size: 7, color: muted)
            page.text(value, x: boxX + boxWidth * 0.42 + 4, baseline: rowY + 9, width: boxWidth * 0.58 - 8, style: TextStyle(font: fonts.mono, size: 7.5, color: ink), alignment: .left, shrinkToFit: true)
            rowY += rowHeight
        }
        y = max(cursor, rowY) + 14

        let customerWidth = contentWidth * 0.5
        let h = partyHeight(caption: "Client", name: document.customer.name, lines: customerLines(), width: customerWidth - 12)
        page.fillRect(x: marginLeft, y: y, width: 2, height: h + 8, color: accent)
        drawPartyBlock(caption: "Client", name: document.customer.name, lines: customerLines(), x: marginLeft + 10, top: y + 4, width: customerWidth - 12)
        y += h + 22
    }

    // 8. Moderne — encart de synthèse teinté en tête, blocs teintés sans bordure.
    private func headerModerne() {
        let top = y
        let logoSize = drawLogo(x: marginLeft, y: top, maxWidth: 110, maxHeight: 40)
        var cursor = top + (logoSize.height > 0 ? logoSize.height + 12 : 0)
        page.text(titleText, x: marginLeft, baseline: cursor + 26, width: contentWidth * 0.55, style: TextStyle(font: fonts.heading, size: 28, color: ink), alignment: .left, shrinkToFit: true)
        cursor += 34
        page.text(numberText, x: marginLeft, baseline: cursor + 10, font: fonts.body, size: 10, color: accent)
        cursor += 18

        let panelX = marginLeft + contentWidth * 0.58
        let panelWidth = right - panelX
        let panelHeight = 74.0
        page.fillRect(x: panelX, y: top, width: panelWidth, height: panelHeight, color: accent.tinted(0.88))
        page.fillRect(x: panelX, y: top, width: 3, height: panelHeight, color: accent)
        let summaryLabel = document.kind == .quote ? "TOTAL TTC" : (document.kind == .creditNote ? "MONTANT DE L'AVOIR" : "NET À PAYER")
        page.text(summaryLabel, x: panelX + 14, baseline: top + 18, font: label.font, size: 7, color: accent)
        let amount = document.kind == .quote || document.kind == .creditNote ? totals.totalTTC : (request.payment?.balance ?? totals.netToPay)
        page.text(Money.format(amount), x: panelX + 14, baseline: top + 42, width: panelWidth - 28, style: TextStyle(font: fonts.heading, size: 20, color: ink), alignment: .left, shrinkToFit: true)
        let dateLine: String
        switch document.kind {
        case .quote: dateLine = document.validUntil.map { "Valable jusqu'au \(DateFormatting.short($0))" } ?? ""
        case .creditNote: dateLine = "Émis le \(DateFormatting.short(document.issueDate))"
        default: dateLine = document.dueDate.map { "Échéance le \(DateFormatting.short($0))" } ?? ""
        }
        page.text(dateLine, x: panelX + 14, baseline: top + 60, font: fonts.body, size: 8, color: muted)
        y = max(cursor, top + panelHeight) + 18

        let gap = 12.0
        let columnWidth = (contentWidth - gap) / 2
        let padding = 12.0
        let sellerHeight = partyHeight(caption: "De", name: document.seller.displayName, lines: sellerLines(), width: columnWidth - 2 * padding)
        let customerHeight = partyHeight(caption: "Pour", name: document.customer.name, lines: customerLines(), width: columnWidth - 2 * padding)
        let blockHeight = max(sellerHeight, customerHeight) + 2 * padding
        page.fillRect(x: marginLeft, y: y, width: columnWidth, height: blockHeight, color: wash)
        page.fillRect(x: marginLeft + columnWidth + gap, y: y, width: columnWidth, height: blockHeight, color: wash)
        drawPartyBlock(caption: "De", name: document.seller.displayName, lines: sellerLines(), x: marginLeft + padding, top: y + padding, width: columnWidth - 2 * padding)
        drawPartyBlock(caption: "Pour", name: document.customer.name, lines: customerLines(), x: marginLeft + columnWidth + gap + padding, top: y + padding, width: columnWidth - 2 * padding)
        y += blockHeight + 10
        let refs = metaRows().filter { !["N°"].contains($0.0) }.map { "\($0.0) : \($0.1)" }.joined(separator: "   ·   ")
        y += page.paragraph(refs, x: marginLeft, top: y, width: contentWidth, style: small)
        y += 16
    }
}
