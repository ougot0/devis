import Foundation

/// Point d'une série mensuelle.
public struct MonthlyAmount: Sendable, Equatable, Identifiable {
    /// Premier jour du mois.
    public var month: Date
    public var amount: Decimal
    public var id: Date { month }
}

public struct RankedAmount: Sendable, Equatable, Identifiable {
    public var label: String
    public var amount: Decimal
    public var count: Int
    public var id: String { label }
}

/// Indicateurs du tableau de bord. Tous calculés à partir des données enregistrées :
/// aucune valeur n'est estimée ou inventée.
public struct DashboardSummary: Sendable, Equatable {
    /// Devis envoyés, non expirés, en attente de réponse (TTC).
    public var pendingQuotesTTC: Decimal
    public var pendingQuotesCount: Int
    /// Facturé (factures et acomptes émis, avoirs déduits), TTC, sur la période.
    public var invoicedTTC: Decimal
    /// Encaissements déclarés sur la période.
    public var collectedTTC: Decimal
    /// Restant dû sur toutes les factures émises.
    public var outstandingTTC: Decimal
    public var unpaidInvoicesCount: Int
    public var overdueTTC: Decimal
    public var overdueInvoicesCount: Int
    public var customerCount: Int
}

/// Statistiques détaillées.
public struct StatisticsReport: Sendable, Equatable {
    public var invoicedHTByMonth: [MonthlyAmount]
    public var collectedByMonth: [MonthlyAmount]
    public var byCustomer: [RankedAmount]
    public var topItems: [RankedAmount]
    public var acceptedQuotes: Int
    public var refusedQuotes: Int
    public var expiredQuotes: Int
    public var pendingQuotes: Int
    /// Taux de transformation (acceptés / devis ayant reçu une réponse ou expirés).
    /// `nil` tant que moins de `minimumDecidedQuotes` devis sont concernés.
    public var conversionRate: Decimal?
    public var totalInvoicedHT: Decimal
    public var totalCollected: Decimal
}

/// Cumul montant + nombre d'occurrences.
struct Tally {
    var amount = Decimal(0)
    var count = 0

    mutating func add(_ value: Decimal, counted: Bool) {
        amount += value
        if counted { count += 1 }
    }
}

public enum StatisticsEngine {
    public static let minimumDecidedQuotes = 5

    public static func dashboard(records: [DocumentRecord], customerCount: Int, period: DateInterval?, today: Date, calendar: Calendar = .devisMinute) -> DashboardSummary {
        func inPeriod(_ date: Date) -> Bool { period?.contains(date) ?? true }
        let zero = Decimal(0)
        var summary = DashboardSummary(pendingQuotesTTC: zero, pendingQuotesCount: 0, invoicedTTC: zero, collectedTTC: zero, outstandingTTC: zero, unpaidInvoicesCount: 0, overdueTTC: zero, overdueInvoicesCount: 0, customerCount: customerCount)
        for record in records {
            let document = record.document
            if document.kind == .quote {
                let status = QuoteLifecycle.effectiveStatus(record.quoteStatus ?? .draft, validUntil: document.validUntil, today: today, calendar: calendar)
                if status == .sent {
                    summary.pendingQuotesTTC += DocumentCalculator.totals(for: document).totalTTC
                    summary.pendingQuotesCount += 1
                }
                continue
            }
            guard record.isIssuedInvoice else { continue }
            if inPeriod(document.issueDate) { summary.invoicedTTC += Accounting.invoicedTTC(record) }
            for payment in record.payments where inPeriod(payment.date) { summary.collectedTTC += Money.round(payment.amount) }
            guard document.kind != .creditNote else { continue }
            let ledger = Accounting.ledger(for: record, in: records)
            let state = ledger.state(dueDate: document.dueDate, today: today, calendar: calendar)
            if ledger.balance > 0 {
                summary.outstandingTTC += ledger.balance
                summary.unpaidInvoicesCount += 1
                if state == .overdue {
                    summary.overdueTTC += ledger.balance
                    summary.overdueInvoicesCount += 1
                }
            }
        }
        return summary
    }

    /// - Parameter months: nombre de mois affichés, se terminant au mois de `today`.
    public static func report(records: [DocumentRecord], months: Int, today: Date, calendar: Calendar = .devisMinute) -> StatisticsReport {
        let currentMonth = startOfMonth(today, calendar: calendar)
        var monthStarts: [Date] = []
        for offset in stride(from: max(months, 1) - 1, through: 0, by: -1) {
            if let month = calendar.date(byAdding: .month, value: -offset, to: currentMonth) { monthStarts.append(month) }
        }
        let firstMonth = monthStarts.first ?? currentMonth
        let end = calendar.date(byAdding: .month, value: 1, to: currentMonth) ?? today
        let window = DateInterval(start: firstMonth, end: end)

        var invoiced: [Date: Decimal] = [:]
        var collected: [Date: Decimal] = [:]
        var customers: [String: Tally] = [:]
        var items: [String: Tally] = [:]

        for record in records where record.isIssuedInvoice {
            let document = record.document
            if window.contains(document.issueDate) {
                let month = startOfMonth(document.issueDate, calendar: calendar)
                let amount = Accounting.invoicedHT(record)
                invoiced[month, default: 0] += amount
                let name = document.customer.name.trimmed.isEmpty ? "Client sans nom" : document.customer.name.trimmed
                customers[name, default: Tally()].add(amount, counted: document.kind != .creditNote)
                if document.kind == .invoice || document.kind == .creditNote {
                    let sign: Decimal = document.kind == .creditNote ? -1 : 1
                    let totals = DocumentCalculator.totals(for: document)
                    for line in document.itemLines {
                        let key = line.designation.trimmed.isEmpty ? "Sans désignation" : line.designation.trimmed
                        let value = (totals.lines[line.id]?.netHT ?? 0) * sign
                        items[key, default: Tally()].add(value, counted: sign > 0)
                    }
                }
            }
            for payment in record.payments where window.contains(payment.date) {
                collected[startOfMonth(payment.date, calendar: calendar), default: 0] += Money.round(payment.amount)
            }
        }

        var accepted: Int = 0
        var refused: Int = 0
        var expired: Int = 0
        var pending: Int = 0
        for record in records where record.document.kind == .quote && window.contains(record.document.issueDate) {
            switch QuoteLifecycle.effectiveStatus(record.quoteStatus ?? .draft, validUntil: record.document.validUntil, today: today, calendar: calendar) {
            case .accepted: accepted += 1
            case .refused: refused += 1
            case .expired: expired += 1
            case .sent: pending += 1
            case .draft: break
            }
        }
        let decided = accepted + refused + expired
        var conversion: Decimal?
        if decided >= minimumDecidedQuotes {
            let ratio: Decimal = Decimal(accepted) * Decimal(100) / Decimal(decided)
            conversion = Money.round(ratio, scale: 1)
        }

        func ranked(_ source: [String: Tally], limit: Int) -> [RankedAmount] {
            var result: [RankedAmount] = []
            for (label, tally) in source where tally.amount != 0 {
                result.append(RankedAmount(label: label, amount: tally.amount, count: tally.count))
            }
            result.sort { (lhs: RankedAmount, rhs: RankedAmount) -> Bool in
                if lhs.amount == rhs.amount { return lhs.label < rhs.label }
                return lhs.amount > rhs.amount
            }
            return Array(result.prefix(limit))
        }

        let invoicedSeries: [MonthlyAmount] = monthStarts.map { MonthlyAmount(month: $0, amount: invoiced[$0] ?? Decimal(0)) }
        let collectedSeries: [MonthlyAmount] = monthStarts.map { MonthlyAmount(month: $0, amount: collected[$0] ?? Decimal(0)) }
        let totalInvoiced: Decimal = invoicedSeries.reduce(Decimal(0)) { $0 + $1.amount }
        let totalCollected: Decimal = collectedSeries.reduce(Decimal(0)) { $0 + $1.amount }
        return StatisticsReport(
            invoicedHTByMonth: invoicedSeries,
            collectedByMonth: collectedSeries,
            byCustomer: ranked(customers, limit: 8),
            topItems: ranked(items, limit: 8),
            acceptedQuotes: accepted,
            refusedQuotes: refused,
            expiredQuotes: expired,
            pendingQuotes: pending,
            conversionRate: conversion,
            totalInvoicedHT: totalInvoiced,
            totalCollected: totalCollected
        )
    }

    public static func startOfMonth(_ date: Date, calendar: Calendar = .devisMinute) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }
}
