#if DEBUG
import Foundation
import CoreGraphics
import SwiftData
import DevisCore
import DevisPDF

/// Mode démonstration, **compilé uniquement en Debug** : `-DemoScreen <écran>` au lancement.
/// Utilise une base en mémoire (les données réelles ne sont jamais touchées) remplie
/// de données fictives, puis ouvre l'écran demandé. Sert aux captures d'écran automatiques.
enum DemoSupport {
    enum Screen: String {
        case onboarding, dashboard, quotes, invoices, customers, more, editor, detail, preview, statistics, signature, signed, signedpdf, reminder
    }

    static var screen: Screen? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-DemoScreen"), index + 1 < arguments.count else { return nil }
        return Screen(rawValue: arguments[index + 1])
    }

    static func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SettingsEntity.self, CustomerEntity.self, CatalogEntity.self, DocumentEntity.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// Documents mis en avant par les écrans de démonstration.
    @MainActor static var featuredQuoteID: UUID?
    @MainActor static var featuredInvoiceID: UUID?
    @MainActor static var signedQuoteID: UUID?
    @MainActor static var overdueInvoiceID: UUID?

    /// Signature manuscrite fictive (courbe générée), pour les captures.
    static var demoStrokes: [[CGPoint]] {
        let main: [CGPoint] = stride(from: 0.0, through: 1.0, by: 0.004).map { t in
            let x = 30 + t * 230
            let envelope = sin(t * .pi) * 0.7 + 0.3
            let y = 95 - 34 * envelope * sin(t * 15) - 10 * cos(t * 31) * envelope
            return CGPoint(x: x, y: y)
        }
        let underline: [CGPoint] = stride(from: 0.0, through: 1.0, by: 0.02).map { t in
            CGPoint(x: 60 + t * 220, y: 138 - 14 * sin(t * .pi * 0.9))
        }
        return [main, underline]
    }

    @MainActor
    static func seed(_ store: AppDataStore) {
        guard screen != .onboarding else { return }
        let calendar = Calendar.devisMinute
        let today = Date()
        func daysAgo(_ days: Int) -> Date { calendar.date(byAdding: .day, value: -days, to: today) ?? today }

        let company = CompanyProfile(
            tradeName: "Atelier Morel", legalName: "Atelier Morel", legalForm: .sarl, shareCapital: 8000,
            address: PostalAddress(line1: "14 rue des Tanneurs", postalCode: "69002", city: "Lyon"),
            siren: "732829320", siret: "73282932000074", registry: .rcs, registryCity: "Lyon",
            vatRegime: .standard, vatNumber: "FR44732829320", email: "contact@atelier-morel.fr", phone: "04 78 00 00 00",
            iban: "FR7630006000011234567890189", bic: "AGRIFRPP",
            professionalInsurance: "Décennale n° 000000 — Assureur Exemple — France métropolitaine"
        )
        try? store.completeOnboarding(company, appearance: DocumentAppearance(template: .artisan), logo: nil)

        let customers = [
            CustomerRecord(snapshot: CustomerSnapshot(kind: .business, name: "Boulangerie Petit", contactName: "Paul Petit", address: PostalAddress(line1: "8 avenue Foch", postalCode: "69006", city: "Lyon"), email: "paul@exemple.fr", siren: "552100554", vatNumber: "FR40552100554")),
            CustomerRecord(snapshot: CustomerSnapshot(kind: .individual, name: "Claire Leroy", address: PostalAddress(line1: "3 rue Haute", postalCode: "69005", city: "Lyon"), email: "claire@exemple.fr")),
            CustomerRecord(snapshot: CustomerSnapshot(kind: .business, name: "Cabinet Duval Architectes", contactName: "Sophie Duval", address: PostalAddress(line1: "21 quai Saint-Antoine", postalCode: "69002", city: "Lyon"), siren: "542051180", vatNumber: "FR03542051180")),
            CustomerRecord(snapshot: CustomerSnapshot(kind: .business, name: "Hôtel des Brotteaux", address: PostalAddress(line1: "5 place Jules Ferry", postalCode: "69006", city: "Lyon"), siren: "480165984")),
        ]
        for customer in customers { try? store.save(customer: customer) }

        let catalog = [
            CatalogItem(name: "Main d'œuvre — menuiserie", category: "Main d'œuvre", price: 48, vatRate: 10, unit: "h", unitCost: 30),
            CatalogItem(name: "Pose de parquet chêne massif", details: "Fourniture et pose, finition vitrifiée", category: "Sols", price: Decimal.exact("62.50"), vatRate: 10, unit: "m²", unitCost: 41, nature: .goods),
            CatalogItem(name: "Placard sur mesure", category: "Agencement", price: 1450, vatRate: 20, unit: "u", unitCost: 900, nature: .goods),
            CatalogItem(name: "Déplacement", category: "Frais", price: 35, vatRate: 20, unit: "forfait"),
        ]
        for item in catalog { try? store.save(item: item) }

        func lines(_ specs: [(String, Decimal, Decimal, Decimal, OperationNature)]) -> [DocumentLine] {
            specs.map { spec in
                let name = spec.0.lowercased()
                let unit = spec.4 == .services ? "h" : (name.contains("parquet") || name.contains("habillage") ? "m²" : "u")
                return DocumentLine(designation: spec.0, quantity: spec.1, unit: unit, unitPriceHT: spec.2, vatRate: spec.3, nature: spec.4)
            }
        }

        // Factures émises sur les derniers mois (ordre chronologique), avec paiements.
        let invoices: [(Int, Int, [DocumentLine], Decimal?)] = [
            (150, 0, lines([("Rénovation escalier", 18, 48, 10, .services), ("Bois et quincaillerie", 1, 640, 20, .goods)]), Decimal.exact("1590.40")),
            (118, 2, lines([("Bibliothèque sur mesure", 1, 2350, 20, .goods)]), 2820),
            (95, 3, lines([("Pose de parquet chêne massif", 42, Decimal.exact("62.50"), 10, .goods), ("Main d'œuvre", 12, 48, 10, .services)]), Decimal.exact("3521.10")),
            (64, 1, lines([("Réparation fenêtres", 6, 48, 10, .services)]), Decimal.exact("316.80")),
            (40, 0, lines([("Comptoir de vente", 1, 3200, 20, .goods), ("Pose", 10, 48, 10, .services)]), 1500),
            (20, 2, lines([("Habillage murs bureaux", 28, 85, 20, .goods)]), nil),
            (5, 3, lines([("Portes intérieures", 4, 420, 20, .goods), ("Pose", 8, 48, 10, .services)]), nil),
        ]
        for (age, customerIndex, documentLines, paid) in invoices {
            var record = store.makeInvoice(customer: customers[customerIndex], today: daysAgo(age))
            record.document.lines = documentLines
            record.document.dueDate = calendar.date(byAdding: .day, value: 30, to: daysAgo(age))
            try? store.save(record)
            if let issued = try? store.issue(id: record.id, now: daysAgo(age)) {
                if let paid {
                    try? store.addPayment(invoiceID: issued.id, payment: PaymentRecord(date: daysAgo(max(age - 20, 1)), amount: paid))
                }
                featuredInvoiceID = issued.id
                if age == 40 { overdueInvoiceID = issued.id }
            }
        }

        // Devis dans différents états.
        let quotes: [(Int, Int, String, QuoteStatus, [DocumentLine])] = [
            (60, 2, "Agencement accueil", .accepted, lines([("Banque d'accueil", 1, 4800, 20, .goods)])),
            (45, 3, "Rénovation chambres", .refused, lines([("Parquet chambres", 64, Decimal.exact("62.50"), 10, .goods)])),
            (12, 1, "Dressing chambre parentale", .sent, lines([("Placard sur mesure", 2, 1450, 20, .goods), ("Pose", 6, 48, 10, .services)])),
            (3, 0, "Rénovation de la salle de vente", .sent, [
                .section("Lot 1 — Préparation"),
                DocumentLine(designation: "Dépose de l'ancien revêtement et évacuation", details: "Protection des sols et tri des déchets compris.", quantity: 38, unit: "m²", unitPriceHT: 14, vatRate: 10),
                DocumentLine(designation: "Ragréage du support", quantity: 38, unit: "m²", unitPriceHT: Decimal.exact("18.50"), vatRate: 10),
                .section("Lot 2 — Pose"),
                DocumentLine(designation: "Pose de parquet chêne massif", details: "Fourniture et pose, finition vitrifiée.", quantity: 38, unit: "m²", unitPriceHT: Decimal.exact("62.50"), vatRate: 10, discount: .percent(5), nature: .goods),
                DocumentLine(designation: "Plinthes chêne assorties", quantity: 26, unit: "m", unitPriceHT: 12, vatRate: 20, nature: .goods),
            ]),
        ]
        for (age, customerIndex, title, status, documentLines) in quotes {
            var record = store.makeQuote(customer: customers[customerIndex], today: daysAgo(age))
            record.document.title = title
            record.document.lines = documentLines
            record.document.depositRequest = .percent(30)
            try? store.save(record)
            if status != .draft { try? store.setQuoteStatus(id: record.id, to: .sent) }
            if status == .accepted || status == .refused { try? store.setQuoteStatus(id: record.id, to: status) }
            featuredQuoteID = record.id
            // Le devis du dressing a été signé par la cliente sur l'iPhone.
            if title.hasPrefix("Dressing"), let jpeg = SignatureRenderer.jpeg(strokes: demoStrokes, canvasSize: CGSize(width: 340, height: 200)) {
                signedQuoteID = (try? store.signQuote(id: record.id, signerName: "Claire Leroy", place: "Lyon", imageJPEG: jpeg, signedAt: daysAgo(10)))?.id
            }
        }
        UserDefaults.standard.set("9000", forKey: "monthlyGoalHT")
    }
}
#endif
