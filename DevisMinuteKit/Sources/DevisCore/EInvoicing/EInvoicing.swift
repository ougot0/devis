import Foundation

/// Préparation à la facturation électronique (réforme française 2026-2027).
///
/// État au 14/10/2026 (service-public.fr, fiche F39785 vérifiée le 07/08/2026) :
/// - réception obligatoire pour toutes les entreprises depuis le 1er septembre 2026 ;
/// - émission obligatoire le 1er septembre 2026 (grandes entreprises, ETI)
///   et le 1er septembre 2027 (PME, micro-entreprises) ;
/// - émission, réception et transmission **uniquement via une plateforme agréée (PA)**.
///
/// DevisMinute fonctionne hors ligne et n'est connecté à aucune plateforme agréée :
/// un PDF produit par l'application **n'est pas** une facture électronique au sens de la réforme,
/// et le XML ci-dessous est une **aide préparatoire** non validée par une plateforme.
/// Le protocole `EInvoicingGateway` définit le point d'intégration futur.
public protocol EInvoicingGateway: Sendable {
    var displayName: String { get }
    /// Transmet une facture émise à la plateforme agréée et retourne son identifiant de suivi.
    func submit(document: BusinessDocument, structuredData: Data, pdf: Data) async throws -> String
    /// Récupère le statut de cycle de vie (déposée, rejetée, encaissée…).
    func status(of submissionID: String) async throws -> String
}

public enum EInvoicingError: Error, LocalizedError {
    case notConfigured

    public var errorDescription: String? {
        "Aucune plateforme agréée n'est connectée. DevisMinute ne transmet pas de factures électroniques : utilisez la plateforme agréée choisie par votre entreprise."
    }
}

/// Implémentation par défaut : aucune transmission (fonctionnement 100 % local).
public struct NoEInvoicingGateway: EInvoicingGateway {
    public init() {}
    public var displayName: String { "Aucune plateforme connectée" }
    public func submit(document: BusinessDocument, structuredData: Data, pdf: Data) async throws -> String { throw EInvoicingError.notConfigured }
    public func status(of submissionID: String) async throws -> String { throw EInvoicingError.notConfigured }
}

/// Génère un fichier XML au format UN/CEFACT CII (syntaxe utilisée par Factur-X), structure inspirée
/// de la norme EN 16931. **Non validé** contre les schémas et règles Schematron officiels :
/// à considérer comme un export de données structurées, pas comme une facture électronique conforme.
public enum CIIExporter {

    /// Constructeur XML minimal (indentation, échappement).
    struct XMLWriter {
        private(set) var text = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        private var depth = 0
        private var stack: [String] = []

        static func escape(_ value: String) -> String {
            value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }

        private static func attributes(_ attributes: [(String, String)]) -> String {
            attributes.map { " \($0.0)=\"\(escape($0.1))\"" }.joined()
        }

        private var indent: String { String(repeating: "  ", count: depth) }

        mutating func comment(_ value: String) {
            text += indent + "<!-- " + value + " -->\n"
        }

        mutating func open(_ name: String, _ attrs: [(String, String)] = []) {
            text += indent + "<" + name + Self.attributes(attrs) + ">\n"
            stack.append(name)
            depth += 1
        }

        mutating func close() {
            depth -= 1
            let name = stack.removeLast()
            text += indent + "</" + name + ">\n"
        }

        mutating func leaf(_ name: String, _ value: String, _ attrs: [(String, String)] = []) {
            text += indent + "<" + name + Self.attributes(attrs) + ">" + Self.escape(value) + "</" + name + ">\n"
        }

        mutating func element(_ name: String, _ attrs: [(String, String)] = [], _ content: (inout XMLWriter) -> Void) {
            open(name, attrs)
            content(&self)
            close()
        }
    }

    private static func amount(_ value: Decimal) -> String { Money.plainString(value) }

    private static func date(_ name: String, _ value: Date, into xml: inout XMLWriter) {
        xml.element(name) { $0.leaf("udt:DateTimeString", DateFormatting.compact(value), [("format", "102")]) }
    }

    private static func address(_ value: PostalAddress, into xml: inout XMLWriter) {
        xml.open("ram:PostalTradeAddress")
        xml.leaf("ram:PostcodeCode", value.postalCode)
        xml.leaf("ram:LineOne", value.line1)
        if !value.line2.isEmpty { xml.leaf("ram:LineTwo", value.line2) }
        xml.leaf("ram:CityName", value.city)
        let country = value.country.trimmed
        xml.leaf("ram:CountryID", country.isEmpty || country.lowercased() == "france" ? "FR" : country)
        xml.close()
    }

    private static func tax(category: String, rate: Decimal, into xml: inout XMLWriter) {
        xml.leaf("ram:TypeCode", "VAT")
        xml.leaf("ram:CategoryCode", category)
        xml.leaf("ram:RateApplicablePercent", amount(rate))
    }

    private static func allowanceIndicator(into xml: inout XMLWriter) {
        xml.open("ram:ChargeIndicator")
        xml.leaf("udt:Indicator", "false")
        xml.close()
    }

    public static func xml(for document: BusinessDocument) -> Data {
        let totals = DocumentCalculator.totals(for: document)
        let seller = document.seller
        let customer = document.customer
        let typeCode: String
        switch document.kind {
        case .creditNote: typeCode = "381"
        case .depositInvoice: typeCode = "386"
        default: typeCode = "380"
        }
        let category: String = !seller.isVATRegistered ? "E" : (document.reverseCharge ? "AE" : "S")

        var xml = XMLWriter()
        xml.comment("Export de données structurées DevisMinute (format CII). Préparatoire : non validé par une plateforme agréée.")
        xml.open("rsm:CrossIndustryInvoice", [
            ("xmlns:rsm", "urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100"),
            ("xmlns:ram", "urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100"),
            ("xmlns:udt", "urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100"),
        ])

        xml.open("rsm:ExchangedDocumentContext")
        xml.open("ram:GuidelineSpecifiedDocumentContextParameter")
        xml.leaf("ram:ID", "urn:cen.eu:en16931:2017")
        xml.close()
        xml.close()

        xml.open("rsm:ExchangedDocument")
        xml.leaf("ram:ID", document.number)
        xml.leaf("ram:TypeCode", typeCode)
        date("ram:IssueDateTime", document.issueDate, into: &xml)
        for mention in LegalMentionsBuilder.mentions(for: document, totals: totals) {
            xml.open("ram:IncludedNote")
            xml.leaf("ram:Content", mention)
            xml.close()
        }
        xml.close()

        xml.open("rsm:SupplyChainTradeTransaction")
        for (index, line) in document.itemLines.enumerated() {
            let lineTotals = totals.lines[line.id] ?? DocumentCalculator.lineTotals(line)
            xml.open("ram:IncludedSupplyChainTradeLineItem")
            xml.open("ram:AssociatedDocumentLineDocument")
            xml.leaf("ram:LineID", String(index + 1))
            xml.close()
            xml.open("ram:SpecifiedTradeProduct")
            xml.leaf("ram:Name", line.designation)
            if !line.details.trimmed.isEmpty { xml.leaf("ram:Description", line.details) }
            xml.close()
            xml.open("ram:SpecifiedLineTradeAgreement")
            xml.open("ram:NetPriceProductTradePrice")
            xml.leaf("ram:ChargeAmount", Money.plainString(line.unitPriceHT, scale: 4))
            xml.close()
            xml.close()
            xml.open("ram:SpecifiedLineTradeDelivery")
            xml.leaf("ram:BilledQuantity", Money.plainString(line.quantity, scale: 4), [("unitCode", "C62")])
            xml.close()
            xml.open("ram:SpecifiedLineTradeSettlement")
            xml.open("ram:ApplicableTradeTax")
            tax(category: category, rate: document.chargesVAT ? line.vatRate : 0, into: &xml)
            xml.close()
            if lineTotals.discountHT > 0 {
                xml.open("ram:SpecifiedTradeAllowanceCharge")
                allowanceIndicator(into: &xml)
                xml.leaf("ram:ActualAmount", amount(lineTotals.discountHT))
                xml.close()
            }
            xml.open("ram:SpecifiedTradeSettlementLineMonetarySummation")
            xml.leaf("ram:LineTotalAmount", amount(lineTotals.netHT))
            xml.close()
            xml.close()
            xml.close()
        }

        xml.open("ram:ApplicableHeaderTradeAgreement")
        if !document.purchaseOrderReference.isEmpty { xml.leaf("ram:BuyerReference", document.purchaseOrderReference) }
        xml.open("ram:SellerTradeParty")
        xml.leaf("ram:Name", seller.legalIdentity)
        let sellerSiret = seller.siret.filter(\.isNumber)
        let sellerSiren = sellerSiret.isEmpty ? seller.siren.filter(\.isNumber) : String(sellerSiret.prefix(9))
        if !sellerSiren.isEmpty {
            xml.open("ram:SpecifiedLegalOrganization")
            xml.leaf("ram:ID", sellerSiren, [("schemeID", "0002")])
            xml.close()
        }
        address(seller.address, into: &xml)
        if !seller.email.isEmpty {
            xml.open("ram:URIUniversalCommunication")
            xml.leaf("ram:URIID", seller.email, [("schemeID", "EM")])
            xml.close()
        }
        if seller.isVATRegistered && !seller.vatNumber.isEmpty {
            xml.open("ram:SpecifiedTaxRegistration")
            xml.leaf("ram:ID", seller.vatNumber.filter { !$0.isWhitespace }, [("schemeID", "VA")])
            xml.close()
        }
        xml.close()
        xml.open("ram:BuyerTradeParty")
        xml.leaf("ram:Name", customer.name)
        let customerSiren = customer.siren.filter(\.isNumber)
        if !customerSiren.isEmpty {
            xml.open("ram:SpecifiedLegalOrganization")
            xml.leaf("ram:ID", customerSiren, [("schemeID", "0002")])
            xml.close()
        }
        address(customer.address, into: &xml)
        if !customer.vatNumber.isEmpty {
            xml.open("ram:SpecifiedTaxRegistration")
            xml.leaf("ram:ID", customer.vatNumber.filter { !$0.isWhitespace }, [("schemeID", "VA")])
            xml.close()
        }
        xml.close()
        xml.close()

        xml.open("ram:ApplicableHeaderTradeDelivery")
        if let delivery = customer.deliveryAddress, !delivery.isEmpty {
            xml.open("ram:ShipToTradeParty")
            address(delivery, into: &xml)
            xml.close()
        }
        if let serviceDate = document.serviceDate {
            xml.open("ram:ActualDeliverySupplyChainEvent")
            date("ram:OccurrenceDateTime", serviceDate, into: &xml)
            xml.close()
        }
        xml.close()

        xml.open("ram:ApplicableHeaderTradeSettlement")
        xml.leaf("ram:InvoiceCurrencyCode", "EUR")
        if !seller.iban.isEmpty {
            xml.open("ram:SpecifiedTradeSettlementPaymentMeans")
            xml.leaf("ram:TypeCode", "58")
            xml.open("ram:PayeePartyCreditorFinancialAccount")
            xml.leaf("ram:IBANID", seller.iban.filter { !$0.isWhitespace })
            xml.close()
            xml.close()
        }
        for bucket in totals.vatBuckets {
            xml.open("ram:ApplicableTradeTax")
            xml.leaf("ram:CalculatedAmount", amount(bucket.vatAmount))
            xml.leaf("ram:TypeCode", "VAT")
            if category == "E" {
                xml.leaf("ram:ExemptionReason", LegalTexts.franchiseMention)
                xml.leaf("ram:ExemptionReasonCode", "VATEX-FR-FRANCHISE")
            } else if category == "AE" {
                xml.leaf("ram:ExemptionReason", "Autoliquidation")
                xml.leaf("ram:ExemptionReasonCode", "VATEX-EU-AE")
            }
            xml.leaf("ram:BasisAmount", amount(bucket.baseHT))
            xml.leaf("ram:CategoryCode", category)
            if seller.vatOnDebits && category == "S" { xml.leaf("ram:DueDateTypeCode", "5") }
            xml.leaf("ram:RateApplicablePercent", amount(bucket.rate))
            xml.close()
        }
        if totals.globalDiscountHT > 0 {
            let shares = Money.allocate(totals.globalDiscountHT, weights: totals.vatBuckets.map(\.baseHT))
            for (bucket, share) in zip(totals.vatBuckets, shares) where share > 0 {
                xml.open("ram:SpecifiedTradeAllowanceCharge")
                allowanceIndicator(into: &xml)
                xml.leaf("ram:ActualAmount", amount(share))
                xml.leaf("ram:Reason", "Remise")
                xml.open("ram:CategoryTradeTax")
                tax(category: category, rate: bucket.rate, into: &xml)
                xml.close()
                xml.close()
            }
        }
        if let dueDate = document.dueDate {
            xml.open("ram:SpecifiedTradePaymentTerms")
            date("ram:DueDateDateTime", dueDate, into: &xml)
            xml.close()
        }
        if !document.correctedInvoiceNumber.isEmpty {
            xml.open("ram:InvoiceReferencedDocument")
            xml.leaf("ram:IssuerAssignedID", document.correctedInvoiceNumber)
            xml.close()
        }
        xml.open("ram:SpecifiedTradeSettlementHeaderMonetarySummation")
        xml.leaf("ram:LineTotalAmount", amount(totals.subtotalHT))
        xml.leaf("ram:AllowanceTotalAmount", amount(totals.globalDiscountHT))
        xml.leaf("ram:TaxBasisTotalAmount", amount(totals.totalHT))
        xml.leaf("ram:TaxTotalAmount", amount(totals.totalVAT), [("currencyID", "EUR")])
        xml.leaf("ram:GrandTotalAmount", amount(totals.totalTTC))
        xml.leaf("ram:TotalPrepaidAmount", amount(totals.depositsDeductedTTC))
        xml.leaf("ram:DuePayableAmount", amount(totals.netToPay))
        xml.close()
        xml.close()

        xml.close()
        xml.close()
        return Data(xml.text.utf8)
    }
}
