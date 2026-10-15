import Foundation

/// Type de client : conditionne les mentions (indemnité de 40 €, SIREN client…).
public enum CustomerKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case business
    case individual
    case publicEntity

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .business: return "Professionnel"
        case .individual: return "Particulier"
        case .publicEntity: return "Entité publique"
        }
    }

    public var isProfessional: Bool { self != .individual }
}

/// Coordonnées du client recopiées dans un document.
public struct CustomerSnapshot: Codable, Sendable, Equatable {
    public var kind: CustomerKind
    public var name: String
    public var contactName: String
    public var address: PostalAddress
    /// Adresse de livraison des biens, si différente.
    public var deliveryAddress: PostalAddress?
    public var email: String
    public var phone: String
    public var siren: String
    public var vatNumber: String

    public init(
        kind: CustomerKind = .business,
        name: String = "",
        contactName: String = "",
        address: PostalAddress = PostalAddress(),
        deliveryAddress: PostalAddress? = nil,
        email: String = "",
        phone: String = "",
        siren: String = "",
        vatNumber: String = ""
    ) {
        self.kind = kind
        self.name = name
        self.contactName = contactName
        self.address = address
        self.deliveryAddress = deliveryAddress
        self.email = email
        self.phone = phone
        self.siren = siren
        self.vatNumber = vatNumber
    }
}

/// Remise, en pourcentage ou en valeur HT.
public enum Discount: Codable, Sendable, Equatable, Hashable {
    case none
    case percent(Decimal)
    case amount(Decimal)

    public var isNone: Bool {
        switch self {
        case .none: return true
        case .percent(let value), .amount(let value): return value == 0
        }
    }

    /// Montant de la remise appliquée à `base`, arrondi au centime et plafonné à la base.
    public func amount(on base: Decimal) -> Decimal {
        let raw: Decimal
        switch self {
        case .none: raw = 0
        case .percent(let rate): raw = Money.round(base * rate / 100)
        case .amount(let value): raw = Money.round(value)
        }
        if base >= 0 { return min(max(raw, 0), base) }
        return max(min(raw, 0), base)
    }

    public var label: String {
        switch self {
        case .none: return ""
        case .percent(let rate): return "−\(Money.formatQuantity(rate)) %"
        case .amount(let value): return "−\(Money.format(value))"
        }
    }
}

/// Nature d'une ligne : livraison de biens ou prestation de services
/// (mention « nature des opérations » de la réforme de la facturation électronique).
public enum OperationNature: String, Codable, Sendable, CaseIterable, Identifiable {
    case goods
    case services

    public var id: String { rawValue }
    public var label: String { self == .goods ? "Bien" : "Service" }
}

/// Type de ligne dans un document.
public enum LineKind: String, Codable, Sendable, CaseIterable {
    /// Ligne chiffrée.
    case item
    /// Titre de section (non chiffré).
    case section
    /// Texte libre (non chiffré).
    case note
}

/// Ligne d'un devis ou d'une facture. Les prix sont **HT**.
public struct DocumentLine: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var kind: LineKind
    public var designation: String
    public var details: String
    public var quantity: Decimal
    public var unit: String
    public var unitPriceHT: Decimal
    /// Taux de TVA en pourcentage (20, 10, 5.5, 2.1, 0).
    public var vatRate: Decimal
    public var discount: Discount
    public var nature: OperationNature
    /// Référence de l'élément de catalogue d'origine (statistiques).
    public var catalogItemID: UUID?
    /// Coût de revient unitaire facultatif (jamais imprimé).
    public var unitCost: Decimal?

    public init(
        id: UUID = UUID(),
        kind: LineKind = .item,
        designation: String = "",
        details: String = "",
        quantity: Decimal = 1,
        unit: String = "u",
        unitPriceHT: Decimal = 0,
        vatRate: Decimal = 20,
        discount: Discount = .none,
        nature: OperationNature = .services,
        catalogItemID: UUID? = nil,
        unitCost: Decimal? = nil
    ) {
        self.id = id
        self.kind = kind
        self.designation = designation
        self.details = details
        self.quantity = quantity
        self.unit = unit
        self.unitPriceHT = unitPriceHT
        self.vatRate = vatRate
        self.discount = discount
        self.nature = nature
        self.catalogItemID = catalogItemID
        self.unitCost = unitCost
    }

    public static func section(_ title: String) -> DocumentLine {
        DocumentLine(kind: .section, designation: title, quantity: 0, unit: "", unitPriceHT: 0, vatRate: 0)
    }

    /// Copie avec un nouvel identifiant (duplication de ligne).
    public func duplicated() -> DocumentLine {
        var copy = self
        copy.id = UUID()
        return copy
    }
}

/// Type de document commercial.
public enum DocumentKind: String, Codable, Sendable, CaseIterable {
    case quote
    case invoice
    case depositInvoice
    case creditNote

    public var title: String {
        switch self {
        case .quote: return "Devis"
        case .invoice: return "Facture"
        case .depositInvoice: return "Facture d'acompte"
        case .creditNote: return "Avoir"
        }
    }

    public var isInvoiceLike: Bool { self != .quote }
}

/// Acompte demandé sur un devis.
public enum DepositRequest: Codable, Sendable, Equatable {
    case none
    case percent(Decimal)
    case amount(Decimal)

    /// Montant TTC de l'acompte demandé.
    public func amount(onTTC total: Decimal) -> Decimal {
        switch self {
        case .none: return 0
        case .percent(let rate): return min(Money.round(total * rate / 100), total)
        case .amount(let value): return min(Money.round(value), total)
        }
    }
}

/// Facture d'acompte déjà émise, déduite d'une facture de solde.
public struct DepositDeduction: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var invoiceNumber: String
    public var issueDate: Date
    /// Montant TTC de la facture d'acompte.
    public var amountTTC: Decimal

    public init(id: UUID = UUID(), invoiceNumber: String, issueDate: Date, amountTTC: Decimal) {
        self.id = id
        self.invoiceNumber = invoiceNumber
        self.issueDate = issueDate
        self.amountTTC = amountTTC
    }
}

/// Contenu complet d'un document tel qu'il est calculé, imprimé, scellé et exporté.
/// C'est une valeur pure : la persistance (SwiftData) la convertit dans les deux sens.
public struct BusinessDocument: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var kind: DocumentKind
    /// Numéro ; vide tant qu'une facture est à l'état de brouillon.
    public var number: String
    public var issueDate: Date
    /// Date de la vente / fin de la prestation (factures).
    public var serviceDate: Date?
    /// Date limite de validité (devis).
    public var validUntil: Date?
    /// Date d'échéance du paiement (factures).
    public var dueDate: Date?
    public var title: String
    public var seller: CompanyProfile
    public var customer: CustomerSnapshot
    public var lines: [DocumentLine]
    public var globalDiscount: Discount
    public var depositRequest: DepositRequest
    public var depositDeductions: [DepositDeduction]
    public var purchaseOrderReference: String
    /// Numéro du devis d'origine (facture issue d'un devis).
    public var sourceQuoteNumber: String
    /// Numéro de la facture corrigée (avoir).
    public var correctedInvoiceNumber: String
    public var paymentTermsText: String
    public var specialConditions: String
    public var notes: String
    /// Autoliquidation : la TVA est due par le client (sous-traitance BTP, prestations
    /// intracommunautaires…). Aucune TVA n'est facturée et la mention « Autoliquidation » est imprimée.
    public var reverseCharge: Bool
    /// Lien de paiement en ligne (Stripe, SumUp, PayPal…), imprimé avec un QR code. Facultatif.
    public var paymentLink: String?

    public init(
        id: UUID = UUID(),
        kind: DocumentKind,
        number: String = "",
        issueDate: Date,
        serviceDate: Date? = nil,
        validUntil: Date? = nil,
        dueDate: Date? = nil,
        title: String = "",
        seller: CompanyProfile,
        customer: CustomerSnapshot,
        lines: [DocumentLine] = [],
        globalDiscount: Discount = .none,
        depositRequest: DepositRequest = .none,
        depositDeductions: [DepositDeduction] = [],
        purchaseOrderReference: String = "",
        sourceQuoteNumber: String = "",
        correctedInvoiceNumber: String = "",
        paymentTermsText: String = "",
        specialConditions: String = "",
        notes: String = "",
        reverseCharge: Bool = false,
        paymentLink: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.number = number
        self.issueDate = issueDate
        self.serviceDate = serviceDate
        self.validUntil = validUntil
        self.dueDate = dueDate
        self.title = title
        self.seller = seller
        self.customer = customer
        self.lines = lines
        self.globalDiscount = globalDiscount
        self.depositRequest = depositRequest
        self.depositDeductions = depositDeductions
        self.purchaseOrderReference = purchaseOrderReference
        self.sourceQuoteNumber = sourceQuoteNumber
        self.correctedInvoiceNumber = correctedInvoiceNumber
        self.paymentTermsText = paymentTermsText
        self.specialConditions = specialConditions
        self.notes = notes
        self.reverseCharge = reverseCharge
        self.paymentLink = paymentLink
    }

    /// TVA facturée sur ce document ?
    public var chargesVAT: Bool { seller.isVATRegistered && !reverseCharge }

    /// Lignes chiffrées uniquement.
    public var itemLines: [DocumentLine] { lines.filter { $0.kind == .item } }

    /// Nature globale des opérations facturées.
    public var operationNatureLabel: String {
        let natures = Set(itemLines.map(\.nature))
        if natures == [.goods] { return "Livraison de biens" }
        if natures == [.services] || natures.isEmpty { return "Prestation de services" }
        return "Livraison de biens et prestation de services"
    }

    /// Le client doit-il voir les mentions réservées aux professionnels (indemnité de 40 €) ?
    public var isBusinessToBusiness: Bool { customer.kind.isProfessional }
}
