import Foundation
import DevisCore

/// Ligne du bloc des totaux.
struct TotalRow {
    enum Emphasis { case normal, strong, grand, deduction }
    var label: String
    var value: String
    var emphasis: Emphasis
}

/// Totaux, conditions, mentions légales et zone de signature.
extension RenderSession {

    func totalRows() -> [TotalRow] {
        var rows: [TotalRow] = []
        let vatRegistered = document.seller.isVATRegistered
        let chargesVAT = document.chargesVAT
        if totals.globalDiscountHT > 0 {
            rows.append(TotalRow(label: vatRegistered ? "Sous-total HT" : "Sous-total", value: Money.format(totals.subtotalHT), emphasis: .normal))
            let discountLabel: String
            if case .percent(let rate) = document.globalDiscount {
                discountLabel = "Remise \(Money.formatQuantity(rate)) %"
            } else {
                discountLabel = "Remise"
            }
            rows.append(TotalRow(label: discountLabel, value: "−" + Money.format(totals.globalDiscountHT), emphasis: .deduction))
        }
        if chargesVAT {
            rows.append(TotalRow(label: "Total HT", value: Money.format(totals.totalHT), emphasis: .strong))
            for bucket in totals.vatBuckets {
                let label = totals.vatBuckets.count > 1 || template == .technique
                    ? "TVA \(Money.formatQuantity(bucket.rate)) % sur \(Money.format(bucket.baseHT))"
                    : "TVA \(Money.formatQuantity(bucket.rate)) %"
                rows.append(TotalRow(label: label, value: Money.format(bucket.vatAmount), emphasis: .normal))
            }
            let ttcLabel = document.kind == .creditNote ? "Total TTC de l'avoir" : "Total TTC"
            rows.append(TotalRow(label: ttcLabel, value: Money.format(totals.totalTTC), emphasis: .grand))
        } else {
            let label = vatRegistered ? "Total HT" : (document.kind == .creditNote ? "Total de l'avoir" : "Total")
            rows.append(TotalRow(label: label, value: Money.format(totals.totalHT), emphasis: .grand))
            if vatRegistered && document.reverseCharge {
                rows.append(TotalRow(label: "TVA due par le preneur (autoliquidation)", value: "—", emphasis: .normal))
            }
        }
        for deposit in document.depositDeductions {
            rows.append(TotalRow(label: "Acompte facturé n° \(deposit.invoiceNumber) du \(DateFormatting.short(deposit.issueDate))", value: "−" + Money.format(deposit.amountTTC), emphasis: .deduction))
        }
        if !document.depositDeductions.isEmpty {
            rows.append(TotalRow(label: "Net à payer", value: Money.format(totals.netToPay), emphasis: .grand))
        }
        if let payment = request.payment, document.kind != .quote, document.kind != .creditNote, payment.paid > 0 || payment.credited > 0 {
            if payment.credited > 0 { rows.append(TotalRow(label: "Avoirs imputés", value: "−" + Money.format(payment.credited), emphasis: .deduction)) }
            if payment.paid > 0 { rows.append(TotalRow(label: "Déjà réglé", value: "−" + Money.format(payment.paid), emphasis: .deduction)) }
            rows.append(TotalRow(label: "Reste à payer", value: Money.format(payment.balance), emphasis: .strong))
        }
        if document.kind == .quote && totals.requestedDepositTTC > 0 {
            rows.append(TotalRow(label: "Acompte à la commande", value: Money.format(totals.requestedDepositTTC), emphasis: .normal))
        }
        return rows
    }

    func drawTotals() {
        let rows = totalRows()
        let rowHeight = template == .technique ? 13.0 : 16.0
        let grandHeight = template == .creatif ? 30.0 : 22.0
        let blockHeight = rows.reduce(0) { $0 + ($1.emphasis == .grand ? grandHeight : rowHeight) } + 10
        let vatTableHeight = template == .technique && document.chargesVAT ? Double(totals.vatBuckets.count + 1) * 13 + 10 : 0
        ensureSpace(max(blockHeight, vatTableHeight) + 8)

        let width: Double = template == .minimal ? contentWidth * 0.42 : 238
        let x = right - width
        var cursor = y

        if template == .technique && document.chargesVAT {
            drawVATRecap(x: marginLeft, top: y, width: contentWidth - width - 20)
        }
        if template == .corporate {
            page.fillRect(x: x, y: cursor, width: width, height: blockHeight, color: accent.tinted(0.93))
        }
        if template == .artisan {
            page.strokeRect(x: x, y: cursor, width: width, height: blockHeight, color: accent, lineWidth: 0.8)
        }
        cursor += 5
        for row in rows {
            let height = row.emphasis == .grand ? grandHeight : rowHeight
            var labelStyle = TextStyle(font: fonts.body, size: bodySize, color: ink)
            var valueStyle = TextStyle(font: template == .technique ? fonts.mono : fonts.body, size: bodySize, color: ink)
            switch row.emphasis {
            case .normal:
                labelStyle.color = muted
            case .deduction:
                labelStyle.color = muted
                valueStyle.color = muted
            case .strong:
                labelStyle.font = fonts.bodyBold
                valueStyle.font = template == .technique ? fonts.mono : fonts.bodyBold
            case .grand:
                labelStyle.font = fonts.heading
                valueStyle.font = fonts.heading
                labelStyle.size = bodySize + 1.5
                valueStyle.size = template == .creatif ? bodySize + 8 : bodySize + 2
                switch template {
                case .corporate, .moderne:
                    page.fillRect(x: x, y: cursor, width: width, height: height, color: accent)
                    labelStyle.color = accentOnFill
                    valueStyle.color = accentOnFill
                case .classique, .artisan, .technique:
                    page.line(from: (x, cursor), to: (right, cursor), color: accent, lineWidth: 1)
                    valueStyle.color = accent
                case .elegant:
                    page.line(from: (x, cursor), to: (right, cursor), color: accent, lineWidth: 0.6)
                    page.line(from: (x, cursor + 2), to: (right, cursor + 2), color: accent, lineWidth: 0.3)
                    labelStyle.font = .timesItalic
                case .minimal:
                    page.line(from: (x, cursor), to: (right, cursor), color: ink, lineWidth: 0.4)
                case .creatif:
                    valueStyle.color = accent
                default:
                    break
                }
            }
            let baseline = cursor + height / 2 + labelStyle.size * 0.35
            let padding = template == .corporate || template == .moderne || template == .artisan ? 8.0 : 0
            let valueWidth = row.emphasis == .grand && template == .creatif ? width * 0.6 : 100
            page.text(row.label, x: x + padding, baseline: baseline, width: width - valueWidth - 2 * padding, style: labelStyle, alignment: .left, shrinkToFit: true)
            page.text(row.value, x: right - valueWidth - padding, baseline: row.emphasis == .grand ? cursor + height / 2 + valueStyle.size * 0.35 : baseline, width: valueWidth, style: valueStyle, alignment: .right, shrinkToFit: true)
            cursor += height
        }
        y = max(cursor + 6, y + vatTableHeight) + 14
    }

    /// Récapitulatif de TVA (modèle Technique).
    private func drawVATRecap(x: Double, top: Double, width: Double) {
        guard width > 160 else { return }
        let columns: [(String, Double)] = [("Taux", 0.2), ("Base HT", 0.3), ("TVA", 0.25), ("TTC", 0.25)]
        var rowTop = top
        func row(_ values: [String], header: Bool) {
            var cellX = x
            if header { page.fillRect(x: x, y: rowTop, width: width, height: 13, color: wash) }
            page.strokeRect(x: x, y: rowTop, width: width, height: 13, color: hairline, lineWidth: 0.5)
            for (index, value) in values.enumerated() {
                let cellWidth = width * columns[index].1
                let style = header ? TextStyle(font: fonts.heading, size: 6.8, color: ink) : TextStyle(font: fonts.mono, size: 7.5, color: ink)
                page.text(value, x: cellX + 4, baseline: rowTop + 9, width: cellWidth - 8, style: style, alignment: index == 0 ? .left : .right, shrinkToFit: true)
                cellX += cellWidth
            }
            rowTop += 13
        }
        row(columns.map(\.0), header: true)
        for bucket in totals.vatBuckets {
            row(["\(Money.formatQuantity(bucket.rate)) %", Money.format(bucket.baseHT), Money.format(bucket.vatAmount), Money.format(bucket.baseHT + bucket.vatAmount)], header: false)
        }
    }

    // MARK: Blocs de fin de document

    func drawClosingBlocks() {
        let sectionTitle = TextStyle(font: fonts.heading, size: bodySize, color: template == .minimal ? ink : accent)
        let text = TextStyle(font: fonts.body, size: bodySize - 0.5, color: ink)

        // Conditions de règlement et coordonnées bancaires (factures et devis avec acompte).
        var payment: [String] = []
        if !document.paymentTermsText.trimmed.isEmpty { payment.append(document.paymentTermsText.trimmed) }
        if document.kind == .invoice || document.kind == .depositInvoice, request.appearance.showBankDetails {
            let seller = document.seller
            if !seller.iban.trimmed.isEmpty {
                var bank = "Virement — IBAN \(formatIBAN(seller.iban))"
                if !seller.bic.trimmed.isEmpty { bank += " · BIC \(seller.bic.trimmed.uppercased())" }
                if !seller.bankName.trimmed.isEmpty { bank += " · \(seller.bankName.trimmed)" }
                payment.append(bank)
            }
            if !document.number.isEmpty { payment.append("Merci d'indiquer la référence \(document.number) avec votre règlement.") }
        }
        if !payment.isEmpty {
            flowBlock(title: document.kind == .quote ? "Modalités de paiement" : "Règlement", text: payment.joined(separator: "\n"), titleStyle: sectionTitle, textStyle: text)
        }
        drawOnlinePaymentBlock()
        if !document.specialConditions.trimmed.isEmpty {
            flowBlock(title: "Conditions particulières", text: document.specialConditions.trimmed, titleStyle: sectionTitle, textStyle: text)
        }
        if !document.notes.trimmed.isEmpty {
            flowBlock(title: document.kind == .creditNote ? "Motif" : "Notes", text: document.notes.trimmed, titleStyle: sectionTitle, textStyle: text)
        }
        let mentions = LegalMentionsBuilder.mentions(for: document, totals: totals)
        if !mentions.isEmpty {
            flowBlock(title: "Mentions", text: mentions.joined(separator: "\n"), titleStyle: sectionTitle, textStyle: TextStyle(font: fonts.body, size: bodySize - 1.5, color: muted))
        }
        if document.kind == .quote, let signature = request.signature, let image = PDFImage(jpegData: signature.imageJPEG) {
            drawSignedBlock(signature, image: image)
        } else if document.kind == .quote && request.appearance.showSignatureBlock {
            drawSignatureBlock()
        }
    }

    /// Bloc « Payer en ligne » : QR code + lien cliquable (Stripe, SumUp, PayPal…).
    func drawOnlinePaymentBlock() {
        guard document.kind != .creditNote, let link = document.paymentLink?.trimmed, PaymentLink.isValid(link) else { return }
        if let payment = request.payment, payment.balance == 0, payment.paid > 0 { return }
        let qrSize = 64.0
        let hasQR = request.paymentQRCodeJPEG.flatMap(PDFImage.init(jpegData:)) != nil
        let height = max(hasQR ? qrSize : 0, 40) + 12
        ensureSpace(height + 8)
        let top = y
        page.strokeRect(x: marginLeft, y: top, width: contentWidth, height: height, color: accent.tinted(0.5), lineWidth: 0.7)
        var textX = marginLeft + 10
        if let data = request.paymentQRCodeJPEG, let image = PDFImage(jpegData: data) {
            let handle = builder.register(image: image)
            page.image(handle, x: marginLeft + 6, y: top + 6, width: qrSize, height: qrSize)
            textX = marginLeft + qrSize + 16
        }
        let textWidth = right - textX - 10
        let provider = PaymentLink.providerName(link).map { " (\($0))" } ?? ""
        page.text("Payer en ligne\(provider)", x: textX, baseline: top + 18, font: fonts.heading, size: bodySize, color: accent)
        let amountDue = request.payment?.balance ?? totals.netToPay
        let lineStyle = TextStyle(font: fonts.body, size: bodySize - 1, color: ink)
        let explanation = document.kind == .quote ? "Réglez l'acompte par carte bancaire en scannant le QR code ou via le lien :" : "Réglez \(Money.format(amountDue)) par carte bancaire en scannant le QR code ou via le lien :"
        page.paragraph(explanation, x: textX, top: top + 24, width: textWidth, style: lineStyle)
        let linkStyle = TextStyle(font: fonts.body, size: bodySize - 1.5, color: accent)
        let shown = TextLayout.truncate(link, style: linkStyle, width: textWidth)
        page.text(shown, x: textX, baseline: top + 24 + lineStyle.lineHeight * 2 + 6, font: linkStyle.font, size: linkStyle.size, color: accent)
        page.link(url: link, x: textX, y: top + 24 + lineStyle.lineHeight * 2 - 4, width: linkStyle.font.width(of: shown, size: linkStyle.size), height: linkStyle.size + 4)
        if hasQR { page.link(url: link, x: marginLeft + 6, y: top + 6, width: qrSize, height: qrSize) }
        y = top + height + 14
    }

    func formatIBAN(_ iban: String) -> String {
        let compact = iban.uppercased().filter { !$0.isWhitespace }
        var groups: [String] = []
        var current = ""
        for character in compact {
            current.append(character)
            if current.count == 4 { groups.append(current); current = "" }
        }
        if !current.isEmpty { groups.append(current) }
        return groups.joined(separator: " ")
    }

    /// Titre + paragraphe pouvant s'étendre sur plusieurs pages.
    func flowBlock(title: String, text: String, titleStyle: TextStyle, textStyle: TextStyle) {
        let lines = TextLayout.wrap(text, style: textStyle, width: contentWidth)
        // Le titre reste toujours avec au moins deux lignes de texte.
        ensureSpace(titleStyle.lineHeight + 4 + min(Double(lines.count), 2) * textStyle.lineHeight)
        page.text(template == .moderne ? title.uppercased() : title, x: marginLeft, baseline: y + titleStyle.size, font: titleStyle.font, size: template == .moderne ? titleStyle.size - 1.5 : titleStyle.size, color: titleStyle.color)
        y += titleStyle.lineHeight + 4
        for line in lines {
            if ensureSpace(textStyle.lineHeight) { /* suite sur la page suivante */ }
            page.lines([line], x: marginLeft, top: y, width: contentWidth, style: textStyle)
            y += textStyle.lineHeight
        }
        y += 12
    }

    private func drawSignatureBlock() {
        let height = 92.0
        ensureSpace(height + 4)
        let width = contentWidth * 0.48
        let x = right - width
        let emphasis = template == .artisan
        page.strokeRect(x: x, y: y, width: width, height: height, color: emphasis ? accent : hairline, lineWidth: emphasis ? 1 : 0.6)
        let titleStyle = TextStyle(font: fonts.bodyBold, size: bodySize, color: emphasis ? accent : ink)
        page.text("Bon pour accord", x: x + 10, baseline: y + 16, font: titleStyle.font, size: titleStyle.size, color: titleStyle.color)
        page.paragraph("Date, signature et mention manuscrite « Devis reçu avant l'exécution des travaux, bon pour accord »", x: x + 10, top: y + 22, width: width - 20, style: TextStyle(font: fonts.body, size: 7, color: muted))
        y += height + 10
    }

    /// Zone « Bon pour accord » remplie : mention, signataire, date et tracé de la signature.
    private func drawSignedBlock(_ signature: QuoteSignature, image: PDFImage) {
        let height = 118.0
        ensureSpace(height + 4)
        let width = contentWidth * 0.48
        let x = right - width
        let top = y
        page.strokeRect(x: x, y: top, width: width, height: height, color: accent, lineWidth: 1)
        page.text("Bon pour accord", x: x + 10, baseline: top + 16, font: fonts.bodyBold, size: bodySize, color: accent)
        let small = TextStyle(font: fonts.body, size: 7.5, color: ink)
        var details = "Signé le \(DateFormatting.short(signature.signedAt))"
        if !signature.place.isEmpty { details += " à \(signature.place)" }
        details += " par \(signature.signerName)"
        let detailLines = TextLayout.wrap(details, style: small, width: width - 20)
        page.lines(detailLines, x: x + 10, top: top + 22, width: width - 20, style: small)
        var cursor = top + 22 + Double(detailLines.count) * small.lineHeight + 1
        let mention = TextStyle(font: fonts.italic, size: 7, color: muted)
        let mentionLines = TextLayout.wrap("« \(QuoteSignature.acceptanceMention) »", style: mention, width: width - 20)
        page.lines(mentionLines, x: x + 10, top: cursor, width: width - 20, style: mention)
        cursor += Double(mentionLines.count) * mention.lineHeight + 3
        // Tracé : ajusté dans l'espace restant en conservant ses proportions.
        let boxWidth = width - 20
        let boxHeight = top + height - 6 - cursor
        if boxHeight > 10, image.pixelWidth > 0, image.pixelHeight > 0 {
            let ratio = Double(image.pixelWidth) / Double(image.pixelHeight)
            var drawWidth = boxWidth
            var drawHeight = drawWidth / ratio
            if drawHeight > boxHeight {
                drawHeight = boxHeight
                drawWidth = drawHeight * ratio
            }
            let handle = builder.register(image: image)
            page.image(handle, x: x + 10, y: cursor, width: drawWidth, height: drawHeight)
        }
        y = top + height + 10
    }
}

extension RenderSession {
    /// Section « Photos » : grille de deux colonnes, légende sous chaque photo, jamais coupée entre deux pages.
    func drawPhotos() {
        let photos = request.photos.prefix(DocumentPhoto.maximumCount).compactMap { photo -> (PDFImage, String)? in
            guard let image = PDFImage(jpegData: photo.jpeg), image.pixelWidth > 0, image.pixelHeight > 0 else { return nil }
            return (image, photo.caption.trimmed)
        }
        if photos.count < request.photos.prefix(DocumentPhoto.maximumCount).count {
            warnings.append("Une photo n'a pas pu être lue et n'est pas imprimée.")
        }
        guard !photos.isEmpty else { return }
        let titleStyle = TextStyle(font: fonts.heading, size: bodySize + 1, color: template == .minimal ? ink : accent)
        let captionStyle = TextStyle(font: fonts.body, size: bodySize - 1, color: muted)
        let gap = 14.0
        let cellWidth = (contentWidth - gap) / 2
        let maxImageHeight = 170.0
        var first = true
        for start in stride(from: 0, to: photos.count, by: 2) {
            let row = Array(photos[start..<min(start + 2, photos.count)])
            let sizes = row.map { image, _ -> (Double, Double) in
                let ratio = Double(image.pixelWidth) / Double(image.pixelHeight)
                var width = cellWidth
                var height = width / ratio
                if height > maxImageHeight { height = maxImageHeight; width = height * ratio }
                return (width, height)
            }
            let captionHeight = row.map { $0.1.isEmpty ? 0 : TextLayout.height($0.1, style: captionStyle, width: cellWidth) + 4 }.max() ?? 0
            let rowHeight = (sizes.map(\.1).max() ?? 0) + captionHeight + gap
            let heading = first ? titleStyle.lineHeight + 8 : 0
            ensureSpace(heading + rowHeight)
            if first {
                y += 6
                page.text("Photos", x: marginLeft, baseline: y + titleStyle.size, font: titleStyle.font, size: titleStyle.size, color: titleStyle.color)
                y += titleStyle.lineHeight + 8
                first = false
            }
            let imageAreaHeight = sizes.map(\.1).max() ?? 0
            for (index, item) in row.enumerated() {
                let x = marginLeft + Double(index) * (cellWidth + gap)
                let (width, height) = sizes[index]
                let handle = builder.register(image: item.0)
                page.image(handle, x: x + (cellWidth - width) / 2, y: y + (imageAreaHeight - height), width: width, height: height)
                page.strokeRect(x: x + (cellWidth - width) / 2, y: y + (imageAreaHeight - height), width: width, height: height, color: hairline, lineWidth: 0.4)
                if !item.1.isEmpty {
                    page.paragraph(item.1, x: x, top: y + imageAreaHeight + 4, width: cellWidth, style: captionStyle, alignment: .center)
                }
            }
            y += rowHeight
        }
    }
}
