import XCTest
@testable import DevisCore

final class NumberingResumeTests: XCTestCase {

    func testResumeContinuesAfterExternalNumber() throws {
        let resumed = try NumberingService.resumedState(after: 57, lastIssueDate: Fixtures.date(2026, 10, 2), lastNumber: "F-2026-0057", current: NumberingState())
        let next = try NumberingService.next(scheme: .defaultInvoice, state: resumed, issueDate: Fixtures.date(2026, 10, 15))
        XCTAssertEqual(next.number, "F-2026-0058")
        XCTAssertThrowsError(try NumberingService.next(scheme: .defaultInvoice, state: resumed, issueDate: Fixtures.date(2026, 10, 1)), "Chronologie conservée")
    }

    func testResumeNeverGoesBackwards() {
        let current = NumberingState(lastSequence: 12, lastYear: 2026, lastIssueDate: Fixtures.date(2026, 10, 10), lastNumber: "F-2026-0012")
        XCTAssertThrowsError(try NumberingService.resumedState(after: 5, lastIssueDate: Fixtures.date(2026, 10, 10), lastNumber: "F-2026-0005", current: current))
        XCTAssertNoThrow(try NumberingService.resumedState(after: 40, lastIssueDate: Fixtures.date(2026, 10, 12), lastNumber: "F-2026-0040", current: current))
        XCTAssertThrowsError(try NumberingService.resumedState(after: -1, lastIssueDate: Fixtures.date(2026, 10, 12), lastNumber: "", current: NumberingState()))
    }

    func testSequenceExtraction() {
        XCTAssertEqual(NumberingService.sequence(in: "F-2026-0057", scheme: .defaultInvoice), 57)
        XCTAssertEqual(NumberingService.sequence(in: "FAC00123", scheme: NumberingScheme(pattern: "FAC{N:5}", resetsYearly: false)), 123)
        XCTAssertEqual(NumberingService.sequence(in: "2604-007", scheme: NumberingScheme(pattern: "{AA}{MM}-{N:3}", resetsYearly: true)), 7)
        XCTAssertNil(NumberingService.sequence(in: "FACT-57", scheme: .defaultInvoice))
    }
}

final class PaymentLinkTests: XCTestCase {
    func testValidation() {
        XCTAssertTrue(PaymentLink.isValid("https://buy.stripe.com/test_8wM5kE"))
        XCTAssertTrue(PaymentLink.isValid("  https://paypal.me/ateliermorel  "))
        XCTAssertFalse(PaymentLink.isValid("http://buy.stripe.com/x"), "https obligatoire")
        XCTAssertFalse(PaymentLink.isValid("buy.stripe.com/x"))
        XCTAssertFalse(PaymentLink.isValid("https://exemple com"))
        XCTAssertFalse(PaymentLink.isValid("javascript:alert(1)"))
        XCTAssertEqual(PaymentLink.providerName("https://buy.stripe.com/abc"), "Stripe")
        XCTAssertNil(PaymentLink.providerName("https://exemple.fr/payer"))
    }

    func testLinkDoesNotBreakExistingSeals() {
        var invoice = Fixtures.invoice(lines: [Fixtures.line("A", qty: "1", price: "100")])
        invoice.number = "F-2026-0001"
        let before = DocumentSealer.canonicalRepresentation(of: invoice)
        XCTAssertFalse(before.contains("paymentLink"), "Un document sans lien garde sa représentation v1")
        let seal = DocumentSealer.seal(invoice, previousSealHash: "", sealedAt: Date())
        invoice.paymentLink = "https://buy.stripe.com/x"
        XCTAssertFalse(DocumentSealer.verify(invoice, seal: seal), "Le lien fait partie du contenu scellé")
    }

    func testOldJSONWithoutNewFieldsStillDecodes() throws {
        var invoice = Fixtures.invoice(lines: [Fixtures.line("A", qty: "1", price: "100")])
        invoice.paymentLink = nil
        let data = try BackupService.encoder().encode(DocumentRecord(document: invoice))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "isImported")
        let decoded = try BackupService.decoder().decode(DocumentRecord.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(decoded.imported)
        XCTAssertNil(decoded.document.paymentLink)
    }
}

final class HistoryImportTests: XCTestCase {

    private let csv = """
    Numéro;Date;Client;Total HT;TVA;Total TTC;Payé;Échéance
    F-2026-0055;03/09/2026;Boulangerie Petit SAS;1 000,00;200,00;1 200,00;1 200,00;03/10/2026
    F-2026-0056;15/09/2026;Nouveau Client SARL;850,50;;1 020,60;300;
    F-2026-0057;2026-10-02;Mme Dupont;;;450,00;;
    F-2026-0058;02/10/2026;Client X;100;20;999;;
    ;02/10/2026;Client Y;100;20;120;;
    F-2026-0059;31/02/2026;Client Z;100;20;120;;
    AV-2026-0003;05/10/2026;Boulangerie Petit SAS;100;20;;;
    F-2026-0055;03/09/2026;Doublon;100;20;120;;
    """

    func testImport() throws {
        let existing = [CustomerRecord(snapshot: Fixtures.businessCustomer)]
        let result = HistoryImporter.invoices(Data(csv.utf8), seller: Fixtures.companySeller, existingCustomers: existing, existingNumbers: [], now: Fixtures.date(2026, 10, 15))
        XCTAssertEqual(result.records.map(\.document.number), ["F-2026-0055", "F-2026-0056", "F-2026-0057", "AV-2026-0003"])
        XCTAssertEqual(Set(result.skipped.map(\.line)), [5, 6, 7, 9])

        let first = result.records[0]
        XCTAssertTrue(first.imported)
        XCTAssertTrue(first.isIssuedInvoice)
        XCTAssertEqual(first.customerID, existing[0].id, "Client existant retrouvé par son nom")
        XCTAssertEqual(DocumentCalculator.totals(for: first.document).totalTTC, 1200)
        XCTAssertEqual(Accounting.ledger(for: first, in: result.records).balance, 0)

        // TVA déduite de HT et TTC, taux non standard reproduit au centime.
        let second = result.records[1]
        XCTAssertEqual(DocumentCalculator.totals(for: second.document).totalVAT, .exact("170.10"))
        XCTAssertEqual(Accounting.ledger(for: second, in: result.records).balance, .exact("720.60"))
        XCTAssertEqual(result.newCustomers.map(\.snapshot.name), ["Nouveau Client SARL", "Mme Dupont"])

        // TTC seul : sans TVA.
        XCTAssertEqual(DocumentCalculator.totals(for: result.records[2].document).totalVAT, 0)
        XCTAssertEqual(result.records[3].document.kind, .creditNote)
    }

    func testImportedInvoicesCountInStatisticsAndSkipSealChecks() throws {
        let result = HistoryImporter.invoices(Data(csv.utf8), seller: Fixtures.companySeller, existingCustomers: [], existingNumbers: [], now: Fixtures.date(2026, 10, 15))
        let dashboard = StatisticsEngine.dashboard(records: result.records, customerCount: 0, period: nil, today: Fixtures.date(2026, 10, 15))
        XCTAssertEqual(dashboard.invoicedTTC, 1200 + .exact("1020.60") + 450 - 120)
        let snapshot = BackupSnapshot(appVersion: "t", company: Fixtures.companySeller, customers: result.newCustomers, catalog: [], documents: result.records, numbering: [:])
        XCTAssertTrue(try BackupService.validate(snapshot).isEmpty, "Pas d'avertissement de sceau pour l'historique importé")
    }

    func testExistingNumbersAreRejected() {
        let result = HistoryImporter.invoices(Data(csv.utf8), seller: Fixtures.companySeller, existingCustomers: [], existingNumbers: ["F-2026-0056"], now: Fixtures.date(2026, 10, 15))
        XCTAssertFalse(result.records.contains { $0.document.number == "F-2026-0056" })
    }

    func testDates() {
        XCTAssertEqual(HistoryImporter.parseDate("03/09/2026"), Fixtures.date(2026, 9, 3))
        XCTAssertEqual(HistoryImporter.parseDate("2026-09-03"), Fixtures.date(2026, 9, 3))
        XCTAssertEqual(HistoryImporter.parseDate("3.9.26"), Fixtures.date(2026, 9, 3))
        XCTAssertNil(HistoryImporter.parseDate("31/02/2026"))
        XCTAssertNil(HistoryImporter.parseDate("hier"))
    }
}
