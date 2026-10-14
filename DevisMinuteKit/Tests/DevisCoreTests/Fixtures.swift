import Foundation
@testable import DevisCore

enum Fixtures {
    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return Calendar.devisMinute.date(from: components)!
    }

    static var companySeller: CompanyProfile {
        CompanyProfile(
            tradeName: "Atelier Martin",
            legalName: "Atelier Martin SARL",
            legalForm: .sarl,
            shareCapital: 10_000,
            address: PostalAddress(line1: "12 rue des Lilas", postalCode: "69003", city: "Lyon"),
            siren: "732829320",
            registry: .rcs,
            registryCity: "Lyon",
            vatRegime: .standard,
            vatNumber: "FR44732829320",
            email: "contact@atelier-martin.fr",
            iban: "FR7630006000011234567890189"
        )
    }

    static var microSeller: CompanyProfile {
        CompanyProfile(
            tradeName: "Studio Lune",
            ownerName: "Camille Durand",
            legalForm: .microEntrepreneur,
            address: PostalAddress(line1: "3 place du Marché", postalCode: "35000", city: "Rennes"),
            siren: "732829320",
            vatRegime: .franchise
        )
    }

    static var businessCustomer: CustomerSnapshot {
        CustomerSnapshot(
            kind: .business,
            name: "Boulangerie Petit SAS",
            address: PostalAddress(line1: "8 avenue Foch", postalCode: "75016", city: "Paris"),
            siren: "552100554",
            vatNumber: "FR40552100554"
        )
    }

    static var individualCustomer: CustomerSnapshot {
        CustomerSnapshot(kind: .individual, name: "Mme Claire Leroy", address: PostalAddress(line1: "1 rue Haute", postalCode: "44000", city: "Nantes"))
    }

    static func line(_ designation: String, qty: String, price: String, vat: String = "20", discount: Discount = .none) -> DocumentLine {
        DocumentLine(designation: designation, quantity: .exact(qty), unit: "u", unitPriceHT: .exact(price), vatRate: .exact(vat), discount: discount)
    }

    static func invoice(lines: [DocumentLine], seller: CompanyProfile = companySeller, customer: CustomerSnapshot = businessCustomer, discount: Discount = .none) -> BusinessDocument {
        BusinessDocument(
            kind: .invoice,
            issueDate: date(2026, 10, 1),
            serviceDate: date(2026, 9, 30),
            dueDate: date(2026, 10, 31),
            seller: seller,
            customer: customer,
            lines: lines,
            globalDiscount: discount
        )
    }
}
