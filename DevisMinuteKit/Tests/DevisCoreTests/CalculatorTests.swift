import XCTest
@testable import DevisCore

final class CalculatorTests: XCTestCase {

    func testSimpleLine() {
        let doc = Fixtures.invoice(lines: [Fixtures.line("Pose", qty: "3", price: "45.50")])
        let totals = DocumentCalculator.totals(for: doc)
        XCTAssertEqual(totals.totalHT, .exact("136.50"))
        XCTAssertEqual(totals.totalVAT, .exact("27.30"))
        XCTAssertEqual(totals.totalTTC, .exact("163.80"))
        XCTAssertEqual(totals.netToPay, totals.totalTTC)
    }

    func testLineRoundingWithFractionalQuantity() {
        // 1,333 h × 37,50 € = 49,9875 → 49,99 (R2)
        let doc = Fixtures.invoice(lines: [Fixtures.line("Heures", qty: "1.333", price: "37.50")])
        XCTAssertEqual(DocumentCalculator.totals(for: doc).totalHT, .exact("49.99"))
    }

    func testVATIsComputedPerRateNotPerLine() {
        // 3 lignes à 0,10 € HT : TVA par ligne = 3 × 0,02 = 0,06 ; TVA par taux = 0,30 × 20 % = 0,06.
        // 3 lignes à 0,33 € : par ligne 3 × 0,07 = 0,21 ; par taux 0,99 × 20 % = 0,198 → 0,20 (R4).
        let doc = Fixtures.invoice(lines: (0..<3).map { _ in Fixtures.line("Article", qty: "1", price: "0.33") })
        let totals = DocumentCalculator.totals(for: doc)
        XCTAssertEqual(totals.totalHT, .exact("0.99"))
        XCTAssertEqual(totals.totalVAT, .exact("0.20"))
        XCTAssertEqual(totals.totalTTC, .exact("1.19"))
    }

    func testMultipleVATRates() {
        let doc = Fixtures.invoice(lines: [
            Fixtures.line("Main d'œuvre", qty: "10", price: "40", vat: "10"),
            Fixtures.line("Fournitures", qty: "1", price: "199.99", vat: "20"),
            Fixtures.line("Isolation", qty: "12.5", price: "18.40", vat: "5.5"),
        ])
        let totals = DocumentCalculator.totals(for: doc)
        XCTAssertEqual(totals.vatBuckets.map(\.rate), [20, 10, .exact("5.5")])
        XCTAssertEqual(totals.vatBuckets.map(\.baseHT), [.exact("199.99"), 400, 230])
        XCTAssertEqual(totals.vatBuckets.map(\.vatAmount), [40, 40, .exact("12.65")])
        XCTAssertEqual(totals.totalHT, .exact("829.99"))
        XCTAssertEqual(totals.totalVAT, .exact("92.65"))
        XCTAssertEqual(totals.totalTTC, .exact("922.64"))
    }

    func testLineDiscountPercentAndAmount() {
        let doc = Fixtures.invoice(lines: [
            Fixtures.line("A", qty: "2", price: "100", discount: .percent(15)),
            Fixtures.line("B", qty: "1", price: "50", discount: .amount(.exact("7.5"))),
        ])
        let totals = DocumentCalculator.totals(for: doc)
        XCTAssertEqual(totals.subtotalHT, .exact("212.50"))
        XCTAssertEqual(totals.totalDiscountHT, .exact("37.50"))
    }

    func testDiscountIsCappedAtLineAmount() {
        let doc = Fixtures.invoice(lines: [Fixtures.line("A", qty: "1", price: "10", discount: .amount(25))])
        XCTAssertEqual(DocumentCalculator.totals(for: doc).totalHT, 0)
        let over = Fixtures.invoice(lines: [Fixtures.line("A", qty: "1", price: "10", discount: .percent(150))])
        XCTAssertEqual(DocumentCalculator.totals(for: over).totalHT, 0)
    }

    func testCumulatedLineAndGlobalDiscountsAcrossRates() {
        // Remise de ligne puis remise globale 10 % répartie au prorata des taux.
        let doc = Fixtures.invoice(lines: [
            Fixtures.line("A", qty: "1", price: "333.33", vat: "20", discount: .percent(5)),
            Fixtures.line("B", qty: "1", price: "100", vat: "5.5"),
        ], discount: .percent(10))
        let totals = DocumentCalculator.totals(for: doc)
        // A : 333,33 − 16,67 = 316,66 ; sous-total 416,66 ; remise globale 41,67
        XCTAssertEqual(totals.subtotalHT, .exact("416.66"))
        XCTAssertEqual(totals.globalDiscountHT, .exact("41.67"))
        XCTAssertEqual(totals.totalHT, .exact("374.99"))
        XCTAssertEqual(totals.vatBuckets.reduce(0) { $0 + $1.baseHT }, totals.totalHT, "La somme des bases doit égaler le total HT")
        XCTAssertEqual(totals.totalTTC, totals.totalHT + totals.totalVAT)
    }

    func testGlobalAmountDiscount() {
        let doc = Fixtures.invoice(lines: [Fixtures.line("A", qty: "1", price: "1000")], discount: .amount(100))
        let totals = DocumentCalculator.totals(for: doc)
        XCTAssertEqual(totals.totalHT, 900)
        XCTAssertEqual(totals.totalVAT, 180)
    }

    func testFranchiseHasNoVATEvenIfLinesHaveRates() {
        let doc = Fixtures.invoice(lines: [Fixtures.line("Logo", qty: "1", price: "450", vat: "20")], seller: Fixtures.microSeller)
        let totals = DocumentCalculator.totals(for: doc)
        XCTAssertEqual(totals.totalVAT, 0)
        XCTAssertEqual(totals.totalTTC, 450)
        XCTAssertEqual(totals.vatBuckets.map(\.rate), [0])
        let mentions = LegalMentionsBuilder.mentions(for: doc, totals: totals)
        XCTAssertTrue(mentions.contains(LegalTexts.franchiseMention))
    }

    func testReverseChargeHasNoVATAndMention() {
        var doc = Fixtures.invoice(lines: [Fixtures.line("Sous-traitance", qty: "1", price: "5000")])
        doc.reverseCharge = true
        let totals = DocumentCalculator.totals(for: doc)
        XCTAssertEqual(totals.totalVAT, 0)
        XCTAssertTrue(LegalMentionsBuilder.mentions(for: doc, totals: totals).contains(LegalTexts.reverseChargeMention))
    }

    func testSectionAndNoteLinesAreIgnored() {
        let doc = Fixtures.invoice(lines: [
            .section("Lot 1"),
            Fixtures.line("A", qty: "1", price: "10"),
            DocumentLine(kind: .note, designation: "Texte", quantity: 99, unitPriceHT: 99),
        ])
        XCTAssertEqual(DocumentCalculator.totals(for: doc).totalHT, 10)
    }

    func testEmptyDocument() {
        let totals = DocumentCalculator.totals(for: Fixtures.invoice(lines: []))
        XCTAssertEqual(totals.totalTTC, 0)
        XCTAssertTrue(totals.vatBuckets.isEmpty)
    }

    func testRequestedDepositOnQuote() {
        var quote = Fixtures.invoice(lines: [Fixtures.line("A", qty: "1", price: "1000")])
        quote.kind = .quote
        quote.depositRequest = .percent(30)
        XCTAssertEqual(DocumentCalculator.totals(for: quote).requestedDepositTTC, 360)
        quote.depositRequest = .amount(5000)
        XCTAssertEqual(DocumentCalculator.totals(for: quote).requestedDepositTTC, 1200, "Plafonné au TTC")
    }

    func testDepositLinesFollowVATBreakdown() {
        var quote = Fixtures.invoice(lines: [
            Fixtures.line("Main d'œuvre", qty: "1", price: "1000", vat: "10"),
            Fixtures.line("Matériel", qty: "1", price: "500", vat: "20"),
        ])
        quote.kind = .quote
        quote.number = "D-2026-0001"
        let quoteTotals = DocumentCalculator.totals(for: quote)
        XCTAssertEqual(quoteTotals.totalTTC, 1700)
        let lines = DocumentCalculator.depositLines(for: quote, depositTTC: 510)
        XCTAssertEqual(lines.count, 2)
        var deposit = quote
        deposit.kind = .depositInvoice
        deposit.lines = lines
        let depositTotals = DocumentCalculator.totals(for: deposit)
        XCTAssertEqual(depositTotals.totalTTC, 510, "Le TTC de la facture d'acompte doit être exactement l'acompte")
        XCTAssertTrue(lines[0].designation.contains("30 %"))
        XCTAssertTrue(lines[0].designation.contains("D-2026-0001"))
    }

    func testDepositLinesRandomizedWithinOneCent() {
        for cents in stride(from: 1, through: 50_000, by: 997) {
            var quote = Fixtures.invoice(lines: [
                Fixtures.line("A", qty: "1", price: "1234.56", vat: "20"),
                Fixtures.line("B", qty: "3", price: "77.77", vat: "5.5"),
                Fixtures.line("C", qty: "2", price: "19.99", vat: "10"),
            ])
            quote.kind = .quote
            let target = Decimal(cents) / 100
            var deposit = quote
            deposit.lines = DocumentCalculator.depositLines(for: quote, depositTTC: target)
            let gap = abs(DocumentCalculator.totals(for: deposit).totalTTC - target)
            XCTAssertLessThanOrEqual(gap, .exact("0.01"), "acompte \(target) : écart maximal d'un centime (règle R6)")
        }
    }

    func testFinalInvoiceDeductsDeposits() {
        var invoice = Fixtures.invoice(lines: [Fixtures.line("A", qty: "1", price: "1000")])
        invoice.depositDeductions = [DepositDeduction(invoiceNumber: "F-2026-0003", issueDate: Fixtures.date(2026, 9, 1), amountTTC: 360)]
        let totals = DocumentCalculator.totals(for: invoice)
        XCTAssertEqual(totals.totalTTC, 1200)
        XCTAssertEqual(totals.depositsDeductedTTC, 360)
        XCTAssertEqual(totals.netToPay, 840)
    }

    func testPriceConversions() {
        XCTAssertEqual(DocumentCalculator.priceHT(fromTTC: 120, vatRate: 20), 100)
        XCTAssertEqual(DocumentCalculator.priceHT(fromTTC: 10, vatRate: .exact("5.5")), .exact("9.4787"))
        XCTAssertEqual(DocumentCalculator.priceTTC(fromHT: .exact("9.4787"), vatRate: .exact("5.5")), 10)
    }

    func testLargeAmountsKeepPrecision() {
        let doc = Fixtures.invoice(lines: [Fixtures.line("Chantier", qty: "1", price: "9999999.99")])
        let totals = DocumentCalculator.totals(for: doc)
        XCTAssertEqual(totals.totalTTC, .exact("11999999.99"))
    }
}
