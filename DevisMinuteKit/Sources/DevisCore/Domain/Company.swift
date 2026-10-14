import Foundation

/// Adresse postale.
public struct PostalAddress: Codable, Sendable, Equatable, Hashable {
    public var line1: String
    public var line2: String
    public var postalCode: String
    public var city: String
    public var country: String

    public init(line1: String = "", line2: String = "", postalCode: String = "", city: String = "", country: String = "France") {
        self.line1 = line1
        self.line2 = line2
        self.postalCode = postalCode
        self.city = city
        self.country = country
    }

    public var isEmpty: Bool {
        line1.trimmed.isEmpty && postalCode.trimmed.isEmpty && city.trimmed.isEmpty
    }

    /// Lignes prêtes à imprimer (sans lignes vides ; pays omis s'il s'agit de la France).
    public var lines: [String] {
        var result: [String] = []
        if !line1.trimmed.isEmpty { result.append(line1.trimmed) }
        if !line2.trimmed.isEmpty { result.append(line2.trimmed) }
        let cityLine = [postalCode.trimmed, city.trimmed].filter { !$0.isEmpty }.joined(separator: " ")
        if !cityLine.isEmpty { result.append(cityLine) }
        let countryName = country.trimmed
        if !countryName.isEmpty && countryName.lowercased() != "france" { result.append(countryName) }
        return result
    }
}

/// Forme juridique de l'émetteur. Elle conditionne les mentions légales obligatoires.
public enum LegalForm: String, Codable, Sendable, CaseIterable, Identifiable {
    case microEntrepreneur
    case entrepreneurIndividuel
    case eurl
    case sarl
    case sasu
    case sas
    case sa
    case snc
    case selarl
    case other

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .microEntrepreneur: return "Micro-entrepreneur (EI)"
        case .entrepreneurIndividuel: return "Entrepreneur individuel (EI)"
        case .eurl: return "EURL"
        case .sarl: return "SARL"
        case .sasu: return "SASU"
        case .sas: return "SAS"
        case .sa: return "SA"
        case .snc: return "SNC"
        case .selarl: return "SELARL"
        case .other: return "Autre"
        }
    }

    /// Abréviation imprimée après la dénomination (« SARL au capital de … »).
    public var shortLabel: String {
        switch self {
        case .microEntrepreneur, .entrepreneurIndividuel: return "EI"
        case .other: return ""
        default: return label
        }
    }

    /// Entrepreneur individuel (y compris micro-entrepreneur) : mention « EI » obligatoire
    /// (art. R526-27 du Code de commerce), pas de capital social.
    public var isIndividualEntrepreneur: Bool {
        self == .microEntrepreneur || self == .entrepreneurIndividuel
    }

    /// Société : forme juridique, capital social et siège à mentionner.
    public var isCompany: Bool { !isIndividualEntrepreneur && self != .other }
}

/// Régime de TVA de l'émetteur.
public enum VATRegime: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Assujetti redevable de la TVA.
    case standard
    /// Franchise en base de TVA (art. 293 B du CGI) : aucune TVA facturée.
    case franchise

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .standard: return "Assujetti à la TVA"
        case .franchise: return "Franchise en base de TVA (art. 293 B du CGI)"
        }
    }
}

/// Registre d'immatriculation mentionné sur les documents.
public enum RegistrationRegistry: String, Codable, Sendable, CaseIterable, Identifiable {
    case none
    case rcs
    case rm
    case rne

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .none: return "Aucun"
        case .rcs: return "RCS"
        case .rm: return "Répertoire des métiers"
        case .rne: return "RNE"
        }
    }
}

/// Informations de l'entreprise émettrice, recopiées (« figées ») dans chaque document émis.
public struct CompanyProfile: Codable, Sendable, Equatable {
    public var tradeName: String
    public var legalName: String
    public var ownerName: String
    public var legalForm: LegalForm
    public var shareCapital: Decimal?
    public var address: PostalAddress
    public var siren: String
    public var siret: String
    public var registry: RegistrationRegistry
    public var registryCity: String
    public var apeCode: String
    public var vatRegime: VATRegime
    public var vatNumber: String
    /// Option pour le paiement de la TVA d'après les débits (prestations de services).
    public var vatOnDebits: Bool
    public var email: String
    public var phone: String
    public var website: String
    public var iban: String
    public var bic: String
    public var bankName: String
    /// Délai de paiement par défaut, en jours à compter de l'émission.
    public var paymentTermsDays: Int
    /// Texte du taux des pénalités de retard (ex. « trois fois le taux d'intérêt légal »).
    public var latePenaltyText: String
    /// Conditions d'escompte ; vide = « Escompte pour paiement anticipé : néant ».
    public var earlyPaymentDiscountText: String
    /// Assurance professionnelle (obligatoire pour les activités artisanales concernées).
    public var professionalInsurance: String
    /// Membre d'un centre de gestion ou d'une association agréée.
    public var approvedAssociationMember: Bool
    public var additionalMentions: String
    public var quoteDefaultValidityDays: Int

    public init(
        tradeName: String = "",
        legalName: String = "",
        ownerName: String = "",
        legalForm: LegalForm = .microEntrepreneur,
        shareCapital: Decimal? = nil,
        address: PostalAddress = PostalAddress(),
        siren: String = "",
        siret: String = "",
        registry: RegistrationRegistry = .none,
        registryCity: String = "",
        apeCode: String = "",
        vatRegime: VATRegime = .franchise,
        vatNumber: String = "",
        vatOnDebits: Bool = false,
        email: String = "",
        phone: String = "",
        website: String = "",
        iban: String = "",
        bic: String = "",
        bankName: String = "",
        paymentTermsDays: Int = 30,
        latePenaltyText: String = LegalTexts.defaultLatePenalty,
        earlyPaymentDiscountText: String = "",
        professionalInsurance: String = "",
        approvedAssociationMember: Bool = false,
        additionalMentions: String = "",
        quoteDefaultValidityDays: Int = 30
    ) {
        self.tradeName = tradeName
        self.legalName = legalName
        self.ownerName = ownerName
        self.legalForm = legalForm
        self.shareCapital = shareCapital
        self.address = address
        self.siren = siren
        self.siret = siret
        self.registry = registry
        self.registryCity = registryCity
        self.apeCode = apeCode
        self.vatRegime = vatRegime
        self.vatNumber = vatNumber
        self.vatOnDebits = vatOnDebits
        self.email = email
        self.phone = phone
        self.website = website
        self.iban = iban
        self.bic = bic
        self.bankName = bankName
        self.paymentTermsDays = paymentTermsDays
        self.latePenaltyText = latePenaltyText
        self.earlyPaymentDiscountText = earlyPaymentDiscountText
        self.professionalInsurance = professionalInsurance
        self.approvedAssociationMember = approvedAssociationMember
        self.additionalMentions = additionalMentions
        self.quoteDefaultValidityDays = quoteDefaultValidityDays
    }

    /// Nom affiché en tête de document.
    public var displayName: String {
        if !tradeName.trimmed.isEmpty { return tradeName.trimmed }
        if !legalName.trimmed.isEmpty { return legalName.trimmed }
        return ownerName.trimmed
    }

    /// Dénomination légale complète, avec la mention « EI » pour un entrepreneur individuel.
    public var legalIdentity: String {
        if legalForm.isIndividualEntrepreneur {
            let name = ownerName.trimmed.isEmpty ? legalName.trimmed : ownerName.trimmed
            return name.isEmpty ? "EI" : "\(name) EI"
        }
        return legalName.trimmed.isEmpty ? tradeName.trimmed : legalName.trimmed
    }

    public var isVATRegistered: Bool { vatRegime == .standard }
}

extension String {
    /// Chaîne sans espaces ni retours à la ligne en début et fin.
    public var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
