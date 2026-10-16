import Foundation

/// Résumé écrit par l'application pour les widgets de l'écran d'accueil (fichier JSON partagé).
/// Le widget ne lit jamais la base de données : il affiche seulement ce résumé.
public struct WidgetSnapshot: Codable, Sendable, Equatable {
    public struct Due: Codable, Sendable, Equatable, Identifiable {
        public var id: UUID
        public var customer: String
        public var number: String
        public var amount: Decimal
        public var dueDate: Date
        public var isOverdue: Bool
    }

    public var generatedAt: Date
    public var companyName: String
    public var outstanding: Decimal
    public var unpaidCount: Int
    public var overdueAmount: Decimal
    public var overdueCount: Int
    public var monthInvoicedHT: Decimal
    public var monthCollected: Decimal
    public var monthGoal: Decimal?
    /// Factures à encaisser, les plus urgentes d'abord (3 au plus).
    public var upcoming: [Due]
    /// Verrouillage Face ID actif : le widget masque les montants.
    public var isPrivate: Bool

    public static let fileName = "widget-snapshot.json"

    public var goalProgress: Double? {
        guard let monthGoal, monthGoal > 0 else { return nil }
        return NSDecimalNumber(decimal: monthInvoicedHT / monthGoal).doubleValue
    }

    /// Exemple affiché dans la galerie des widgets.
    public static let placeholder = WidgetSnapshot(
        generatedAt: Date(), companyName: "Mon entreprise", outstanding: Decimal.exact("8290.40"), unpaidCount: 4,
        overdueAmount: 2996, overdueCount: 2, monthInvoicedHT: 6450, monthCollected: Decimal.exact("4120.50"), monthGoal: 9000,
        upcoming: [
            Due(id: UUID(), customer: "Boulangerie Petit", number: "F-2026-0041", amount: 2996, dueDate: Date(), isOverdue: true),
            Due(id: UUID(), customer: "Hôtel des Brotteaux", number: "F-2026-0044", amount: Decimal.exact("3249.60"), dueDate: Date().addingTimeInterval(86_400 * 9), isOverdue: false),
        ],
        isPrivate: false
    )

    public static func make(records: [DocumentRecord], companyName: String, monthGoal: Decimal?, isPrivate: Bool, today: Date, calendar: Calendar = .devisMinute) -> WidgetSnapshot {
        let month = calendar.dateInterval(of: .month, for: today)
        var outstanding: Decimal = 0
        var overdueAmount: Decimal = 0
        var unpaid = 0
        var overdue = 0
        var dues: [Due] = []
        var invoicedHT: Decimal = 0
        var collected: Decimal = 0
        for record in records where record.isIssuedInvoice {
            if let month, month.contains(record.document.issueDate) { invoicedHT += Accounting.invoicedHT(record) }
            guard record.document.kind != .creditNote else { continue }
            if let month {
                collected += record.payments.filter { month.contains($0.date) }.reduce(Decimal(0)) { $0 + $1.amount }
            }
            let ledger = Accounting.ledger(for: record, in: records)
            guard ledger.balance > 0 else { continue }
            let isOverdue = ledger.state(dueDate: record.document.dueDate, today: today, calendar: calendar) == .overdue
            outstanding += ledger.balance
            unpaid += 1
            if isOverdue {
                overdueAmount += ledger.balance
                overdue += 1
            }
            dues.append(Due(id: record.id, customer: record.document.customer.name, number: record.document.number, amount: ledger.balance,
                            dueDate: record.document.dueDate ?? record.document.issueDate, isOverdue: isOverdue))
        }
        let upcoming = dues.sorted { ($0.isOverdue ? 0 : 1, $0.dueDate) < ($1.isOverdue ? 0 : 1, $1.dueDate) }
        return WidgetSnapshot(generatedAt: today, companyName: companyName, outstanding: outstanding, unpaidCount: unpaid,
                              overdueAmount: overdueAmount, overdueCount: overdue, monthInvoicedHT: invoicedHT, monthCollected: collected,
                              monthGoal: monthGoal, upcoming: Array(upcoming.prefix(3)), isPrivate: isPrivate)
    }
}
