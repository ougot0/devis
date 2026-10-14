import XCTest
@testable import DevisCore

final class BackupTests: XCTestCase {

    private func sampleSnapshot() -> BackupSnapshot {
        var invoice = Fixtures.invoice(lines: [Fixtures.line("Prestation 0,1", qty: "3", price: "0.1"), Fixtures.line("Pose", qty: "1.25", price: "33.3333")])
        invoice.number = "F-2026-0001"
        let seal = DocumentSealer.seal(invoice, previousSealHash: "", sealedAt: Fixtures.date(2026, 10, 1))
        let customer = CustomerRecord(snapshot: Fixtures.businessCustomer, notes: "Client fidèle — « VIP »")
        let record = DocumentRecord(document: invoice, invoiceStatus: .issued, payments: [PaymentRecord(date: Fixtures.date(2026, 10, 5), amount: .exact("12.34"))], seal: seal, customerID: customer.id, issuedAt: Fixtures.date(2026, 10, 1))
        return BackupSnapshot(createdAt: Fixtures.date(2026, 10, 14), appVersion: "1.0", company: Fixtures.companySeller, customers: [customer],
                              catalog: [CatalogItem(name: "Heure", price: .exact("45.5"), vatRate: .exact("5.5"), unitCost: .exact("0.1"))],
                              documents: [record], numbering: ["invoice": NumberingState(lastSequence: 1, lastYear: 2026, lastIssueDate: Fixtures.date(2026, 10, 1), lastNumber: "F-2026-0001")],
                              settings: Data("{\"template\":\"classique\"}".utf8), logo: Data([0xFF, 0xD8, 0xFF]))
    }

    func testPlainRoundTripPreservesEverythingExactly() throws {
        let snapshot = sampleSnapshot()
        let archive = try BackupService.makeArchive(snapshot, password: nil)
        let inspection = try BackupService.inspect(archive, password: nil)
        XCTAssertEqual(inspection.snapshot, snapshot)
        XCTAssertTrue(inspection.warnings.isEmpty, "\(inspection.warnings)")
        XCTAssertEqual(inspection.snapshot.documents[0].document.lines[0].unitPriceHT, .exact("0.1"))
        XCTAssertTrue(DocumentSealer.verify(inspection.snapshot.documents[0].document, seal: inspection.snapshot.documents[0].seal!))
    }

    func testEncryptedRoundTrip() throws {
        let snapshot = sampleSnapshot()
        let archive = try BackupService.makeArchive(snapshot, password: "correct horse battery", iterations: 1000)
        XCTAssertFalse(String(decoding: archive, as: UTF8.self).contains("Boulangerie"), "Le contenu ne doit pas apparaître en clair")
        XCTAssertNotNil(try BackupService.readEnvelope(archive).encryption)
        XCTAssertThrowsError(try BackupService.inspect(archive, password: nil)) { XCTAssertEqual($0 as? BackupError, .passwordRequired) }
        XCTAssertThrowsError(try BackupService.inspect(archive, password: "mauvais mot de passe")) { XCTAssertEqual($0 as? BackupError, .wrongPasswordOrCorrupted) }
        XCTAssertEqual(try BackupService.inspect(archive, password: "correct horse battery").snapshot, snapshot)
    }

    func testWeakPasswordRejected() {
        XCTAssertThrowsError(try BackupService.makeArchive(sampleSnapshot(), password: "court", iterations: 10)) { XCTAssertEqual($0 as? BackupError, .weakPassword) }
    }

    func testTamperedPlainArchiveIsRejected() throws {
        let archive = try BackupService.makeArchive(sampleSnapshot(), password: nil)
        var envelope = try BackupService.readEnvelope(archive)
        var text = String(decoding: envelope.payload, as: UTF8.self)
        text = text.replacingOccurrences(of: "Boulangerie", with: "Patisserie")
        envelope.payload = Data(text.utf8)
        let tampered = try BackupService.encoder().encode(envelope)
        XCTAssertThrowsError(try BackupService.inspect(tampered, password: nil)) { XCTAssertEqual($0 as? BackupError, .integrityCheckFailed) }
    }

    func testTamperedEncryptedArchiveIsRejected() throws {
        let archive = try BackupService.makeArchive(sampleSnapshot(), password: "motdepasse-solide", iterations: 500)
        var envelope = try BackupService.readEnvelope(archive)
        envelope.payload[envelope.payload.count / 2] ^= 0x01
        let tampered = try BackupService.encoder().encode(envelope)
        XCTAssertThrowsError(try BackupService.inspect(tampered, password: "motdepasse-solide")) { XCTAssertEqual($0 as? BackupError, .wrongPasswordOrCorrupted) }
    }

    func testNotABackupAndFutureVersion() throws {
        XCTAssertThrowsError(try BackupService.readEnvelope(Data("bonjour".utf8))) { XCTAssertEqual($0 as? BackupError, .notABackup) }
        var envelope = try BackupService.readEnvelope(try BackupService.makeArchive(sampleSnapshot(), password: nil))
        envelope.version = 99
        XCTAssertThrowsError(try BackupService.readEnvelope(try BackupService.encoder().encode(envelope))) { XCTAssertEqual($0 as? BackupError, .unsupportedVersion(99)) }
    }

    func testValidationDetectsDuplicatesAndBrokenSeals() throws {
        var snapshot = sampleSnapshot()
        snapshot.documents[0].document.lines[0].unitPriceHT = 99
        XCTAssertTrue(try BackupService.validate(snapshot).contains { $0.contains("sceau") })
        var duplicate = snapshot.documents[0]
        duplicate.document.id = UUID()
        snapshot.documents.append(duplicate)
        XCTAssertThrowsError(try BackupService.validate(snapshot))
    }

    func testPBKDF2KnownVectors() {
        // Vecteurs PBKDF2-HMAC-SHA256 publiés (RFC 7914, §11 et jeux de test courants).
        let one = PBKDF2.deriveKey(password: "password", salt: Data("salt".utf8), iterations: 1, length: 32)
        XCTAssertEqual(one.map { String(format: "%02x", $0) }.joined(), "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b")
        let two = PBKDF2.deriveKey(password: "password", salt: Data("salt".utf8), iterations: 2, length: 32)
        XCTAssertEqual(two.map { String(format: "%02x", $0) }.joined(), "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43")
        let long = PBKDF2.deriveKey(password: "passwd", salt: Data("salt".utf8), iterations: 1, length: 64)
        XCTAssertEqual(long.map { String(format: "%02x", $0) }.joined(), "55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783")
    }
}

final class CSVTests: XCTestCase {

    func testEscapingAndFormulaInjection() {
        XCTAssertEqual(CSV.escape("simple"), "simple")
        XCTAssertEqual(CSV.escape("a;b"), "\"a;b\"")
        XCTAssertEqual(CSV.escape("il a dit \"oui\""), "\"il a dit \"\"oui\"\"\"")
        XCTAssertEqual(CSV.escape("=SOMME(A1)"), "'=SOMME(A1)")
        XCTAssertEqual(CSV.escape("-12,50"), "-12,50", "Un nombre négatif n'est pas une formule")
    }

    func testRoundTripParse() {
        let data = CSV.make(header: ["A", "B"], rows: [["1;2", "ligne\nsuivante"], ["\"q\"", ""]])
        XCTAssertEqual(Array(data.prefix(3)), [0xEF, 0xBB, 0xBF])
        XCTAssertEqual(CSV.parse(data), [["A", "B"], ["1;2", "ligne\nsuivante"], ["\"q\"", ""]])
    }

    func testInvoiceExport() {
        var invoice = Fixtures.invoice(lines: [Fixtures.line("A", qty: "1", price: "100")])
        invoice.number = "F-2026-0001"
        let record = DocumentRecord(document: invoice, invoiceStatus: .issued, payments: [PaymentRecord(date: Fixtures.date(2026, 10, 2), amount: 50)])
        let draft = DocumentRecord(document: Fixtures.invoice(lines: [Fixtures.line("B", qty: "1", price: "1")]))
        let rows = CSV.parse(CSVExporter.invoices([record, draft], today: Fixtures.date(2026, 10, 10)))
        XCTAssertEqual(rows.count, 2, "Les brouillons ne sont pas exportés")
        XCTAssertEqual(rows[1][1], "F-2026-0001")
        XCTAssertEqual(rows[1][8], "120,00")
        XCTAssertEqual(rows[1][13], "70,00")
        XCTAssertEqual(rows[1][14], "Partiellement payée")
    }

    func testCustomerImport() {
        let csv = "Nom,Ville,Email,SIREN,Type\nDupont SARL,Lyon,a@b.fr,552 100 554,Professionnel\n,Paris,,,\nMme Martin,Nantes,,,Particulier\n"
        let result = CSVImporter.customers(Data(csv.utf8))
        XCTAssertEqual(result.items.count, 2)
        XCTAssertEqual(result.items[0].snapshot.siren, "552100554")
        XCTAssertEqual(result.items[1].snapshot.kind, .individual)
        XCTAssertEqual(result.skipped.first?.line, 3)
    }

    func testCatalogImportAndExportRoundTrip() {
        let items = [CatalogItem(name: "Heure de conseil", category: "Conseil", price: .exact("80.5"), vatRate: 20, unit: "h", unitCost: 30),
                     CatalogItem(name: "Câble ; 2 m", price: 12, priceIncludesVAT: true, vatRate: .exact("5.5"), nature: .goods)]
        let result = CSVImporter.catalog(CSVExporter.catalog(items))
        XCTAssertEqual(result.items.count, 2)
        XCTAssertEqual(result.items[0].price, .exact("80.5"))
        XCTAssertEqual(result.items[0].unitCost, 30)
        XCTAssertEqual(result.items[1].name, "Câble ; 2 m")
        XCTAssertTrue(result.items[1].priceIncludesVAT)
        XCTAssertEqual(result.items[1].vatRate, .exact("5.5"))
        XCTAssertEqual(result.items[1].nature, .goods)
        let invalid = CSVImporter.catalog(Data("Nom;Prix\nA;abc\n".utf8))
        XCTAssertEqual(invalid.items.count, 0)
        XCTAssertEqual(invalid.skipped.count, 1)
    }
}

final class StatisticsTests: XCTestCase {

    private func issued(_ number: String, _ date: Date, price: String, kind: DocumentKind = .invoice, payments: [PaymentRecord] = [], corrected: String = "", due: Date? = nil) -> DocumentRecord {
        var document = Fixtures.invoice(lines: [Fixtures.line("Prestation \(number)", qty: "1", price: price)])
        document.kind = kind
        document.number = number
        document.issueDate = date
        document.dueDate = due ?? Calendar.devisMinute.date(byAdding: .day, value: 30, to: date)
        document.correctedInvoiceNumber = corrected
        return DocumentRecord(document: document, invoiceStatus: .issued, payments: payments)
    }

    func testEmptyDataProducesZerosNotFakeNumbers() {
        let report = StatisticsEngine.report(records: [], months: 6, today: Fixtures.date(2026, 10, 14))
        XCTAssertEqual(report.invoicedHTByMonth.count, 6)
        XCTAssertTrue(report.invoicedHTByMonth.allSatisfy { $0.amount == 0 })
        XCTAssertNil(report.conversionRate)
        XCTAssertTrue(report.byCustomer.isEmpty)
    }

    func testMonthlySeriesAndCreditNotes() {
        let records = [
            issued("F1", Fixtures.date(2026, 9, 3), price: "1000", payments: [PaymentRecord(date: Fixtures.date(2026, 10, 2), amount: 1200)]),
            issued("F2", Fixtures.date(2026, 10, 3), price: "500"),
            issued("AV1", Fixtures.date(2026, 10, 5), price: "100", kind: .creditNote, corrected: "F2"),
            DocumentRecord(document: Fixtures.invoice(lines: [Fixtures.line("Brouillon", qty: "1", price: "9999")])),
        ]
        let report = StatisticsEngine.report(records: records, months: 3, today: Fixtures.date(2026, 10, 14))
        XCTAssertEqual(report.invoicedHTByMonth.map(\.amount), [0, 1000, 400])
        XCTAssertEqual(report.collectedByMonth.map(\.amount), [0, 0, 1200])
        XCTAssertEqual(report.totalInvoicedHT, 1400)

        let dashboard = StatisticsEngine.dashboard(records: records, customerCount: 3, period: nil, today: Fixtures.date(2026, 10, 14))
        XCTAssertEqual(dashboard.invoicedTTC, 1680)
        XCTAssertEqual(dashboard.collectedTTC, 1200)
        XCTAssertEqual(dashboard.outstandingTTC, 480, "F2 : 600 TTC − avoir 120")
        XCTAssertEqual(dashboard.unpaidInvoicesCount, 1)
        XCTAssertEqual(dashboard.overdueInvoicesCount, 0)
    }

    func testOverdueAndPendingQuotes() {
        var quote = Fixtures.invoice(lines: [Fixtures.line("Q", qty: "1", price: "100")])
        quote.kind = .quote
        quote.validUntil = Fixtures.date(2026, 12, 1)
        var expiredQuote = quote
        expiredQuote.id = UUID()
        expiredQuote.validUntil = Fixtures.date(2026, 9, 1)
        let records = [
            issued("F1", Fixtures.date(2026, 8, 1), price: "100", due: Fixtures.date(2026, 9, 1)),
            DocumentRecord(document: quote, quoteStatus: .sent),
            DocumentRecord(document: expiredQuote, quoteStatus: .sent),
        ]
        let dashboard = StatisticsEngine.dashboard(records: records, customerCount: 1, period: nil, today: Fixtures.date(2026, 10, 14))
        XCTAssertEqual(dashboard.overdueTTC, 120)
        XCTAssertEqual(dashboard.pendingQuotesCount, 1, "Un devis expiré n'est plus en attente")
        XCTAssertEqual(dashboard.pendingQuotesTTC, 120)
    }

    func testDepositsAreNotDoubleCounted() {
        let deposit = issued("F1", Fixtures.date(2026, 10, 1), price: "300", kind: .depositInvoice)
        var final = issued("F2", Fixtures.date(2026, 10, 10), price: "1000")
        final.document.depositDeductions = [DepositDeduction(invoiceNumber: "F1", issueDate: Fixtures.date(2026, 10, 1), amountTTC: 360)]
        let report = StatisticsEngine.report(records: [deposit, final], months: 1, today: Fixtures.date(2026, 10, 14))
        XCTAssertEqual(report.totalInvoicedHT, 1000)
        let dashboard = StatisticsEngine.dashboard(records: [deposit, final], customerCount: 1, period: nil, today: Fixtures.date(2026, 10, 14))
        XCTAssertEqual(dashboard.invoicedTTC, 1200)
    }

    func testConversionRateNeedsEnoughData() {
        func quote(_ status: QuoteStatus) -> DocumentRecord {
            var document = Fixtures.invoice(lines: [Fixtures.line("Q", qty: "1", price: "10")])
            document.kind = .quote
            document.id = UUID()
            document.issueDate = Fixtures.date(2026, 10, 1)
            document.validUntil = Fixtures.date(2026, 12, 1)
            return DocumentRecord(document: document, quoteStatus: status)
        }
        let few = [quote(.accepted), quote(.refused)]
        XCTAssertNil(StatisticsEngine.report(records: few, months: 1, today: Fixtures.date(2026, 10, 14)).conversionRate)
        let enough = [quote(.accepted), quote(.accepted), quote(.accepted), quote(.refused), quote(.refused), quote(.sent)]
        let report = StatisticsEngine.report(records: enough, months: 1, today: Fixtures.date(2026, 10, 14))
        XCTAssertEqual(report.conversionRate, 60)
        XCTAssertEqual(report.pendingQuotes, 1)
    }
}

final class ProfitabilityTests: XCTestCase {

    func testMarginAndMarkup() {
        let result = ProfitabilityCalculator.compute(ProfitabilityInput(salePriceHT: 150, unitCostHT: 100, discountPercent: 0, quantity: 10))
        XCTAssertEqual(result.unitMargin, 50)
        XCTAssertEqual(result.marginRate, 50)
        XCTAssertEqual(result.markupRate, .exact("33.33"))
        XCTAssertEqual(result.multiplier, 1.5)
        XCTAssertEqual(result.revenueHT, 1500)
        XCTAssertEqual(result.estimatedGrossProfit, 500)
        XCTAssertFalse(result.isLossMaking)
    }

    func testDiscountAndLoss() {
        let result = ProfitabilityCalculator.compute(ProfitabilityInput(salePriceHT: 100, unitCostHT: 95, discountPercent: 10))
        XCTAssertEqual(result.netSalePriceHT, 90)
        XCTAssertEqual(result.unitMargin, -5)
        XCTAssertTrue(result.isLossMaking)
        XCTAssertEqual(ProfitabilityCalculator.maximumDiscount(salePriceHT: 100, unitCostHT: 95), 5)
    }

    func testZeroCostAndInverseCalculations() {
        let result = ProfitabilityCalculator.compute(ProfitabilityInput(salePriceHT: 80, unitCostHT: 0))
        XCTAssertNil(result.marginRate)
        XCTAssertEqual(result.markupRate, 100)
        XCTAssertEqual(ProfitabilityCalculator.price(forMarginRate: 25, cost: 80), 100)
        XCTAssertEqual(ProfitabilityCalculator.price(forMarkupRate: 20, cost: 80), 100)
        XCTAssertNil(ProfitabilityCalculator.price(forMarkupRate: 100, cost: 80))
    }
}

final class CatalogAndCIITests: XCTestCase {

    func testCatalogTTCConversion() {
        let item = CatalogItem(name: "Forfait", price: 120, priceIncludesVAT: true, vatRate: 20)
        XCTAssertEqual(item.unitPriceHT, 100)
        let line = item.makeLine(quantity: 2)
        XCTAssertEqual(line.catalogItemID, item.id)
        XCTAssertEqual(line.unitPriceHT, 100)
        let franchise = item.makeLine(sellerChargesVAT: false)
        XCTAssertEqual(franchise.unitPriceHT, 120)
        XCTAssertEqual(franchise.vatRate, 0)
    }

    func testCIIContainsKeyFields() {
        var invoice = Fixtures.invoice(lines: [Fixtures.line("Conseil & <audit>", qty: "2", price: "150")], discount: .percent(10))
        invoice.number = "F-2026-0007"
        let xml = String(decoding: CIIExporter.xml(for: invoice), as: UTF8.self)
        XCTAssertTrue(xml.contains("<ram:ID>F-2026-0007</ram:ID>"))
        XCTAssertTrue(xml.contains("<ram:TypeCode>380</ram:TypeCode>"))
        XCTAssertTrue(xml.contains("Conseil &amp; &lt;audit&gt;"))
        XCTAssertTrue(xml.contains("<ram:TaxBasisTotalAmount>270.00</ram:TaxBasisTotalAmount>"))
        XCTAssertTrue(xml.contains("<ram:GrandTotalAmount>324.00</ram:GrandTotalAmount>"))
        XCTAssertTrue(xml.contains("schemeID=\"0002\">552100554"))
        XCTAssertTrue(xml.contains("Préparatoire"))

        var franchise = Fixtures.invoice(lines: [Fixtures.line("Logo", qty: "1", price: "500")], seller: Fixtures.microSeller)
        franchise.number = "F-1"
        let franchiseXML = String(decoding: CIIExporter.xml(for: franchise), as: UTF8.self)
        XCTAssertTrue(franchiseXML.contains("<ram:CategoryCode>E</ram:CategoryCode>"))
        XCTAssertTrue(franchiseXML.contains("VATEX-FR-FRANCHISE"))
    }

    func testCIIIsWellFormedXML() throws {
        var invoice = Fixtures.invoice(lines: [Fixtures.line("A", qty: "1", price: "10")])
        invoice.number = "F-1"
        invoice.customer.deliveryAddress = PostalAddress(line1: "Entrepôt", postalCode: "13000", city: "Marseille")
        let xml = String(decoding: CIIExporter.xml(for: invoice), as: UTF8.self)
        XCTAssertEqual(xml.components(separatedBy: "<ram:PostalTradeAddress>").count, xml.components(separatedBy: "</ram:PostalTradeAddress>").count)
        XCTAssertTrue(xml.contains("<ram:ShipToTradeParty>"))
    }

    func testGatewayNotConfigured() async {
        do {
            _ = try await NoEInvoicingGateway().submit(document: Fixtures.invoice(lines: []), structuredData: Data(), pdf: Data())
            XCTFail("doit échouer")
        } catch {
            XCTAssertTrue(error is EInvoicingError)
        }
    }
}
