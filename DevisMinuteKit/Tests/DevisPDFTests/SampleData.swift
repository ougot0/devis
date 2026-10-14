import Foundation
import DevisCore

/// Données d'exemple pour les tests de rendu (fictives, uniquement en test).
enum SampleData {
    /// Logo JPEG 240 × 80 px.
    static let logoJPEG = Data(base64Encoded: "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")!

    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day; components.hour = 12
        return Calendar.devisMinute.date(from: components)!
    }

    static var seller: CompanyProfile {
        CompanyProfile(
            tradeName: "Atelier Martin",
            legalName: "Atelier Martin",
            legalForm: .sarl,
            shareCapital: 15000,
            address: PostalAddress(line1: "12 rue des Lilas", postalCode: "69003", city: "Lyon"),
            siren: "732829320",
            siret: "73282932000074",
            registry: .rcs,
            registryCity: "Lyon",
            vatRegime: .standard,
            vatNumber: "FR44732829320",
            email: "contact@atelier-martin.fr",
            phone: "04 72 00 00 00",
            iban: "FR7630006000011234567890189",
            bic: "AGRIFRPP",
            professionalInsurance: "Décennale n° 123456 — Assureur Exemple, 1 rue de Paris 75001 Paris — couverture France métropolitaine"
        )
    }

    static var customer: CustomerSnapshot {
        CustomerSnapshot(kind: .business, name: "Boulangerie Petit SAS", contactName: "M. Paul Petit",
                         address: PostalAddress(line1: "8 avenue Foch", postalCode: "75016", city: "Paris"),
                         siren: "552100554", vatNumber: "FR40552100554")
    }

    static func quote(lineCount: Int = 6, longText: Bool = false) -> BusinessDocument {
        var lines: [DocumentLine] = [.section("Lot 1 — Préparation")]
        for index in 0..<lineCount {
            if index == lineCount / 2 { lines.append(.section("Lot 2 — Pose et finitions")) }
            var line = DocumentLine(
                designation: index % 3 == 0 ? "Dépose de l'ancien revêtement et évacuation des gravats" : "Fourniture et pose de carrelage grès cérame 60×60",
                details: index % 2 == 0 ? "Y compris protection des sols, nettoyage de fin de chantier et tri des déchets." : "",
                quantity: Decimal(index % 4 + 1) + Decimal.exact("0.5"),
                unit: index % 2 == 0 ? "m²" : "h",
                unitPriceHT: Decimal.exact("42.90") + Decimal(index),
                vatRate: index % 5 == 0 ? 20 : 10,
                discount: index == 1 ? .percent(10) : .none,
                nature: index % 2 == 0 ? .services : .goods
            )
            if longText && index == 2 {
                line.details = String(repeating: "Description très détaillée de la prestation avec contraintes techniques, références de matériaux et conditions d'accès au chantier. ", count: 40)
            }
            lines.append(line)
        }
        lines.append(DocumentLine(kind: .note, designation: "Les quantités seront ajustées au métré réel en fin de chantier."))
        return BusinessDocument(
            kind: .quote,
            number: "D-2026-0042",
            issueDate: date(2026, 10, 14),
            validUntil: date(2026, 11, 13),
            title: "Rénovation de la salle de vente",
            seller: seller,
            customer: customer,
            lines: lines,
            globalDiscount: .percent(5),
            depositRequest: .percent(30),
            specialConditions: "Travaux réalisés en horaires de fermeture du magasin. Accès au local à prévoir par le client.",
            notes: "Merci de votre confiance."
        )
    }

    static func invoice(lineCount: Int = 6, longText: Bool = false) -> BusinessDocument {
        var document = quote(lineCount: lineCount, longText: longText)
        document.kind = .invoice
        document.number = "F-2026-0118"
        document.serviceDate = date(2026, 10, 10)
        document.validUntil = nil
        document.dueDate = date(2026, 11, 13)
        document.sourceQuoteNumber = "D-2026-0042"
        document.depositRequest = .none
        document.depositDeductions = [DepositDeduction(invoiceNumber: "F-2026-0101", issueDate: date(2026, 9, 20), amountTTC: 100)]
        return document
    }
}
