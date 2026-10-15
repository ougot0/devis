import Foundation

/// États d'un devis.
public enum QuoteStatus: String, Codable, Sendable, CaseIterable, Identifiable {
    case draft
    case sent
    case accepted
    case refused
    case expired

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .draft: return "Brouillon"
        case .sent: return "Envoyé"
        case .accepted: return "Accepté"
        case .refused: return "Refusé"
        case .expired: return "Expiré"
        }
    }

    /// Un devis accepté ou refusé n'est plus modifiable : il faut le dupliquer.
    public var isEditable: Bool { self == .draft || self == .sent }
}

/// États d'une facture, d'une facture d'acompte ou d'un avoir.
public enum InvoiceStatus: String, Codable, Sendable, CaseIterable {
    /// Brouillon : modifiable, sans numéro, sans valeur légale.
    case draft
    /// Émise : numérotée, scellée, non modifiable. Toute correction passe par un avoir.
    case issued

    public var label: String { self == .draft ? "Brouillon" : "Émise" }
}

public enum LifecycleError: Error, Equatable, LocalizedError {
    case transitionNotAllowed(from: String, to: String)
    case documentLocked
    case quoteNotAccepted
    case emptyDocument

    public var errorDescription: String? {
        switch self {
        case .transitionNotAllowed(let from, let to):
            return "Impossible de passer de « \(from) » à « \(to) »."
        case .documentLocked:
            return "Ce document est émis : il ne peut plus être modifié. Créez un avoir pour le corriger."
        case .quoteNotAccepted:
            return "Seul un devis envoyé ou accepté peut être converti en facture."
        case .emptyDocument:
            return "Le document ne contient aucune ligne chiffrée."
        }
    }
}

/// Règles de transition des devis.
public enum QuoteLifecycle {
    public static func allowedTransitions(from status: QuoteStatus) -> Set<QuoteStatus> {
        switch status {
        case .draft: return [.sent]
        case .sent: return [.draft, .accepted, .refused, .expired]
        case .expired: return [.sent, .accepted, .refused]
        case .accepted: return []
        case .refused: return []
        }
    }

    public static func transition(from status: QuoteStatus, to target: QuoteStatus) throws -> QuoteStatus {
        guard allowedTransitions(from: status).contains(target) else {
            throw LifecycleError.transitionNotAllowed(from: status.label, to: target.label)
        }
        return target
    }

    /// Statut affiché : un devis envoyé dont la date de validité est dépassée apparaît « Expiré ».
    public static func effectiveStatus(_ status: QuoteStatus, validUntil: Date?, today: Date, calendar: Calendar = .devisMinute) -> QuoteStatus {
        guard status == .sent, let validUntil else { return status }
        return calendar.startOfDay(for: today) > calendar.startOfDay(for: validUntil) ? .expired : status
    }

    /// Un devis peut être signé par le client tant qu'il n'est ni accepté ni refusé
    /// (y compris un brouillon signé sur place, ou un devis expiré que le client accepte quand même).
    public static func canSign(_ status: QuoteStatus) -> Bool {
        status == .draft || status == .sent || status == .expired
    }

    public static func canConvertToInvoice(_ status: QuoteStatus) -> Bool {
        status == .sent || status == .accepted
    }
}

/// Règles d'émission des factures.
public enum InvoiceLifecycle {
    /// Vérifie qu'une facture peut être modifiée.
    public static func ensureEditable(_ status: InvoiceStatus) throws {
        if status == .issued { throw LifecycleError.documentLocked }
    }

    /// Vérifie qu'une facture peut être émise.
    public static func ensureIssuable(_ document: BusinessDocument, status: InvoiceStatus) throws {
        guard status == .draft else { throw LifecycleError.transitionNotAllowed(from: status.label, to: InvoiceStatus.issued.label) }
        guard !document.itemLines.isEmpty else { throw LifecycleError.emptyDocument }
    }
}

/// Construction des documents dérivés (conversion, duplication, avoir).
public enum DocumentFactory {

    /// Nouvelle facture (brouillon) à partir d'un devis. Le devis n'est pas modifié.
    public static func invoice(from quote: BusinessDocument, seller: CompanyProfile, issueDate: Date, deposits: [DepositDeduction] = [], calendar: Calendar = .devisMinute) -> BusinessDocument {
        var invoice = quote
        invoice.id = UUID()
        invoice.kind = .invoice
        invoice.number = ""
        invoice.issueDate = issueDate
        invoice.serviceDate = issueDate
        invoice.validUntil = nil
        invoice.dueDate = calendar.date(byAdding: .day, value: seller.paymentTermsDays, to: issueDate)
        invoice.seller = seller
        invoice.sourceQuoteNumber = quote.number
        invoice.depositRequest = .none
        invoice.depositDeductions = deposits
        invoice.lines = quote.lines.map { $0.duplicated() }
        return invoice
    }

    /// Facture d'acompte (brouillon) à partir d'un devis.
    public static func depositInvoice(from quote: BusinessDocument, seller: CompanyProfile, amountTTC: Decimal, issueDate: Date, calendar: Calendar = .devisMinute) -> BusinessDocument {
        var invoice = invoice(from: quote, seller: seller, issueDate: issueDate, calendar: calendar)
        invoice.kind = .depositInvoice
        invoice.globalDiscount = .none
        invoice.depositDeductions = []
        invoice.lines = DocumentCalculator.depositLines(for: quote, depositTTC: amountTTC)
        invoice.title = quote.title.isEmpty ? "" : "Acompte — \(quote.title)"
        return invoice
    }

    /// Copie d'un devis existant, remise à l'état de brouillon (nouveau numéro à attribuer).
    public static func duplicate(_ document: BusinessDocument, issueDate: Date, seller: CompanyProfile, calendar: Calendar = .devisMinute) -> BusinessDocument {
        var copy = document
        copy.id = UUID()
        copy.number = ""
        copy.issueDate = issueDate
        copy.seller = seller
        copy.lines = document.lines.map { $0.duplicated() }
        copy.depositDeductions = []
        copy.correctedInvoiceNumber = ""
        if document.kind == .quote {
            copy.validUntil = calendar.date(byAdding: .day, value: seller.quoteDefaultValidityDays, to: issueDate)
        } else {
            copy.dueDate = calendar.date(byAdding: .day, value: seller.paymentTermsDays, to: issueDate)
            copy.serviceDate = issueDate
        }
        return copy
    }

    /// Avoir total : reprend toutes les lignes de la facture d'origine.
    public static func fullCreditNote(for invoice: BusinessDocument, issueDate: Date, reason: String) -> BusinessDocument {
        var credit = invoice
        credit.id = UUID()
        credit.kind = .creditNote
        credit.number = ""
        credit.issueDate = issueDate
        credit.serviceDate = invoice.serviceDate
        credit.dueDate = nil
        credit.validUntil = nil
        credit.correctedInvoiceNumber = invoice.number
        credit.depositDeductions = []
        credit.depositRequest = .none
        credit.lines = invoice.lines.map { $0.duplicated() }
        credit.notes = reason
        credit.title = "Avoir sur facture n° \(invoice.number)"
        return credit
    }

    /// Avoir partiel : une ligne de réduction à un taux de TVA donné.
    public static func partialCreditNote(for invoice: BusinessDocument, issueDate: Date, amountHT: Decimal, vatRate: Decimal, reason: String) -> BusinessDocument {
        var credit = fullCreditNote(for: invoice, issueDate: issueDate, reason: reason)
        credit.globalDiscount = .none
        credit.lines = [DocumentLine(
            designation: reason.isEmpty ? "Réduction sur facture n° \(invoice.number)" : reason,
            quantity: 1,
            unit: "forfait",
            unitPriceHT: Money.round(amountHT),
            vatRate: vatRate,
            nature: invoice.itemLines.first?.nature ?? .services
        )]
        return credit
    }
}
