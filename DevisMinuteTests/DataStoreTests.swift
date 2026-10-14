import XCTest
import SwiftData
import DevisCore
@testable import DevisMinute

/// Tests d'intégration de la couche de persistance (base SwiftData en mémoire).
@MainActor
final class DataStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var store: DataStore!

    override func setUp() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: SettingsEntity.self, CustomerEntity.self, CatalogEntity.self, DocumentEntity.self, configurations: configuration)
        store = DataStore(context: container.mainContext)
        let profile = CompanyProfile(
            tradeName: "Atelier Test", legalName: "Atelier Test SARL", legalForm: .sarl, shareCapital: 1000,
            address: PostalAddress(line1: "1 rue A", postalCode: "75001", city: "Paris"),
            siren: "732829320", registry: .rcs, registryCity: "Paris", vatRegime: .standard, vatNumber: "FR44732829320")
        try store.completeOnboarding(profile, appearance: .init(), logo: nil)
    }

    private func customer() throws -> CustomerRecord {
        let record = CustomerRecord(snapshot: CustomerSnapshot(kind: .business, name: "Client SAS", address: PostalAddress(line1: "2 rue B", postalCode: "69001", city: "Lyon"), siren: "552100554", vatNumber: "FR40552100554"))
        try store.save(customer: record)
        return record
    }

    private func draftInvoice(price: Decimal = 100) throws -> DocumentRecord {
        var record = store.makeInvoice(customer: try customer())
        record.document.lines = [DocumentLine(designation: "Prestation", quantity: 1, unitPriceHT: price, vatRate: 20)]
        try store.save(record)
        return record
    }

    func testQuoteIsNumberedOnFirstSave() throws {
        var quote = store.makeQuote(customer: try customer())
        quote.document.lines = [DocumentLine(designation: "A", unitPriceHT: 10)]
        try store.save(quote)
        let saved = try XCTUnwrap(store.allRecords().first)
        XCTAssertTrue(saved.document.number.hasPrefix("D-"))
    }

    func testIssueAssignsSequentialNumbersAndLocks() throws {
        let first = try draftInvoice()
        let second = try draftInvoice(price: 200)
        XCTAssertEqual(store.record(id: first.id)?.document.number, "", "Pas de numéro avant émission")

        let issuedFirst = try store.issue(id: first.id)
        let issuedSecond = try store.issue(id: second.id)
        XCTAssertTrue(issuedFirst.document.number.hasSuffix("0001"))
        XCTAssertTrue(issuedSecond.document.number.hasSuffix("0002"))
        XCTAssertEqual(issuedSecond.seal?.previousSealHash, issuedFirst.seal?.sealHash)

        var tampered = try XCTUnwrap(store.record(id: first.id))
        tampered.document.lines[0].unitPriceHT = 1
        XCTAssertThrowsError(try store.save(tampered))
        XCTAssertThrowsError(try store.delete(id: first.id))
        XCTAssertTrue(store.integrityReport().isEmpty)
    }

    func testDeletedDraftLeavesNoGap() throws {
        let abandoned = try draftInvoice()
        try store.delete(id: abandoned.id)
        let kept = try draftInvoice()
        XCTAssertTrue(try store.issue(id: kept.id).document.number.hasSuffix("0001"))
    }

    func testIssueRefusedWhenMandatoryDataMissing() throws {
        var record = store.makeInvoice(customer: nil)
        record.document.lines = [DocumentLine(designation: "A", unitPriceHT: 10)]
        try store.save(record)
        XCTAssertThrowsError(try store.issue(id: record.id)) { error in
            guard case StoreError.complianceBlocking = error else { return XCTFail("\(error)") }
        }
    }

    func testPaymentsAndCreditNote() throws {
        let invoice = try store.issue(id: try draftInvoice().id)
        try store.addPayment(invoiceID: invoice.id, payment: PaymentRecord(date: Date(), amount: 20))
        XCTAssertThrowsError(try store.addPayment(invoiceID: invoice.id, payment: PaymentRecord(date: Date(), amount: 1000)))

        let credit = try store.createCreditNote(invoiceID: invoice.id, partialAmountHT: 50, vatRate: 20, reason: "Geste commercial")
        let issuedCredit = try store.issue(id: credit.id)
        XCTAssertTrue(issuedCredit.document.number.hasPrefix("AV-"))
        let ledger = Accounting.ledger(for: try XCTUnwrap(store.record(id: invoice.id)), in: store.allRecords())
        XCTAssertEqual(ledger.balance, 40, "120 − 20 payés − 60 d'avoir")
    }

    func testQuoteToDepositAndFinalInvoice() throws {
        var quote = store.makeQuote(customer: try customer())
        quote.document.lines = [DocumentLine(designation: "Chantier", unitPriceHT: 1000, vatRate: 10)]
        try store.save(quote)
        try store.setQuoteStatus(id: quote.id, to: .sent)
        try store.setQuoteStatus(id: quote.id, to: .accepted)

        let deposit = try store.createDepositInvoice(quoteID: quote.id, amountTTC: 330)
        try store.issue(id: deposit.id)
        let final = try store.convertToInvoice(quoteID: quote.id)
        let totals = DocumentCalculator.totals(for: final.document)
        XCTAssertEqual(totals.totalTTC, 1100)
        XCTAssertEqual(totals.netToPay, 770)
    }

    func testBackupRestoreRoundTrip() throws {
        let invoice = try store.issue(id: try draftInvoice().id)
        let snapshot = store.makeSnapshot(appVersion: "test")
        let archive = try BackupService.makeArchive(snapshot, password: "motdepasse-test", iterations: 1000)

        try store.delete(id: try draftInvoice().id)
        let inspection = try BackupService.inspect(archive, password: "motdepasse-test")
        try store.restore(inspection.snapshot)

        XCTAssertEqual(store.record(id: invoice.id)?.document.number, invoice.document.number)
        XCTAssertTrue(store.integrityReport().isEmpty)
        let next = try store.issue(id: try draftInvoice().id)
        XCTAssertTrue(next.document.number.hasSuffix("0002"), "La numérotation reprend après la restauration")
    }
}
