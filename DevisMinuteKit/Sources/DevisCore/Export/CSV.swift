import Foundation

/// Export et import CSV compatibles avec Excel et Numbers en français :
/// séparateur « ; », virgule décimale, UTF-8 avec BOM, champs entre guillemets si nécessaire.
public enum CSV {
    public static let separator: Character = ";"

    public static func escape(_ field: String) -> String {
        var value = field
        // Neutralise l'injection de formules à l'ouverture dans un tableur.
        if let first = value.first, ["=", "+", "-", "@"].contains(first), Decimal(string: value.replacingOccurrences(of: ",", with: ".")) == nil {
            value = "'" + value
        }
        if value.contains(separator) || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    public static func amount(_ value: Decimal) -> String {
        Money.plainString(value).replacingOccurrences(of: ".", with: ",")
    }

    public static func make(header: [String], rows: [[String]]) -> Data {
        var text = header.map(escape).joined(separator: String(separator)) + "\r\n"
        for row in rows { text += row.map(escape).joined(separator: String(separator)) + "\r\n" }
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(text.utf8))
        return data
    }

    /// Analyse un CSV (séparateur « ; » ou « , » détecté automatiquement, guillemets RFC 4180).
    public static func parse(_ data: Data) -> [[String]] {
        var text = String(decoding: data, as: UTF8.self)
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let firstLine = text.prefix { $0 != "\n" && $0 != "\r" }
        let delimiter: Character = firstLine.filter { $0 == ";" }.count >= firstLine.filter { $0 == "," }.count ? ";" : ","
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = Array(text)
        iterator.append("\n")
        var index = 0
        while index < iterator.count {
            let character = iterator[index]
            if inQuotes {
                if character == "\"" {
                    if index + 1 < iterator.count && iterator[index + 1] == "\"" {
                        field.append("\"")
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else if character == "\"" {
                inQuotes = true
            } else if character == delimiter {
                row.append(field)
                field = ""
            } else if character == "\n" || character == "\r" || character == "\r\n" {
                if character == "\r" && index + 1 < iterator.count && iterator[index + 1] == "\n" { index += 1 }
                row.append(field)
                if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                row = []
                field = ""
            } else {
                field.append(character)
            }
            index += 1
        }
        return rows
    }
}

/// Exports tabulaires.
public enum CSVExporter {

    public static func invoices(_ records: [DocumentRecord], today: Date = Date()) -> Data {
        let header = ["Type", "Numéro", "Date d'émission", "Échéance", "Client", "SIREN client", "Total HT", "TVA", "Total TTC", "Acomptes déduits", "Net à payer", "Encaissé", "Avoirs", "Solde", "État", "Devis d'origine", "Facture corrigée"]
        let rows = records.filter(\.isIssuedInvoice).sorted { $0.document.issueDate < $1.document.issueDate }.map { record -> [String] in
            let document = record.document
            let totals = DocumentCalculator.totals(for: document)
            let ledger = Accounting.ledger(for: record, in: records)
            let state = document.kind == .creditNote ? "—" : ledger.state(dueDate: document.dueDate, today: today).label
            return [document.kind.title, document.number, DateFormatting.short(document.issueDate), document.dueDate.map(DateFormatting.short) ?? "",
                    document.customer.name, document.customer.siren, CSV.amount(totals.totalHT), CSV.amount(totals.totalVAT), CSV.amount(totals.totalTTC),
                    CSV.amount(totals.depositsDeductedTTC), CSV.amount(totals.netToPay), CSV.amount(ledger.totalPaid), CSV.amount(ledger.creditedAmount),
                    document.kind == .creditNote ? "" : CSV.amount(ledger.balance), state, document.sourceQuoteNumber, document.correctedInvoiceNumber]
        }
        return CSV.make(header: header, rows: rows)
    }

    /// Ventilation de la TVA par facture et par taux (aide à la déclaration, à faire vérifier).
    public static func vatBreakdown(_ records: [DocumentRecord]) -> Data {
        let header = ["Numéro", "Date", "Type", "Taux TVA", "Base HT", "TVA"]
        var rows: [[String]] = []
        for record in records.filter(\.isIssuedInvoice).sorted(by: { $0.document.issueDate < $1.document.issueDate }) {
            let totals = DocumentCalculator.totals(for: record.document)
            let sign: Decimal = record.document.kind == .creditNote ? -1 : 1
            for bucket in totals.vatBuckets {
                rows.append([record.document.number, DateFormatting.short(record.document.issueDate), record.document.kind.title,
                             Money.formatQuantity(bucket.rate), CSV.amount(sign * bucket.baseHT), CSV.amount(sign * bucket.vatAmount)])
            }
        }
        return CSV.make(header: header, rows: rows)
    }

    public static func quotes(_ records: [DocumentRecord], today: Date = Date()) -> Data {
        let header = ["Numéro", "Date", "Valable jusqu'au", "Client", "Objet", "Total HT", "Total TTC", "État"]
        let rows = records.filter { $0.document.kind == .quote }.sorted { $0.document.issueDate < $1.document.issueDate }.map { record -> [String] in
            let totals = DocumentCalculator.totals(for: record.document)
            let status = QuoteLifecycle.effectiveStatus(record.quoteStatus ?? .draft, validUntil: record.document.validUntil, today: today)
            return [record.document.number, DateFormatting.short(record.document.issueDate), record.document.validUntil.map(DateFormatting.short) ?? "",
                    record.document.customer.name, record.document.title, CSV.amount(totals.totalHT), CSV.amount(totals.totalTTC), status.label]
        }
        return CSV.make(header: header, rows: rows)
    }

    public static func payments(_ records: [DocumentRecord]) -> Data {
        let header = ["Date", "Facture", "Client", "Montant", "Moyen", "Note"]
        var rows: [(Date, [String])] = []
        for record in records where record.isIssuedInvoice {
            for payment in record.payments {
                rows.append((payment.date, [DateFormatting.short(payment.date), record.document.number, record.document.customer.name, CSV.amount(payment.amount), payment.method.label, payment.note]))
            }
        }
        return CSV.make(header: header, rows: rows.sorted { $0.0 < $1.0 }.map(\.1))
    }

    public static let customerHeader = ["Type", "Nom", "Contact", "Adresse", "Complément", "Code postal", "Ville", "Pays", "Email", "Téléphone", "SIREN", "TVA", "Notes"]

    public static func customers(_ customers: [CustomerRecord]) -> Data {
        let rows = customers.map { record -> [String] in
            let c = record.snapshot
            return [c.kind.label, c.name, c.contactName, c.address.line1, c.address.line2, c.address.postalCode, c.address.city, c.address.country, c.email, c.phone, c.siren, c.vatNumber, record.notes]
        }
        return CSV.make(header: customerHeader, rows: rows)
    }

    public static let catalogHeader = ["Nom", "Description", "Catégorie", "Prix", "Prix TTC (oui/non)", "Taux TVA", "Unité", "Coût de revient", "Nature (bien/service)"]

    public static func catalog(_ items: [CatalogItem]) -> Data {
        let rows = items.map { item -> [String] in
            [item.name, item.details, item.category, CSV.amount(item.price), item.priceIncludesVAT ? "oui" : "non", Money.formatQuantity(item.vatRate), item.unit,
             item.unitCost.map(CSV.amount) ?? "", item.nature == .goods ? "bien" : "service"]
        }
        return CSV.make(header: catalogHeader, rows: rows)
    }

    public static let expensesHeader = ["Date", "Fournisseur", "Libellé", "Catégorie", "Montant TTC", "TVA", "Montant HT", "Moyen de paiement", "Justificatif", "Notes"]

    public static func expenses(_ items: [ExpenseRecord]) -> Data {
        let rows = items.sorted { $0.date < $1.date }.map { item -> [String] in
            [DateFormatting.short(item.date), item.supplier, item.label, item.category.label, CSV.amount(item.amountTTC), CSV.amount(item.vatAmount),
             CSV.amount(item.amountHT), item.paymentMethod.label, item.receiptJPEG == nil ? "non" : "oui", item.notes]
        }
        return CSV.make(header: expensesHeader, rows: rows)
    }
}

/// Import des données compatibles (clients, catalogue) à partir de CSV.
public enum CSVImporter {
    public struct Result<Item> {
        public var items: [Item]
        /// Lignes ignorées, avec leur numéro (1 = en-tête).
        public var skipped: [(line: Int, reason: String)]
    }

    private static func column(_ header: [String], _ names: [String]) -> Int? {
        let normalized = header.map { $0.trimmed.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_FR")) }
        for name in names {
            let target = name.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_FR"))
            if let index = normalized.firstIndex(where: { $0 == target || $0.hasPrefix(target) }) { return index }
        }
        return nil
    }

    public static func customers(_ data: Data) -> Result<CustomerRecord> {
        let rows = CSV.parse(data)
        guard let header = rows.first, let nameIndex = column(header, ["nom", "raison sociale", "name", "société", "societe"]) else {
            return Result(items: [], skipped: [(1, "Colonne « Nom » introuvable")])
        }
        func value(_ row: [String], _ names: [String]) -> String {
            guard let index = column(header, names), index < row.count else { return "" }
            return row[index].trimmed
        }
        var items: [CustomerRecord] = []
        var skipped: [(Int, String)] = []
        for (offset, row) in rows.dropFirst().enumerated() {
            let name = nameIndex < row.count ? row[nameIndex].trimmed : ""
            guard !name.isEmpty else { skipped.append((offset + 2, "Nom vide")); continue }
            let typeText = value(row, ["type"]).lowercased()
            let kind: CustomerKind = typeText.hasPrefix("part") || typeText == "individual" ? .individual : (typeText.contains("public") ? .publicEntity : .business)
            let snapshot = CustomerSnapshot(
                kind: kind, name: name, contactName: value(row, ["contact"]),
                address: PostalAddress(line1: value(row, ["adresse", "address"]), line2: value(row, ["complément", "complement"]), postalCode: value(row, ["code postal", "cp", "postal"]), city: value(row, ["ville", "city"]), country: value(row, ["pays", "country"]).isEmpty ? "France" : value(row, ["pays", "country"])),
                email: value(row, ["email", "e-mail", "courriel"]), phone: value(row, ["téléphone", "telephone", "tel", "phone"]),
                siren: value(row, ["siren", "siret"]).filter(\.isNumber), vatNumber: value(row, ["tva", "vat"]))
            items.append(CustomerRecord(snapshot: snapshot, notes: value(row, ["notes", "note"])))
        }
        return Result(items: items, skipped: skipped)
    }

    public static func catalog(_ data: Data) -> Result<CatalogItem> {
        let rows = CSV.parse(data)
        guard let header = rows.first, let nameIndex = column(header, ["nom", "désignation", "designation", "name"]), let priceIndex = column(header, ["prix", "price"]) else {
            return Result(items: [], skipped: [(1, "Colonnes « Nom » et « Prix » requises")])
        }
        func value(_ row: [String], _ names: [String]) -> String {
            guard let index = column(header, names), index < row.count else { return "" }
            return row[index].trimmed
        }
        var items: [CatalogItem] = []
        var skipped: [(Int, String)] = []
        for (offset, row) in rows.dropFirst().enumerated() {
            let line = offset + 2
            let name = nameIndex < row.count ? row[nameIndex].trimmed : ""
            guard !name.isEmpty else { skipped.append((line, "Nom vide")); continue }
            guard priceIndex < row.count, let price = Money.parse(row[priceIndex]), price >= 0 else { skipped.append((line, "Prix invalide")); continue }
            let vatText = value(row, ["taux tva", "tva", "vat"])
            let vat = vatText.isEmpty ? Decimal(20) : (Money.parse(vatText) ?? -1)
            guard vat >= 0, vat < 100 else { skipped.append((line, "Taux de TVA invalide")); continue }
            let ttcText = value(row, ["prix ttc", "ttc"]).lowercased()
            let costText = value(row, ["coût", "cout", "cost"])
            items.append(CatalogItem(
                name: name, details: value(row, ["description", "détails", "details"]), category: value(row, ["catégorie", "categorie", "category"]),
                price: price, priceIncludesVAT: ["oui", "yes", "1", "ttc", "vrai", "true"].contains(ttcText), vatRate: vat,
                unit: value(row, ["unité", "unite", "unit"]).isEmpty ? "u" : value(row, ["unité", "unite", "unit"]),
                unitCost: costText.isEmpty ? nil : Money.parse(costText),
                nature: value(row, ["nature"]).lowercased().hasPrefix("bien") ? .goods : .services))
        }
        return Result(items: items, skipped: skipped)
    }
}
