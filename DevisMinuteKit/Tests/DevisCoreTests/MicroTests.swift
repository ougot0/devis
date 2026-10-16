import XCTest
@testable import DevisCore

final class MicroTests: XCTestCase {
    private func paidInvoice(lines: [DocumentLine], paid: Decimal, on date: Date, seller: CompanyProfile = Fixtures.microSeller) -> DocumentRecord {
        var document = Fixtures.invoice(lines: lines, seller: seller)
        document.number = "F-\(UUID().uuidString.prefix(4))"
        return DocumentRecord(document: document, invoiceStatus: .issued, payments: [PaymentRecord(date: date, amount: paid)])
    }

    func testRevenueSplitsGoodsAndServicesByPayment() {
        var goods = Fixtures.line("Meuble", qty: "1", price: "600", vat: "0")
        goods.nature = .goods
        let services = Fixtures.line("Pose", qty: "1", price: "400", vat: "0")
        let record = paidInvoice(lines: [goods, services], paid: 500, on: Fixtures.date(2026, 10, 10))
        let october = MicroCalculator.period(containing: Fixtures.date(2026, 10, 20), frequency: .monthly)
        let revenue = MicroCalculator.revenue(records: [record], in: october)
        XCTAssertEqual(revenue.goods, 300)
        XCTAssertEqual(revenue.services, 200)
        let september = MicroCalculator.period(containing: Fixtures.date(2026, 9, 20), frequency: .monthly)
        XCTAssertEqual(MicroCalculator.revenue(records: [record], in: september).total, 0, "Seuls les encaissements de la période comptent")
    }

    func testRevenueIsHTWhenVATIsCharged() {
        let record = paidInvoice(lines: [Fixtures.line("Pose", qty: "1", price: "1000")], paid: 600, on: Fixtures.date(2026, 10, 10), seller: Fixtures.companySeller)
        let revenue = MicroCalculator.revenue(records: [record], in: MicroCalculator.period(containing: Fixtures.date(2026, 10, 1), frequency: .quarterly))
        XCTAssertEqual(revenue.services, 500)
    }

    func testQuarterlyDeclarationWithRates() {
        let record = paidInvoice(lines: [Fixtures.line("Prestation", qty: "1", price: "10000", vat: "0")], paid: 10000, on: Fixtures.date(2026, 8, 15))
        let period = MicroCalculator.period(containing: Fixtures.date(2026, 8, 15), frequency: .quarterly)
        let declaration = MicroCalculator.declaration(records: [record], period: period, settings: MicroSettings(servicesKind: .commercial, frequency: .quarterly, versementLiberatoire: true), isCraftsman: true)
        XCTAssertEqual(declaration.title, "3e trimestre 2026")
        XCTAssertEqual(DateFormatting.short(declaration.dueDate), "31/10/2026")
        XCTAssertEqual(declaration.lines.map(\.amount), [2120, 30, 170], "21,2 % + CFP artisan 0,3 % + VL 1,7 %")
        XCTAssertEqual(declaration.total, 2320)
        let liberal = MicroCalculator.declaration(records: [record], period: period, settings: MicroSettings(servicesKind: .liberal), isCraftsman: false)
        XCTAssertEqual(liberal.lines.map(\.amount), [2560, 20])
    }

    func testMonthlyPeriodsAndDueDates() {
        let period = MicroCalculator.period(containing: Fixtures.date(2026, 12, 3), frequency: .monthly)
        XCTAssertEqual(MicroCalculator.title(for: period, frequency: .monthly), "Décembre 2026")
        XCTAssertEqual(DateFormatting.short(MicroCalculator.dueDate(for: period)), "31/01/2027")
        let previous = MicroCalculator.previousPeriod(before: period, frequency: .monthly)
        XCTAssertEqual(DateFormatting.short(MicroCalculator.dueDate(for: previous)), "31/12/2026")
        let q1 = MicroCalculator.period(containing: Fixtures.date(2026, 2, 10), frequency: .quarterly)
        XCTAssertEqual(MicroCalculator.title(for: q1, frequency: .quarterly), "1er trimestre 2026")
        XCTAssertEqual(DateFormatting.short(MicroCalculator.dueDate(for: q1)), "30/04/2026")
    }

    func testThresholdAlerts() {
        let near = paidInvoice(lines: [Fixtures.line("Prestation", qty: "1", price: "32000", vat: "0")], paid: 32000, on: Fixtures.date(2026, 6, 1))
        var statuses = MicroCalculator.thresholds(records: [near], year: 2026, franchise: true)
        XCTAssertEqual(statuses.first { $0.title == "Franchise de TVA" }?.level, .approaching)
        XCTAssertEqual(statuses.first { $0.title == "Plafond micro — services" }?.level, .ok)
        let over = paidInvoice(lines: [Fixtures.line("Prestation", qty: "1", price: "42000", vat: "0")], paid: 42000, on: Fixtures.date(2026, 6, 1))
        statuses = MicroCalculator.thresholds(records: [over], year: 2026, franchise: true)
        XCTAssertEqual(statuses.first { $0.title == "Franchise de TVA" }?.level, .critical)
        XCTAssertFalse(MicroCalculator.thresholds(records: [over], year: 2026, franchise: false).contains { $0.title.hasPrefix("Franchise") })
    }
}
