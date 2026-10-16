import Foundation
import DevisCore

/// Colonne du tableau des prestations.
struct TableColumn {
    enum Kind { case index, designation, quantity, unit, quantityWithUnit, unitPrice, discount, vat, total }
    var kind: Kind
    var title: String
    var width: Double
    var alignment: TextAlignment
}

/// Tableau des prestations : colonnes adaptées au modèle et au contenu, multipage.
extension RenderSession {

    var hasLineDiscounts: Bool { document.itemLines.contains { !$0.discount.isNone } }
    var showsVATColumn: Bool { document.chargesVAT }

    func makeColumns() -> [TableColumn] {
        var columns: [TableColumn] = []
        if template == .technique { columns.append(TableColumn(kind: .index, title: "#", width: 20, alignment: .left)) }
        columns.append(TableColumn(kind: .designation, title: "Désignation", width: 0, alignment: .left))
        if template == .minimal {
            columns.append(TableColumn(kind: .quantityWithUnit, title: "Qté", width: 56, alignment: .right))
        } else {
            columns.append(TableColumn(kind: .quantity, title: "Qté", width: 38, alignment: .right))
            columns.append(TableColumn(kind: .unit, title: "Unité", width: 40, alignment: .left))
        }
        columns.append(TableColumn(kind: .unitPrice, title: "PU HT", width: 62, alignment: .right))
        if hasLineDiscounts && template != .minimal { columns.append(TableColumn(kind: .discount, title: "Remise", width: 46, alignment: .right)) }
        if showsVATColumn && template != .minimal { columns.append(TableColumn(kind: .vat, title: "TVA", width: 34, alignment: .right)) }
        columns.append(TableColumn(kind: .total, title: document.seller.isVATRegistered ? "Total HT" : "Total", width: 70, alignment: .right))
        if template == .minimal, let index = columns.firstIndex(where: { $0.kind == .unitPrice }) {
            columns[index].title = document.seller.isVATRegistered ? "Prix HT" : "Prix"
        }
        let fixed = columns.reduce(0) { $0 + $1.width }
        if let index = columns.firstIndex(where: { $0.kind == .designation }) {
            columns[index].width = max(contentWidth - fixed, 120)
        }
        return columns
    }

    var cellPadding: Double { template == .technique ? 3 : 5 }
    var rowPadding: Double {
        switch template {
        case .technique: return 3
        case .minimal, .creatif, .elegant: return 6
        default: return 4.5
        }
    }

    var headerStyle: TextStyle {
        switch template {
        case .corporate, .artisan: return TextStyle(font: fonts.bodyBold, size: 7.5, color: accentOnFill)
        case .moderne, .minimal: return TextStyle(font: fonts.bodyBold, size: 6.8, color: muted)
        case .elegant: return TextStyle(font: .timesItalic, size: 9, color: accent)
        case .technique: return TextStyle(font: fonts.heading, size: 7, color: ink)
        default: return TextStyle(font: fonts.bodyBold, size: 7.5, color: accent)
        }
    }

    var headerRowHeight: Double { template == .technique ? 15 : 20 }

    func drawTableHeader(_ columns: [TableColumn]) {
        let height = headerRowHeight
        switch template {
        case .corporate, .artisan:
            page.fillRect(x: marginLeft, y: y, width: contentWidth, height: height, color: accent)
        case .technique:
            page.fillRect(x: marginLeft, y: y, width: contentWidth, height: height, color: wash)
            page.strokeRect(x: marginLeft, y: y, width: contentWidth, height: height, color: hairline, lineWidth: 0.5)
        case .elegant:
            page.line(from: (marginLeft, y), to: (right, y), color: accent, lineWidth: 0.6)
        default:
            break
        }
        var x = marginLeft
        let style = headerStyle
        let uppercase = template == .moderne || template == .minimal || template == .corporate
        for column in columns {
            let title = uppercase ? column.title.uppercased() : column.title
            page.text(title, x: x + cellPadding, baseline: y + height / 2 + style.size * 0.35, width: column.width - 2 * cellPadding, style: style, alignment: column.alignment, shrinkToFit: true)
            x += column.width
        }
        switch template {
        case .classique, .moderne, .creatif:
            page.line(from: (marginLeft, y + height), to: (right, y + height), color: template == .moderne ? hairline : accent, lineWidth: template == .classique ? 1 : 0.6)
        case .minimal:
            page.line(from: (marginLeft, y + height), to: (right, y + height), color: ink, lineWidth: 0.4)
        case .elegant:
            page.line(from: (marginLeft, y + height), to: (right, y + height), color: accent, lineWidth: 0.6)
        case .artisan:
            drawVerticalRules(columns, top: y, height: height, color: accent.tinted(0.4))
        case .technique:
            drawVerticalRules(columns, top: y, height: height, color: hairline)
        default:
            break
        }
        y += height
    }

    func drawVerticalRules(_ columns: [TableColumn], top: Double, height: Double, color: PDFColor) {
        var x = marginLeft
        for column in columns.dropLast() {
            x += column.width
            page.line(from: (x, top), to: (x, top + height), color: color, lineWidth: 0.5)
        }
    }

    func cellText(_ column: TableColumn, line: DocumentLine, lineTotals: LineTotals, index: Int) -> String {
        switch column.kind {
        case .index: return String(index)
        case .designation: return line.designation
        case .quantity: return Money.formatQuantity(line.quantity)
        case .unit: return line.unit
        case .quantityWithUnit: return [Money.formatQuantity(line.quantity), line.unit].filter { !$0.isEmpty }.joined(separator: " ")
        case .unitPrice: return Money.format(line.unitPriceHT, scale: priceScale(line.unitPriceHT))
        case .discount: return line.discount.isNone ? "" : line.discount.label
        case .vat: return "\(Money.formatQuantity(line.vatRate)) %"
        case .total: return Money.format(lineTotals.netHT)
        }
    }

    /// Prix unitaires : 2 décimales, ou jusqu'à 4 si nécessaire (règle R1).
    func priceScale(_ value: Decimal) -> Int {
        Money.round(value) == value ? 2 : (Money.round(value, scale: 3) == value ? 3 : 4)
    }

    func drawTable() {
        let columns = makeColumns()
        ensureSpace(headerRowHeight + 30)
        drawTableHeader(columns)

        guard let designationColumn = columns.first(where: { $0.kind == .designation }) else { return }
        let designationWidth = designationColumn.width - 2 * cellPadding
        let designationX = marginLeft + columns.prefix { $0.kind != .designation }.reduce(0) { $0 + $1.width } + cellPadding
        let nameStyle = template == .minimal || template == .elegant ? body : bodyBold.with(font: fonts.bodyBold)
        let detailStyle = TextStyle(font: fonts.body, size: bodySize - 1, color: muted)
        let noteStyle = TextStyle(font: fonts.italic, size: bodySize - 0.5, color: muted)

        var itemIndex = 0
        var zebra = false
        var sectionTitle: String?
        var sectionTotal = Decimal(0)
        var sectionHasItems = false

        func drawSectionSubtotal() {
            guard template == .technique, let title = sectionTitle, sectionHasItems else { return }
            let height = 15.0
            if ensureSpace(height) { drawTableHeader(columns) }
            page.fillRect(x: marginLeft, y: y, width: contentWidth, height: height, color: wash)
            page.strokeRect(x: marginLeft, y: y, width: contentWidth, height: height, color: hairline, lineWidth: 0.5)
            let totalColumn = columns.last!
            page.text("Sous-total — \(title)", x: designationX, baseline: y + 10.5, width: contentWidth - totalColumn.width - (designationX - marginLeft), style: TextStyle(font: fonts.heading, size: 7, color: ink), alignment: .left, shrinkToFit: true)
            page.text(Money.format(sectionTotal), x: right - totalColumn.width + cellPadding, baseline: y + 10.5, width: totalColumn.width - 2 * cellPadding, style: TextStyle(font: fonts.mono, size: 7.5, color: ink), alignment: .right, shrinkToFit: true)
            y += height
        }

        for line in document.lines {
            switch line.kind {
            case .section:
                drawSectionSubtotal()
                sectionTitle = line.designation
                sectionTotal = 0
                sectionHasItems = false
                let style = TextStyle(font: fonts.heading, size: bodySize + 0.5, color: accent)
                let lines = TextLayout.wrap(line.designation, style: style, width: contentWidth - 2 * cellPadding)
                let height = Double(lines.count) * style.lineHeight + rowPadding * 2 + 4
                // Un titre de section n'est jamais laissé seul en bas de page.
                if ensureSpace(height + 24) { drawTableHeader(columns) }
                if template == .artisan || template == .technique {
                    page.fillRect(x: marginLeft, y: y, width: contentWidth, height: height, color: accent.tinted(0.9))
                    page.strokeRect(x: marginLeft, y: y, width: contentWidth, height: height, color: hairline, lineWidth: 0.5)
                }
                page.lines(lines, x: marginLeft + cellPadding, top: y + rowPadding + 2, width: contentWidth - 2 * cellPadding, style: style)
                y += height
                zebra = false

            case .note:
                let lines = TextLayout.wrap(line.designation + (line.details.isEmpty ? "" : "\n" + line.details), style: noteStyle, width: designationWidth)
                drawSplittableRow(rows: lines.map { ($0, noteStyle) }, columns: columns, values: nil, zebraFill: false)

            case .item:
                itemIndex += 1
                let lineTotals = totals.lines[line.id] ?? DocumentCalculator.lineTotals(line)
                sectionTotal += lineTotals.netHT
                sectionHasItems = true
                var rows: [(String, TextStyle)] = TextLayout.wrap(line.designation.isEmpty ? "—" : line.designation, style: nameStyle, width: designationWidth).map { ($0, nameStyle) }
                if !line.details.trimmed.isEmpty {
                    rows += TextLayout.wrap(line.details, style: detailStyle, width: designationWidth).map { ($0, detailStyle) }
                }
                var values: [(TableColumn, String, Double)] = []
                var x = marginLeft
                for column in columns {
                    if column.kind != .designation {
                        values.append((column, cellText(column, line: line, lineTotals: lineTotals, index: itemIndex), x))
                    }
                    x += column.width
                }
                let useZebra = (template == .corporate || template == .moderne) && zebra
                drawSplittableRow(rows: rows, columns: columns, values: values, zebraFill: useZebra)
                zebra.toggle()
            }
        }
        drawSectionSubtotal()

        switch template {
        case .minimal, .elegant:
            page.line(from: (marginLeft, y), to: (right, y), color: template == .elegant ? accent : ink, lineWidth: 0.4)
        default:
            break
        }
        y += 14
    }

    /// Dessine une ligne de tableau, en la découpant sur plusieurs pages si elle est trop haute.
    private func drawSplittableRow(rows: [(String, TextStyle)], columns: [TableColumn], values: [(TableColumn, String, Double)]?, zebraFill: Bool) {
        guard let designation = columns.first(where: { $0.kind == .designation }) else { return }
        let designationX = marginLeft + columns.prefix { $0.kind != .designation }.reduce(0) { $0 + $1.width } + cellPadding
        var remaining = rows[...]
        var firstChunk = true
        while !remaining.isEmpty {
            let fullHeight = remaining.reduce(0) { $0 + $1.1.lineHeight } + 2 * rowPadding
            if y + fullHeight > bottomLimit {
                let minimumChunk = (remaining.first?.1.lineHeight ?? 10) * 2 + 2 * rowPadding
                if y + minimumChunk > bottomLimit || fullHeight <= bottomLimit - marginTop - headerRowHeight - 30 {
                    // La ligne tient entière sur une page : on change de page plutôt que de la couper.
                    newPage(first: false)
                    drawTableHeader(columns)
                }
            }
            var chunkHeight = 2 * rowPadding
            var count = 0
            for row in remaining {
                if y + chunkHeight + row.1.lineHeight > bottomLimit && count > 0 { break }
                chunkHeight += row.1.lineHeight
                count += 1
            }
            let chunk = remaining.prefix(count)
            remaining = remaining.dropFirst(count)

            if zebraFill { page.fillRect(x: marginLeft, y: y, width: contentWidth, height: chunkHeight, color: template == .moderne ? wash : accent.tinted(0.93)) }
            var lineTop = y + rowPadding
            for (text, style) in chunk {
                page.lines([text], x: designationX, top: lineTop, width: designation.width - 2 * cellPadding, style: style)
                lineTop += style.lineHeight
            }
            if firstChunk, let values {
                let firstStyle = chunk.first?.1 ?? body
                let baseline = y + rowPadding + firstStyle.size * firstStyle.font.ascent + (firstStyle.lineHeight - firstStyle.size) / 2
                for (column, value, x) in values {
                    let style: TextStyle
                    switch column.kind {
                    case .total: style = TextStyle(font: template == .technique ? fonts.mono : fonts.bodyBold, size: bodySize, color: ink)
                    case .index: style = TextStyle(font: fonts.mono, size: bodySize - 0.5, color: muted)
                    case .unit, .vat, .discount: style = TextStyle(font: fonts.body, size: bodySize - 0.5, color: muted)
                    default: style = TextStyle(font: template == .technique ? fonts.mono : fonts.body, size: bodySize, color: ink)
                    }
                    page.text(value, x: x + cellPadding, baseline: baseline, width: column.width - 2 * cellPadding, style: style, alignment: column.alignment, shrinkToFit: true)
                }
            }
            switch template {
            case .artisan:
                page.strokeRect(x: marginLeft, y: y, width: contentWidth, height: chunkHeight, color: accent.tinted(0.55), lineWidth: 0.5)
                drawVerticalRules(columns, top: y, height: chunkHeight, color: accent.tinted(0.55))
            case .technique:
                page.strokeRect(x: marginLeft, y: y, width: contentWidth, height: chunkHeight, color: hairline, lineWidth: 0.5)
                drawVerticalRules(columns, top: y, height: chunkHeight, color: hairline)
            case .classique, .creatif:
                page.line(from: (marginLeft, y + chunkHeight), to: (right, y + chunkHeight), color: hairline, lineWidth: 0.5)
            default:
                break
            }
            y += chunkHeight
            firstChunk = false
        }
    }
}
