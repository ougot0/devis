import Foundation

/// Nature des prestations de services d'un micro-entrepreneur (les ventes de biens suivent les lignes « Bien »).
public enum MicroServicesKind: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Prestations commerciales ou artisanales (BIC).
    case commercial
    /// Prestations libérales (BNC), Sécurité sociale des indépendants.
    case liberal
    /// Profession libérale réglementée relevant de la Cipav.
    case cipav

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .commercial: return "Prestations commerciales ou artisanales (BIC)"
        case .liberal: return "Prestations libérales (BNC)"
        case .cipav: return "Profession libérale relevant de la Cipav"
        }
    }
}

public enum DeclarationFrequency: String, Codable, Sendable, CaseIterable, Identifiable {
    case monthly
    case quarterly

    public var id: String { rawValue }
    public var label: String { self == .monthly ? "Mensuelle" : "Trimestrielle" }
}

/// Réglages propres au micro-entrepreneur.
public struct MicroSettings: Codable, Sendable, Equatable {
    public var servicesKind: MicroServicesKind
    public var frequency: DeclarationFrequency
    /// Versement libératoire de l'impôt sur le revenu.
    public var versementLiberatoire: Bool

    public init(servicesKind: MicroServicesKind = .commercial, frequency: DeclarationFrequency = .quarterly, versementLiberatoire: Bool = false) {
        self.servicesKind = servicesKind
        self.frequency = frequency
        self.versementLiberatoire = versementLiberatoire
    }
}

/// Taux et seuils du régime micro pour une année.
public struct MicroRates: Sendable, Equatable {
    public var year: Int
    public var salesRate: Decimal
    public var commercialServicesRate: Decimal
    public var liberalRate: Decimal
    public var cipavRate: Decimal
    /// Versement libératoire : ventes, prestations BIC, prestations BNC.
    public var vlSales: Decimal
    public var vlCommercial: Decimal
    public var vlLiberal: Decimal
    /// Contribution à la formation professionnelle : commerçant, artisan, libéral.
    public var cfpTrader: Decimal
    public var cfpCraftsman: Decimal
    public var cfpLiberal: Decimal
    /// Plafonds du régime micro (chiffre d'affaires annuel HT).
    public var salesCeiling: Decimal
    public var servicesCeiling: Decimal
    /// Franchise en base de TVA : seuils de base et majorés.
    public var vatSalesThreshold: Decimal
    public var vatSalesHigherThreshold: Decimal
    public var vatServicesThreshold: Decimal
    public var vatServicesHigherThreshold: Decimal
    public var source: String

    /// Valeurs 2026, vérifiées le 16/10/2026 sur autoentrepreneur.urssaf.fr, economie.gouv.fr et service-public.fr.
    public static let y2026 = MicroRates(
        year: 2026,
        salesRate: Decimal.exact("12.3"), commercialServicesRate: Decimal.exact("21.2"), liberalRate: Decimal.exact("25.6"), cipavRate: Decimal.exact("23.2"),
        vlSales: 1, vlCommercial: Decimal.exact("1.7"), vlLiberal: Decimal.exact("2.2"),
        cfpTrader: Decimal.exact("0.1"), cfpCraftsman: Decimal.exact("0.3"), cfpLiberal: Decimal.exact("0.2"),
        salesCeiling: 203_100, servicesCeiling: 83_600,
        vatSalesThreshold: 85_000, vatSalesHigherThreshold: 93_500, vatServicesThreshold: 37_500, vatServicesHigherThreshold: 41_250,
        source: "Taux 2026 (autoentrepreneur.urssaf.fr, economie.gouv.fr), vérifiés en octobre 2026"
    )

    /// Barème à utiliser pour une année (le plus récent connu si l'année n'est pas encore renseignée).
    public static func forYear(_ year: Int) -> MicroRates { y2026 }

    public func servicesRate(_ kind: MicroServicesKind) -> Decimal {
        switch kind {
        case .commercial: return commercialServicesRate
        case .liberal: return liberalRate
        case .cipav: return cipavRate
        }
    }
}

/// Chiffre d'affaires encaissé HT, séparé entre ventes de biens et prestations de services.
public struct MicroRevenue: Sendable, Equatable {
    public var goods: Decimal
    public var services: Decimal
    public var total: Decimal { goods + services }

    public init(goods: Decimal = 0, services: Decimal = 0) {
        self.goods = goods
        self.services = services
    }
}

/// Une ligne de cotisation estimée.
public struct ContributionLine: Sendable, Equatable, Identifiable {
    public var label: String
    public var base: Decimal
    public var rate: Decimal
    public var amount: Decimal { Money.round(base * rate / 100) }
    public var id: String { label }
}

/// Déclaration de chiffre d'affaires d'une période (mois ou trimestre).
public struct MicroDeclaration: Sendable, Equatable {
    public var period: DateInterval
    public var title: String
    public var dueDate: Date
    public var revenue: MicroRevenue
    public var lines: [ContributionLine]
    public var total: Decimal { lines.reduce(Decimal(0)) { $0 + $1.amount } }
}

/// Alerte de seuil (plafond micro ou franchise de TVA).
public struct ThresholdStatus: Sendable, Equatable, Identifiable {
    public enum Level: Int, Sendable, Comparable {
        case ok, approaching, exceeded, critical
        public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public var id: String { title }
    public var title: String
    public var amount: Decimal
    public var limit: Decimal
    public var level: Level
    public var message: String

    public var progress: Double {
        guard limit > 0 else { return 0 }
        return NSDecimalNumber(decimal: amount / limit).doubleValue
    }
}

public enum MicroCalculator {

    /// CA encaissé HT sur la période : chaque paiement est converti en HT au prorata de la facture
    /// et réparti entre biens et services selon la nature des lignes.
    public static func revenue(records: [DocumentRecord], in period: DateInterval) -> MicroRevenue {
        var result = MicroRevenue()
        for record in records where record.isIssuedInvoice && record.document.kind != .creditNote {
            let payments = record.payments.filter { period.contains($0.date) }
            guard !payments.isEmpty else { continue }
            let totals = DocumentCalculator.totals(for: record.document)
            guard totals.totalTTC > 0 else { continue }
            var goodsHT: Decimal = 0
            var servicesHT: Decimal = 0
            for line in record.document.itemLines {
                let lineHT = totals.lines[line.id]?.netHT ?? 0
                if line.nature == .goods { goodsHT += lineHT } else { servicesHT += lineHT }
            }
            let linesHT = goodsHT + servicesHT
            let goodsShare = linesHT > 0 ? goodsHT / linesHT : 0
            for payment in payments {
                let paidHT = payment.amount * totals.totalHT / totals.totalTTC
                let goods = Money.round(paidHT * goodsShare)
                result.goods += goods
                result.services += Money.round(paidHT) - goods
            }
        }
        return result
    }

    /// Période de déclaration contenant `date`.
    public static func period(containing date: Date, frequency: DeclarationFrequency, calendar: Calendar = .devisMinute) -> DateInterval {
        switch frequency {
        case .monthly:
            return calendar.dateInterval(of: .month, for: date)!
        case .quarterly:
            let month = calendar.component(.month, from: date)
            let year = calendar.component(.year, from: date)
            let firstMonth = ((month - 1) / 3) * 3 + 1
            let start = calendar.date(from: DateComponents(year: year, month: firstMonth, day: 1))!
            let end = calendar.date(byAdding: .month, value: 3, to: start)!
            return DateInterval(start: start, end: end)
        }
    }

    public static func previousPeriod(before period: DateInterval, frequency: DeclarationFrequency, calendar: Calendar = .devisMinute) -> DateInterval {
        Self.period(containing: period.start.addingTimeInterval(-3600), frequency: frequency, calendar: calendar)
    }

    /// Date limite de déclaration : dernier jour du mois qui suit la période.
    public static func dueDate(for period: DateInterval, calendar: Calendar = .devisMinute) -> Date {
        let nextMonth = calendar.dateInterval(of: .month, for: period.end)!
        return calendar.date(byAdding: .day, value: -1, to: nextMonth.end)!
    }

    public static func title(for period: DateInterval, frequency: DeclarationFrequency, calendar: Calendar = .devisMinute) -> String {
        let year = calendar.component(.year, from: period.start)
        switch frequency {
        case .monthly:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "fr_FR")
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "LLLL yyyy"
            let text = formatter.string(from: period.start)
            return text.prefix(1).uppercased() + text.dropFirst()
        case .quarterly:
            let quarter = (calendar.component(.month, from: period.start) - 1) / 3 + 1
            return "\(quarter == 1 ? "1er" : "\(quarter)e") trimestre \(year)"
        }
    }

    /// Cotisations estimées de la période.
    public static func declaration(records: [DocumentRecord], period: DateInterval, settings: MicroSettings, isCraftsman: Bool, rates: MicroRates? = nil, calendar: Calendar = .devisMinute) -> MicroDeclaration {
        let year = calendar.component(.year, from: period.start)
        let rates = rates ?? MicroRates.forYear(year)
        let revenue = revenue(records: records, in: period)
        var lines: [ContributionLine] = []
        if revenue.goods != 0 {
            lines.append(ContributionLine(label: "Cotisations sociales — ventes", base: revenue.goods, rate: rates.salesRate))
        }
        if revenue.services != 0 {
            lines.append(ContributionLine(label: "Cotisations sociales — services", base: revenue.services, rate: rates.servicesRate(settings.servicesKind)))
        }
        if revenue.total != 0 {
            let cfp: Decimal
            switch settings.servicesKind {
            case .liberal, .cipav: cfp = rates.cfpLiberal
            case .commercial: cfp = isCraftsman ? rates.cfpCraftsman : rates.cfpTrader
            }
            lines.append(ContributionLine(label: "Formation professionnelle (CFP)", base: revenue.total, rate: cfp))
        }
        if settings.versementLiberatoire {
            if revenue.goods != 0 { lines.append(ContributionLine(label: "Versement libératoire — ventes", base: revenue.goods, rate: rates.vlSales)) }
            if revenue.services != 0 {
                lines.append(ContributionLine(label: "Versement libératoire — services", base: revenue.services, rate: settings.servicesKind == .commercial ? rates.vlCommercial : rates.vlLiberal))
            }
        }
        return MicroDeclaration(period: period, title: title(for: period, frequency: settings.frequency, calendar: calendar), dueDate: dueDate(for: period, calendar: calendar), revenue: revenue, lines: lines)
    }

    /// Suivi des plafonds de l'année civile en cours.
    public static func thresholds(records: [DocumentRecord], year: Int, franchise: Bool, rates: MicroRates? = nil, calendar: Calendar = .devisMinute) -> [ThresholdStatus] {
        let rates = rates ?? MicroRates.forYear(year)
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
        let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))!
        let revenue = revenue(records: records, in: DateInterval(start: start, end: end))
        var result: [ThresholdStatus] = []

        func ratioLevel(_ amount: Decimal, _ limit: Decimal) -> ThresholdStatus.Level {
            if amount > limit { return .exceeded }
            return amount >= limit * Decimal.exact("0.8") ? .approaching : .ok
        }

        // Plafond du régime micro : services, puis total (ventes + services).
        let servicesLevel = ratioLevel(revenue.services, rates.servicesCeiling)
        result.append(ThresholdStatus(title: "Plafond micro — services", amount: revenue.services, limit: rates.servicesCeiling, level: servicesLevel,
                                      message: servicesLevel == .exceeded ? "Plafond dépassé : si cela se reproduit l'an prochain, vous sortirez du régime micro. Parlez-en à votre comptable." : "Chiffre d'affaires de prestations encaissé en \(year)."))
        if revenue.goods > 0 {
            let totalLevel = ratioLevel(revenue.total, rates.salesCeiling)
            result.append(ThresholdStatus(title: "Plafond micro — total", amount: revenue.total, limit: rates.salesCeiling, level: totalLevel,
                                          message: totalLevel == .exceeded ? "Plafond global dépassé : si cela se reproduit l'an prochain, vous sortirez du régime micro." : "Ventes et prestations encaissées en \(year)."))
        }

        // Franchise en base de TVA.
        if franchise {
            let checks: [(String, Decimal, Decimal, Decimal)] = revenue.goods > 0
                ? [("Franchise de TVA — services", revenue.services, rates.vatServicesThreshold, rates.vatServicesHigherThreshold),
                   ("Franchise de TVA — total", revenue.total, rates.vatSalesThreshold, rates.vatSalesHigherThreshold)]
                : [("Franchise de TVA", revenue.services, rates.vatServicesThreshold, rates.vatServicesHigherThreshold)]
            for (title, amount, base, higher) in checks {
                let level: ThresholdStatus.Level
                let message: String
                if amount > higher {
                    level = .critical
                    message = "Seuil majoré de \(Money.format(higher)) dépassé : vous devez facturer la TVA dès la facture qui a fait dépasser le seuil. Passez en « Assujetti à la TVA » dans les réglages de l'entreprise."
                } else if amount > base {
                    level = .exceeded
                    message = "Seuil de \(Money.format(base)) dépassé : vous facturerez la TVA à partir du 1er janvier \(year + 1). Au-delà de \(Money.format(higher)), la TVA s'applique immédiatement."
                } else {
                    level = ratioLevel(amount, base)
                    message = level == .approaching ? "Vous approchez du seuil de la franchise de TVA (\(Money.format(base)))." : "Seuil de la franchise en base de TVA : \(Money.format(base))."
                }
                result.append(ThresholdStatus(title: title, amount: amount, limit: base, level: level, message: message))
            }
        }
        return result
    }
}
