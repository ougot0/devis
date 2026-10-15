import Foundation

/// Lien de paiement en ligne (Stripe Payment Links, SumUp, PayPal.me…).
public enum PaymentLink {
    /// Accepte uniquement une adresse `https://` complète, sans espace.
    public static func isValid(_ text: String) -> Bool {
        let value = text.trimmed
        guard !value.isEmpty, !value.contains(where: \.isWhitespace),
              let url = URL(string: value), url.scheme?.lowercased() == "https",
              let host = url.host, host.contains(".") else { return false }
        return true
    }

    /// Nom du service reconnu, pour l'affichage (« Stripe », « SumUp »…).
    public static func providerName(_ text: String) -> String? {
        guard let host = URL(string: text.trimmed)?.host?.lowercased() else { return nil }
        if host.hasSuffix("stripe.com") { return "Stripe" }
        if host.hasSuffix("sumup.com") || host.hasSuffix("sumup.link") { return "SumUp" }
        if host.hasSuffix("paypal.me") || host.hasSuffix("paypal.com") { return "PayPal" }
        if host.hasSuffix("lydia-app.com") || host.hasSuffix("lydia.me") { return "Lydia" }
        if host.hasSuffix("qonto.com") { return "Qonto" }
        return nil
    }
}

/// Import des factures émises avec un autre logiciel, sous forme d'archive consultable.
///
/// Chaque facture importée devient un document émis, marqué « importé », sans sceau :
/// elle alimente l'historique des clients, les statistiques et le suivi des paiements,
/// mais le document d'origine (PDF ou papier) reste la référence légale.
///
/// Colonnes reconnues (en-tête, ordre libre, séparateur « ; » ou « , ») :
/// Numéro*, Date*, Client*, Total HT, TVA, Total TTC (au moins deux des trois montants,
/// ou TTC seul en franchise de TVA), Payé, Échéance, Type (facture / avoir).
public enum HistoryImporter {

    public struct Result {
        public var records: [DocumentRecord]
        /// Clients à créer (ceux qui n'existent pas encore dans le répertoire).
        public var newCustomers: [CustomerRecord]
        public var skipped: [(line: Int, reason: String)]
    }

    public static func invoices(_ data: Data, seller: CompanyProfile, existingCustomers: [CustomerRecord], existingNumbers: Set<String>, now: Date = Date()) -> Result {
        let rows = CSV.parse(data)
        var result = Result(records: [], newCustomers: [], skipped: [])
        guard let header = rows.first else {
            result.skipped.append((1, "Fichier vide"))
            return result
        }
        let normalized = header.map { $0.trimmed.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_FR")) }
        func column(_ names: [String]) -> Int? {
            for name in names {
                if let index = normalized.firstIndex(where: { $0 == name || $0.hasPrefix(name) }) { return index }
            }
            return nil
        }
        guard let numberColumn = column(["numero", "n°", "no", "number", "facture"]),
              let dateColumn = column(["date d'emission", "date emission", "date"]),
              let customerColumn = column(["client", "customer", "nom"]) else {
            result.skipped.append((1, "Colonnes « Numéro », « Date » et « Client » obligatoires"))
            return result
        }
        let htColumn = column(["total ht", "montant ht", "ht"])
        let vatColumn = column(["tva", "montant tva", "vat"])
        let ttcColumn = column(["total ttc", "montant ttc", "ttc", "total"])
        let paidColumn = column(["paye", "montant paye", "regle", "encaisse", "paid"])
        let dueColumn = column(["echeance", "date d'echeance", "due"])
        let typeColumn = column(["type"])

        var customers = existingCustomers
        var seen = existingNumbers
        let calendar = Calendar.devisMinute

        for (offset, row) in rows.dropFirst().enumerated() {
            let line = offset + 2
            func value(_ index: Int?) -> String {
                guard let index, index < row.count else { return "" }
                return row[index].trimmed
            }
            func amount(_ index: Int?) -> Decimal? {
                let text = value(index)
                return text.isEmpty ? nil : Money.parse(text).map { Money.round($0) }
            }
            let number = value(numberColumn)
            guard !number.isEmpty else { result.skipped.append((line, "Numéro vide")); continue }
            guard !seen.contains(number) else { result.skipped.append((line, "Numéro \(number) déjà présent")); continue }
            guard let date = parseDate(value(dateColumn)) else { result.skipped.append((line, "Date illisible (format attendu JJ/MM/AAAA)")); continue }
            guard date <= now else { result.skipped.append((line, "Date dans le futur")); continue }
            let customerName = value(customerColumn)
            guard !customerName.isEmpty else { result.skipped.append((line, "Client vide")); continue }

            // Montants : HT, TVA, TTC — deux suffisent ; TTC seul = sans TVA.
            var ht = amount(htColumn), vat = amount(vatColumn), ttc = amount(ttcColumn)
            if ht == nil, let ttc, let vat { ht = ttc - vat }
            if vat == nil, let ht, let ttc { vat = ttc - ht }
            if ht == nil, vat == nil, let ttc { ht = ttc; vat = 0 }
            if vat == nil, ht != nil { vat = 0 }
            guard let totalHT = ht, let totalVAT = vat, totalHT > 0, totalVAT >= 0 else {
                result.skipped.append((line, "Montants manquants ou invalides"))
                continue
            }
            if let ttc, ttc != totalHT + totalVAT {
                result.skipped.append((line, "Total TTC incohérent (HT + TVA ≠ TTC)"))
                continue
            }

            let typeText = value(typeColumn).lowercased()
            let isCredit = typeText.hasPrefix("avoir") || (typeText.isEmpty && number.uppercased().hasPrefix("AV"))
            let customerID: UUID
            let snapshot: CustomerSnapshot
            if let existing = customers.first(where: { $0.snapshot.name.lowercased() == customerName.lowercased() }) {
                customerID = existing.id
                snapshot = existing.snapshot
            } else {
                let created = CustomerRecord(snapshot: CustomerSnapshot(kind: .business, name: customerName), notes: "Créé lors de l'import de l'historique.")
                customers.append(created)
                result.newCustomers.append(created)
                customerID = created.id
                snapshot = created.snapshot
            }

            // Une ligne unique dont le taux reproduit exactement la TVA d'origine.
            let rate = totalVAT == 0 ? Decimal(0) : Money.round(totalVAT * 100 / totalHT, scale: 6)
            let importedLine = DocumentLine(designation: isCredit ? "Avoir importé (historique)" : "Facture importée (historique)", quantity: 1, unit: "forfait", unitPriceHT: totalHT, vatRate: rate)
            var issuer = seller
            if totalVAT > 0 && issuer.vatRegime == .franchise { issuer.vatRegime = .standard }
            let due = parseDate(value(dueColumn)) ?? calendar.date(byAdding: .day, value: 30, to: date)
            let document = BusinessDocument(
                kind: isCredit ? .creditNote : .invoice,
                number: number,
                issueDate: date,
                serviceDate: date,
                dueDate: isCredit ? nil : due,
                title: "Importée d'un autre logiciel",
                seller: issuer,
                customer: snapshot,
                lines: [importedLine],
                notes: "Facture importée : le document d'origine fait foi."
            )
            // Contrôle : le moteur doit retrouver exactement les montants d'origine.
            let totals = DocumentCalculator.totals(for: document)
            guard totals.totalHT == totalHT, totals.totalVAT == totalVAT else {
                result.skipped.append((line, "Montants non reproductibles"))
                continue
            }
            var payments: [PaymentRecord] = []
            if !isCredit, let paid = amount(paidColumn), paid > 0 {
                payments.append(PaymentRecord(date: min(due ?? date, now), amount: min(paid, totals.totalTTC), method: .other, note: "Importé"))
            }
            var record = DocumentRecord(document: document, invoiceStatus: .issued, payments: payments, customerID: customerID, createdAt: now, updatedAt: now, issuedAt: date)
            record.isImported = true
            result.records.append(record)
            seen.insert(number)
        }
        return result
    }

    /// Dates acceptées : JJ/MM/AAAA, JJ-MM-AAAA, JJ.MM.AAAA, AAAA-MM-JJ (midi, heure de Paris).
    public static func parseDate(_ text: String) -> Date? {
        let value = text.trimmed
        guard !value.isEmpty else { return nil }
        let parts = value.split(whereSeparator: { "/-.".contains($0) }).map(String.init)
        guard parts.count == 3, let a = Int(parts[0]), let b = Int(parts[1]), let c = Int(parts[2]) else { return nil }
        var components = DateComponents()
        if parts[0].count == 4 {
            components.year = a; components.month = b; components.day = c
        } else {
            components.day = a; components.month = b; components.year = c < 100 ? 2000 + c : c
        }
        components.hour = 12
        guard let month = components.month, (1...12).contains(month), let day = components.day, (1...31).contains(day) else { return nil }
        let calendar = Calendar.devisMinute
        guard let date = calendar.date(from: components), calendar.component(.day, from: date) == day else { return nil }
        return date
    }
}
