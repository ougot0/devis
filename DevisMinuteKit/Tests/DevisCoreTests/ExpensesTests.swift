import XCTest
@testable import DevisCore

final class ExpensesTests: XCTestCase {
    func testVATFromTTC() {
        XCTAssertEqual(ExpenseRecord.vat(fromTTC: 120, rate: 20), 20)
        XCTAssertEqual(ExpenseRecord.vat(fromTTC: 55, rate: 10), 5)
        XCTAssertEqual(ExpenseRecord.vat(fromTTC: Decimal.exact("10.55"), rate: Decimal.exact("5.5")), Decimal.exact("0.55"))
        XCTAssertEqual(ExpenseRecord.vat(fromTTC: 99, rate: 0), 0)
    }

    func testValidation() {
        XCTAssertThrowsError(try ExpenseRecord(date: Date(), amountTTC: 0).validate())
        XCTAssertThrowsError(try ExpenseRecord(date: Date(), amountTTC: 10, vatAmount: 10).validate())
        XCTAssertNoThrow(try ExpenseRecord(date: Date(), amountTTC: 12, vatAmount: 2).validate())
    }

    func testProfitUsesHTWhenVATIsRecoverable() {
        var invoice = Fixtures.invoice(lines: [Fixtures.line("Prestation", qty: "1", price: "1000")])
        invoice.number = "F-1"
        let issued = DocumentRecord(document: invoice, invoiceStatus: .issued)
        let expenses = [
            ExpenseRecord(date: Fixtures.date(2026, 10, 3), category: .materials, amountTTC: 240, vatAmount: 40),
            ExpenseRecord(date: Fixtures.date(2026, 10, 9), category: .travel, amountTTC: 60, vatAmount: 10),
            ExpenseRecord(date: Fixtures.date(2025, 1, 9), category: .travel, amountTTC: 999, vatAmount: 0),
        ]
        let october = DateInterval(start: Fixtures.date(2026, 10, 1), end: Fixtures.date(2026, 11, 1))
        let standard = ProfitCalculator.summary(records: [issued], expenses: expenses, interval: october, vatRecoverable: true)
        XCTAssertEqual(standard.revenueHT, 1000)
        XCTAssertEqual(standard.expenses, 250)
        XCTAssertEqual(standard.profit, 750)
        XCTAssertEqual(standard.marginRate, 75)
        XCTAssertEqual(standard.expensesByCategory.first?.category, .materials)
        let franchise = ProfitCalculator.summary(records: [issued], expenses: expenses, interval: october, vatRecoverable: false)
        XCTAssertEqual(franchise.expenses, 300, "Sans TVA récupérable, la dépense coûte son prix TTC")
    }

    func testCSVAndBackupCompatibility() throws {
        let csv = String(decoding: CSVExporter.expenses([ExpenseRecord(date: Fixtures.date(2026, 10, 3), supplier: "Leroy", category: .materials, amountTTC: 120, vatAmount: 20)]), as: UTF8.self)
        XCTAssertTrue(csv.contains("Leroy"))
        XCTAssertTrue(csv.contains("100,00"))
        // Une sauvegarde sans dépenses (ancien format) se relit.
        let snapshot = BackupSnapshot(appVersion: "1", company: Fixtures.companySeller, customers: [], catalog: [], documents: [], numbering: [:])
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as! [String: Any]
        json.removeValue(forKey: "expenses")
        XCTAssertNil(try JSONDecoder().decode(BackupSnapshot.self, from: JSONSerialization.data(withJSONObject: json)).expenses)
    }
}

final class WidgetSnapshotTests: XCTestCase {
    func testSnapshotTotalsAndOrdering() throws {
        func invoice(_ number: String, due: Date, paid: Decimal = 0) -> DocumentRecord {
            var document = Fixtures.invoice(lines: [Fixtures.line("A", qty: "1", price: "100")])
            document.id = UUID()
            document.number = number
            document.dueDate = due
            return DocumentRecord(document: document, invoiceStatus: .issued, payments: paid > 0 ? [PaymentRecord(date: Fixtures.date(2026, 10, 5), amount: paid)] : [])
        }
        let records = [
            invoice("F-1", due: Fixtures.date(2026, 11, 20)),
            invoice("F-2", due: Fixtures.date(2026, 10, 2), paid: 20),
            invoice("F-3", due: Fixtures.date(2026, 11, 1), paid: 120),
        ]
        let snapshot = WidgetSnapshot.make(records: records, companyName: "Atelier", monthGoal: 600, isPrivate: false, today: Fixtures.date(2026, 10, 15))
        XCTAssertEqual(snapshot.outstanding, 220)
        XCTAssertEqual(snapshot.unpaidCount, 2)
        XCTAssertEqual(snapshot.overdueCount, 1)
        XCTAssertEqual(snapshot.overdueAmount, 100)
        XCTAssertEqual(snapshot.upcoming.map(\.number), ["F-2", "F-1"], "Retards d'abord")
        XCTAssertEqual(snapshot.monthInvoicedHT, 300)
        XCTAssertEqual(snapshot.monthCollected, 140)
        XCTAssertEqual(snapshot.goalProgress, 0.5)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(decoded, snapshot)
    }
}
