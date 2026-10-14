import Foundation

/// Moyen de paiement déclaré.
public enum PaymentMethod: String, Codable, Sendable, CaseIterable, Identifiable {
    case transfer
    case card
    case cheque
    case cash
    case directDebit
    case other

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .transfer: return "Virement"
        case .card: return "Carte bancaire"
        case .cheque: return "Chèque"
        case .cash: return "Espèces"
        case .directDebit: return "Prélèvement"
        case .other: return "Autre"
        }
    }
}

/// Encaissement déclaré par l'utilisateur sur une facture.
public struct PaymentRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var date: Date
    public var amount: Decimal
    public var method: PaymentMethod
    public var note: String

    public init(id: UUID = UUID(), date: Date, amount: Decimal, method: PaymentMethod = .transfer, note: String = "") {
        self.id = id
        self.date = date
        self.amount = amount
        self.method = method
        self.note = note
    }
}

/// État de règlement d'une facture émise.
public enum PaymentState: String, Codable, Sendable, CaseIterable {
    case unpaid
    case partiallyPaid
    case paid
    case overdue
    /// Entièrement annulée par un ou plusieurs avoirs.
    case cancelled

    public var label: String {
        switch self {
        case .unpaid: return "En attente"
        case .partiallyPaid: return "Partiellement payée"
        case .paid: return "Payée"
        case .overdue: return "En retard"
        case .cancelled: return "Annulée par avoir"
        }
    }
}

/// Erreurs d'enregistrement d'un paiement.
public enum PaymentError: Error, Equatable, LocalizedError {
    case nonPositiveAmount
    case exceedsBalance(balance: Decimal)
    case invoiceNotIssued

    public var errorDescription: String? {
        switch self {
        case .nonPositiveAmount: return "Le montant du paiement doit être positif."
        case .exceedsBalance(let balance): return "Le paiement dépasse le solde restant dû (\(Money.format(balance)))."
        case .invoiceNotIssued: return "Une facture doit être émise avant d'enregistrer un paiement."
        }
    }
}

/// Suivi des encaissements d'une facture.
public struct PaymentLedger: Sendable, Equatable {
    /// Montant dû (net à payer de la facture, avoirs imputés déduits).
    public var amountDue: Decimal
    public var payments: [PaymentRecord]
    /// Montant TTC des avoirs imputés sur cette facture.
    public var creditedAmount: Decimal

    public init(amountDue: Decimal, payments: [PaymentRecord] = [], creditedAmount: Decimal = 0) {
        self.amountDue = amountDue
        self.payments = payments
        self.creditedAmount = creditedAmount
    }

    public var totalPaid: Decimal { payments.reduce(Decimal(0)) { $0 + Money.round($1.amount) } }

    /// Solde restant dû (jamais négatif).
    public var balance: Decimal { max(amountDue - creditedAmount - totalPaid, 0) }

    public func state(dueDate: Date?, today: Date, calendar: Calendar = .devisMinute) -> PaymentState {
        if creditedAmount >= amountDue && amountDue > 0 && totalPaid == 0 { return .cancelled }
        if balance == 0 { return .paid }
        if let dueDate, calendar.startOfDay(for: today) > calendar.startOfDay(for: dueDate) { return .overdue }
        return totalPaid > 0 ? .partiallyPaid : .unpaid
    }

    /// Valide un nouveau paiement avant enregistrement.
    public func validate(_ amount: Decimal) throws {
        let rounded = Money.round(amount)
        guard rounded > 0 else { throw PaymentError.nonPositiveAmount }
        guard rounded <= balance else { throw PaymentError.exceedsBalance(balance: balance) }
    }

    /// Nombre de jours de retard (0 si non échue ou soldée).
    public func daysOverdue(dueDate: Date?, today: Date, calendar: Calendar = .devisMinute) -> Int {
        guard balance > 0, let dueDate else { return 0 }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: dueDate), to: calendar.startOfDay(for: today)).day ?? 0
        return max(days, 0)
    }
}

extension Calendar {
    /// Calendrier grégorien, fuseau Europe/Paris : toutes les dates métier en dépendent.
    public static var devisMinute: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        calendar.locale = Locale(identifier: "fr_FR")
        calendar.firstWeekday = 2
        return calendar
    }
}
