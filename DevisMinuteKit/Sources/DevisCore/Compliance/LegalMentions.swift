import Foundation

/// Textes légaux par défaut (France). Sources : Code de commerce L441-9, L441-10, D441-5 ;
/// CGI art. 242 nonies A annexe II, 293 B ; fiche service-public.fr F31808 (vérifiée le 11/08/2026).
/// Ces textes sont des **modèles** : l'utilisateur reste responsable de leur adéquation à sa situation.
public enum LegalTexts {
    public static let defaultLatePenalty = "trois fois le taux d'intérêt légal en vigueur"
    public static let franchiseMention = "TVA non applicable, art. 293 B du CGI"
    public static let reverseChargeMention = "Autoliquidation"
    public static let vatOnDebitsMention = "Option pour le paiement de la taxe d'après les débits"
    public static let noEarlyPaymentDiscount = "Escompte pour paiement anticipé : néant"
    public static let recoveryIndemnity = "Indemnité forfaitaire pour frais de recouvrement en cas de retard de paiement : 40 € (art. L441-10 et D441-5 du Code de commerce)"
    public static let approvedAssociation = "Membre d'une association agréée, le règlement par chèque et carte bancaire est accepté"
    public static let quoteAcceptance = "Devis reçu avant l'exécution des travaux. Bon pour accord — date et signature :"
}

/// Construit les blocs de mentions imprimés sur un document.
public enum LegalMentionsBuilder {

    /// Ligne d'identité légale de l'émetteur (pied de page).
    public static func sellerLegalLine(_ seller: CompanyProfile) -> String {
        var parts: [String] = []
        if seller.legalForm.isIndividualEntrepreneur {
            parts.append(seller.legalIdentity)
        } else {
            var identity = seller.legalIdentity
            if !seller.legalForm.shortLabel.isEmpty { identity += " — \(seller.legalForm.shortLabel)" }
            if let capital = seller.shareCapital, capital > 0 {
                identity += " au capital de \(Money.format(capital))"
            }
            parts.append(identity)
        }
        let address = seller.address.lines.joined(separator: ", ")
        if !address.isEmpty { parts.append(seller.legalForm.isCompany ? "Siège : \(address)" : address) }
        if !seller.siret.trimmed.isEmpty {
            parts.append("SIRET \(formatSiret(seller.siret))")
        } else if !seller.siren.trimmed.isEmpty {
            parts.append("SIREN \(formatSiren(seller.siren))")
        }
        if seller.registry != .none {
            let city = seller.registryCity.trimmed
            switch seller.registry {
            case .rcs: parts.append(city.isEmpty ? "RCS" : "RCS \(city)")
            case .rm: parts.append(city.isEmpty ? "RM" : "RM \(city)")
            case .rne: parts.append("Immatriculée au RNE")
            case .none: break
            }
        }
        if !seller.apeCode.trimmed.isEmpty { parts.append("APE \(seller.apeCode.trimmed)") }
        if seller.isVATRegistered && !seller.vatNumber.trimmed.isEmpty {
            parts.append("TVA intracom. \(seller.vatNumber.trimmed)")
        }
        return parts.joined(separator: " · ")
    }

    /// Mentions de bas de document (conditions de règlement, TVA, pénalités…).
    public static func mentions(for document: BusinessDocument, totals: DocumentTotals) -> [String] {
        let seller = document.seller
        var result: [String] = []

        if !seller.isVATRegistered {
            result.append(LegalTexts.franchiseMention)
        } else if document.reverseCharge {
            result.append(LegalTexts.reverseChargeMention)
        } else if seller.vatOnDebits && document.itemLines.contains(where: { $0.nature == .services }) {
            result.append(LegalTexts.vatOnDebitsMention)
        }

        switch document.kind {
        case .quote:
            if let validUntil = document.validUntil {
                result.append("Devis valable jusqu'au \(DateFormatting.long(validUntil)).")
            }
            if totals.requestedDepositTTC > 0 {
                result.append("Acompte demandé à la commande : \(Money.format(totals.requestedDepositTTC)) TTC.")
            }
        case .invoice, .depositInvoice:
            if !document.sourceQuoteNumber.isEmpty {
                result.append("Facture établie d'après le devis n° \(document.sourceQuoteNumber).")
            }
            if let dueDate = document.dueDate {
                result.append("Date d'échéance du règlement : \(DateFormatting.long(dueDate)).")
            }
            let discountText = seller.earlyPaymentDiscountText.trimmed
            result.append(discountText.isEmpty ? LegalTexts.noEarlyPaymentDiscount : discountText)
            let penalty = seller.latePenaltyText.trimmed.isEmpty ? LegalTexts.defaultLatePenalty : seller.latePenaltyText.trimmed
            result.append("En cas de retard de paiement, des pénalités sont exigibles sans rappel au taux de \(penalty).")
            if document.isBusinessToBusiness {
                result.append(LegalTexts.recoveryIndemnity + ".")
            }
        case .creditNote:
            if !document.correctedInvoiceNumber.isEmpty {
                result.append("Avoir se rapportant à la facture n° \(document.correctedInvoiceNumber).")
            }
        }

        if seller.approvedAssociationMember { result.append(LegalTexts.approvedAssociation + ".") }
        if !seller.professionalInsurance.trimmed.isEmpty {
            result.append("Assurance professionnelle : \(seller.professionalInsurance.trimmed)")
        }
        if !seller.additionalMentions.trimmed.isEmpty { result.append(seller.additionalMentions.trimmed) }
        return result
    }

    public static func formatSiren(_ value: String) -> String {
        let digits = value.filter(\.isNumber)
        guard digits.count == 9 else { return value.trimmed }
        return group(digits, sizes: [3, 3, 3])
    }

    public static func formatSiret(_ value: String) -> String {
        let digits = value.filter(\.isNumber)
        guard digits.count == 14 else { return value.trimmed }
        return group(digits, sizes: [3, 3, 3, 5])
    }

    private static func group(_ digits: String, sizes: [Int]) -> String {
        var groups: [String] = []
        var index = digits.startIndex
        for size in sizes {
            let end = digits.index(index, offsetBy: size)
            groups.append(String(digits[index..<end]))
            index = end
        }
        return groups.joined(separator: " ")
    }
}

/// Formats de date français.
public enum DateFormatting {
    public static func long(_ date: Date) -> String { formatter("d MMMM yyyy").string(from: date) }
    public static func short(_ date: Date) -> String { formatter("dd/MM/yyyy").string(from: date) }
    public static func iso(_ date: Date) -> String { formatter("yyyy-MM-dd").string(from: date) }
    /// Format compact AAAAMMJJ (norme CII / Factur-X, code 102).
    public static func compact(_ date: Date) -> String { formatter("yyyyMMdd").string(from: date) }
    public static func monthYear(_ date: Date) -> String { formatter("MMM yyyy").string(from: date) }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.calendar = Calendar.devisMinute
        formatter.timeZone = Calendar.devisMinute.timeZone
        formatter.dateFormat = format
        return formatter
    }
}
