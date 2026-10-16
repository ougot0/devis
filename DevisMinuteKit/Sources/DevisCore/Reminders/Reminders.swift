import Foundation

/// Niveau de relance d'une facture impayée.
public enum ReminderLevel: String, Codable, Sendable, CaseIterable, Identifiable, Comparable {
    /// Rappel courtois, juste après l'échéance.
    case friendly
    /// Relance ferme, quelques semaines plus tard.
    case firm
    /// Mise en demeure de payer : dernière étape avant une procédure de recouvrement.
    case formalNotice

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .friendly: return "Rappel courtois"
        case .firm: return "Relance ferme"
        case .formalNotice: return "Mise en demeure"
        }
    }

    private var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    public static func < (lhs: ReminderLevel, rhs: ReminderLevel) -> Bool { lhs.rank < rhs.rank }
}

/// Relance envoyée au client (déclarée par l'utilisateur après l'envoi de l'e-mail).
public struct ReminderRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var date: Date
    public var level: ReminderLevel

    public init(id: UUID = UUID(), date: Date, level: ReminderLevel) {
        self.id = id
        self.date = date
        self.level = level
    }
}

/// E-mail prêt à envoyer.
public struct EmailDraft: Sendable, Equatable {
    public var recipient: String
    public var subject: String
    public var body: String

    public init(recipient: String, subject: String, body: String) {
        self.recipient = recipient
        self.subject = subject
        self.body = body
    }
}

/// Modèles d'e-mails : envoi d'un document et relances d'impayés.
public enum EmailTemplates {

    /// E-mail d'envoi d'un devis, d'une facture ou d'un avoir (PDF joint par l'application).
    public static func sending(_ document: BusinessDocument, balance: Decimal? = nil) -> EmailDraft {
        let totals = DocumentCalculator.totals(for: document)
        let amount = Money.format(document.kind == .creditNote ? totals.totalTTC : totals.netToPay)
        let taxLabel = document.chargesVAT ? " TTC" : ""
        var paragraphs: [String] = [greeting(document)]
        switch document.kind {
        case .quote:
            var text = "Veuillez trouver ci-joint notre devis n° \(document.number)"
            if !document.title.isEmpty { text += " (\(document.title))" }
            text += " d'un montant de \(amount)\(taxLabel)"
            if let valid = document.validUntil { text += ", valable jusqu'au \(DateFormatting.short(valid))" }
            paragraphs.append(text + ".")
            paragraphs.append("Pour l'accepter, il vous suffit de nous le retourner daté et signé avec la mention « \(QuoteSignature.acceptanceMention) ». Je reste à votre disposition pour toute question.")
        case .creditNote:
            var text = "Veuillez trouver ci-joint l'avoir n° \(document.number) d'un montant de \(amount)\(taxLabel)"
            if !document.correctedInvoiceNumber.isEmpty { text += ", qui se rapporte à la facture n° \(document.correctedInvoiceNumber)" }
            paragraphs.append(text + ".")
        default:
            let due = balance ?? totals.netToPay
            var text = "Veuillez trouver ci-joint la facture n° \(document.number) d'un montant de \(Money.format(due))\(taxLabel)"
            if let date = document.dueDate { text += ", à régler avant le \(DateFormatting.short(date))" }
            paragraphs.append(text + ".")
            paragraphs.append(contentsOf: paymentInstructions(document))
        }
        paragraphs.append(signature(document.seller))
        return EmailDraft(recipient: document.customer.email, subject: "\(subject(for: document)) — \(document.seller.displayName)", body: paragraphs.joined(separator: "\n\n"))
    }

    /// E-mail de relance d'une facture impayée.
    public static func reminder(_ level: ReminderLevel, for document: BusinessDocument, balance: Decimal, daysOverdue: Int) -> EmailDraft {
        let amount = Money.format(balance) + (document.chargesVAT ? " TTC" : "")
        let dueText = document.dueDate.map { "arrivée à échéance le \(DateFormatting.short($0))" } ?? "arrivée à échéance"
        let reference = "la facture n° \(document.number) du \(DateFormatting.short(document.issueDate))"
        var paragraphs: [String] = [greeting(document)]
        let subjectPrefix: String
        switch level {
        case .friendly:
            subjectPrefix = "Rappel"
            paragraphs.append("Sauf erreur de ma part, \(reference), \(dueText), reste à régler pour un montant de \(amount).")
            paragraphs.append("Il s'agit peut-être d'un simple oubli : je vous remercie de bien vouloir procéder au règlement. Si le paiement a été effectué entre-temps, merci de ne pas tenir compte de ce message.")
            paragraphs.append(contentsOf: paymentInstructions(document))
        case .firm:
            subjectPrefix = "Relance"
            paragraphs.append("Malgré mon précédent rappel, \(reference), \(dueText), demeure impayée à ce jour, soit \(daysOverdue) jour\(daysOverdue > 1 ? "s" : "") de retard. Le montant restant dû est de \(amount).")
            paragraphs.append("Je vous demande de procéder au règlement sous 8 jours. \(penaltySentence(document))")
            paragraphs.append(contentsOf: paymentInstructions(document))
        case .formalNotice:
            subjectPrefix = "Mise en demeure de payer"
            paragraphs.append("Malgré mes relances, \(reference), \(dueText), reste impayée, soit \(daysOverdue) jour\(daysOverdue > 1 ? "s" : "") de retard.")
            paragraphs.append("Par la présente, je vous mets en demeure de me régler la somme de \(amount) dans un délai de 8 jours à compter de la réception de ce courrier.")
            paragraphs.append(penaltySentence(document))
            paragraphs.append("À défaut de règlement dans ce délai, je me verrai contraint d'engager une procédure de recouvrement, sans nouvel avis.")
            paragraphs.append(contentsOf: paymentInstructions(document))
        }
        paragraphs.append(signature(document.seller))
        return EmailDraft(recipient: document.customer.email, subject: "\(subjectPrefix) — facture \(document.number) — \(document.seller.displayName)", body: paragraphs.joined(separator: "\n\n"))
    }

    static func subject(for document: BusinessDocument) -> String {
        switch document.kind {
        case .quote: return "Devis \(document.number)"
        case .creditNote: return "Avoir \(document.number)"
        case .depositInvoice: return "Facture d'acompte \(document.number)"
        default: return "Facture \(document.number)"
        }
    }

    static func greeting(_ document: BusinessDocument) -> String {
        let customer = document.customer
        if !customer.contactName.trimmed.isEmpty { return "Bonjour \(customer.contactName.trimmed)," }
        if customer.kind == .individual && !customer.name.trimmed.isEmpty { return "Bonjour \(customer.name.trimmed)," }
        return "Bonjour,"
    }

    static func penaltySentence(_ document: BusinessDocument) -> String {
        var text = "Conformément aux conditions figurant sur la facture, des pénalités de retard sont exigibles"
        if document.isBusinessToBusiness {
            text += ", ainsi que l'indemnité forfaitaire pour frais de recouvrement de 40 € (art. L441-10 du Code de commerce)"
        }
        return text + "."
    }

    static func paymentInstructions(_ document: BusinessDocument) -> [String] {
        var lines: [String] = []
        if let link = document.paymentLink?.trimmed, PaymentLink.isValid(link) {
            lines.append("Vous pouvez régler en ligne par carte bancaire : \(link)")
        }
        let iban = document.seller.iban.trimmed
        if !iban.isEmpty {
            var text = "Virement : IBAN \(iban)"
            if !document.seller.bic.trimmed.isEmpty { text += " — BIC \(document.seller.bic.trimmed)" }
            lines.append(text + ", en indiquant la référence \(document.number).")
        }
        return lines
    }

    static func signature(_ seller: CompanyProfile) -> String {
        var lines = ["Cordialement,"]
        let owner = seller.ownerName.trimmed
        if !owner.isEmpty { lines.append(owner) }
        if owner != seller.displayName { lines.append(seller.displayName) }
        if !seller.phone.trimmed.isEmpty { lines.append(seller.phone.trimmed) }
        return lines.joined(separator: "\n")
    }
}

/// Rappel local programmé sur l'iPhone (échéance ou retard).
public struct DueAlert: Sendable, Equatable {
    public var identifier: String
    public var fireDate: Date
    public var title: String
    public var body: String
    public var documentID: UUID
}

/// Règles de relance.
public enum ReminderPolicy {
    /// Préfixe des identifiants de notifications, pour pouvoir les remplacer en bloc.
    public static let identifierPrefix = "devisminute.due."
    /// iOS conserve au plus 64 notifications locales en attente.
    public static let maximumAlerts = 60

    /// Prochaine relance conseillée, d'après les relances déjà envoyées.
    public static func suggestedLevel(after reminders: [ReminderRecord]) -> ReminderLevel {
        guard let last = reminders.map(\.level).max() else { return .friendly }
        switch last {
        case .friendly: return .firm
        case .firm, .formalNotice: return .formalNotice
        }
    }

    /// Notifications à programmer : le jour de l'échéance, puis 7 jours après si la facture est toujours impayée.
    public static func alerts(for records: [DocumentRecord], now: Date, calendar: Calendar = .devisMinute) -> [DueAlert] {
        var result: [DueAlert] = []
        for record in records where record.isIssuedInvoice && record.document.kind != .creditNote && !record.imported {
            guard let due = record.document.dueDate else { continue }
            let ledger = Accounting.ledger(for: record, in: records)
            guard ledger.balance > 0 else { continue }
            let customer = record.document.customer.name
            let amount = Money.format(ledger.balance)
            let morning = { (date: Date) -> Date? in calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date) }
            if let fire = morning(due), fire > now {
                result.append(DueAlert(identifier: "\(identifierPrefix)\(record.id.uuidString).due", fireDate: fire,
                                       title: "Échéance aujourd'hui",
                                       body: "Facture \(record.document.number) — \(customer) : \(amount) à encaisser.",
                                       documentID: record.id))
            }
            if let later = calendar.date(byAdding: .day, value: 7, to: due), let fire = morning(later), fire > now {
                result.append(DueAlert(identifier: "\(identifierPrefix)\(record.id.uuidString).late", fireDate: fire,
                                       title: "Facture en retard",
                                       body: "\(customer) n'a pas réglé la facture \(record.document.number) (\(amount)). Envoyez une relance en une touche.",
                                       documentID: record.id))
            }
        }
        return Array(result.sorted { $0.fireDate < $1.fireDate }.prefix(maximumAlerts))
    }
}
