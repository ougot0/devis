import Foundation

/// Catégorie de dépense professionnelle.
public enum ExpenseCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case materials
    case subcontracting
    case equipment
    case travel
    case meals
    case software
    case phone
    case insurance
    case rent
    case bank
    case fees
    case other

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .materials: return "Achats et matériaux"
        case .subcontracting: return "Sous-traitance"
        case .equipment: return "Outillage et équipement"
        case .travel: return "Carburant et déplacements"
        case .meals: return "Repas"
        case .software: return "Logiciels et abonnements"
        case .phone: return "Téléphone et internet"
        case .insurance: return "Assurances"
        case .rent: return "Loyer et charges"
        case .bank: return "Frais bancaires"
        case .fees: return "Honoraires (comptable…)"
        case .other: return "Autres"
        }
    }

    /// Symbole SF Symbols utilisé par l'application.
    public var symbol: String {
        switch self {
        case .materials: return "shippingbox"
        case .subcontracting: return "person.2"
        case .equipment: return "hammer"
        case .travel: return "car"
        case .meals: return "fork.knife"
        case .software: return "app.badge"
        case .phone: return "phone"
        case .insurance: return "shield"
        case .rent: return "building.2"
        case .bank: return "building.columns"
        case .fees: return "doc.text.magnifyingglass"
        case .other: return "ellipsis.circle"
        }
    }
}

/// Dépense professionnelle, avec son justificatif éventuel.
public struct ExpenseRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var date: Date
    public var supplier: String
    public var label: String
    public var category: ExpenseCategory
    public var amountTTC: Decimal
    /// TVA figurant sur le justificatif (récupérable si l'entreprise est assujettie).
    public var vatAmount: Decimal
    public var paymentMethod: PaymentMethod
    public var notes: String
    /// Photo ou scan du justificatif, en JPEG.
    public var receiptJPEG: Data?
    public var createdAt: Date

    public init(id: UUID = UUID(), date: Date, supplier: String = "", label: String = "", category: ExpenseCategory = .other, amountTTC: Decimal, vatAmount: Decimal = 0, paymentMethod: PaymentMethod = .card, notes: String = "", receiptJPEG: Data? = nil, createdAt: Date = Date()) {
        self.id = id
        self.date = date
        self.supplier = supplier
        self.label = label
        self.category = category
        self.amountTTC = amountTTC
        self.vatAmount = vatAmount
        self.paymentMethod = paymentMethod
        self.notes = notes
        self.receiptJPEG = receiptJPEG
        self.createdAt = createdAt
    }

    public var amountHT: Decimal { amountTTC - vatAmount }

    /// Coût réel pour l'entreprise : HT si la TVA est récupérable, TTC sinon (franchise en base).
    public func cost(vatRecoverable: Bool) -> Decimal { vatRecoverable ? amountHT : amountTTC }

    public var title: String {
        let parts = [supplier.trimmed, label.trimmed].filter { !$0.isEmpty }
        return parts.isEmpty ? category.label : parts.joined(separator: " — ")
    }

    /// TVA calculée à partir d'un montant TTC et d'un taux (arrondi au centime).
    public static func vat(fromTTC amount: Decimal, rate: Decimal) -> Decimal {
        guard rate > 0 else { return 0 }
        return Money.round(amount - amount * 100 / (100 + rate))
    }

    public func validate() throws {
        guard amountTTC > 0 else { throw ExpenseError.amountRequired }
        guard vatAmount >= 0, vatAmount < amountTTC else { throw ExpenseError.invalidVAT }
    }
}

public enum ExpenseError: Error, LocalizedError, Equatable {
    case amountRequired
    case invalidVAT

    public var errorDescription: String? {
        switch self {
        case .amountRequired: return "Indiquez le montant TTC de la dépense."
        case .invalidVAT: return "La TVA doit être positive et inférieure au montant TTC."
        }
    }
}

/// Bénéfice estimé : chiffre d'affaires facturé HT moins les dépenses.
public struct ProfitSummary: Sendable, Equatable {
    public var revenueHT: Decimal
    public var expenses: Decimal
    public var profit: Decimal { revenueHT - expenses }
    /// Part du chiffre d'affaires qui reste après les dépenses (nil sans chiffre d'affaires).
    public var marginRate: Decimal? {
        guard revenueHT > 0 else { return nil }
        return Money.round(profit / revenueHT * 100, scale: 1)
    }
    public var expensesByCategory: [(category: ExpenseCategory, amount: Decimal)]

    public static func == (lhs: ProfitSummary, rhs: ProfitSummary) -> Bool {
        lhs.revenueHT == rhs.revenueHT && lhs.expenses == rhs.expenses
            && lhs.expensesByCategory.map(\.category) == rhs.expensesByCategory.map(\.category)
            && lhs.expensesByCategory.map(\.amount) == rhs.expensesByCategory.map(\.amount)
    }
}

public enum ProfitCalculator {
    /// - Parameter interval: période (nil = depuis le début).
    public static func summary(records: [DocumentRecord], expenses: [ExpenseRecord], interval: DateInterval?, vatRecoverable: Bool) -> ProfitSummary {
        let inPeriod = { (date: Date) -> Bool in interval?.contains(date) ?? true }
        let revenue = records
            .filter { $0.isIssuedInvoice && inPeriod($0.document.issueDate) }
            .reduce(Decimal(0)) { $0 + Accounting.invoicedHT($1) }
        var byCategory: [ExpenseCategory: Decimal] = [:]
        var total: Decimal = 0
        for expense in expenses where inPeriod(expense.date) {
            let cost = expense.cost(vatRecoverable: vatRecoverable)
            byCategory[expense.category, default: 0] += cost
            total += cost
        }
        let sorted = byCategory.map { (category: $0.key, amount: $0.value) }.sorted { $0.amount > $1.amount }
        return ProfitSummary(revenueHT: revenue, expenses: total, expensesByCategory: sorted)
    }
}
