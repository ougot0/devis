import XCTest
@testable import DevisCore

final class MoneyTests: XCTestCase {

    func testRoundingHalfUpAwayFromZero() {
        XCTAssertEqual(Money.round(.exact("0.005")), .exact("0.01"))
        XCTAssertEqual(Money.round(.exact("0.004")), .exact("0"))
        XCTAssertEqual(Money.round(.exact("2.675")), .exact("2.68"), "Decimal évite l'erreur binaire classique de 2.675")
        XCTAssertEqual(Money.round(.exact("-0.005")), .exact("-0.01"))
        XCTAssertEqual(Money.round(.exact("1.99999")), .exact("2"))
    }

    func testDecimalAvoidsBinaryErrors() {
        let sum = Decimal.exact("0.1") + Decimal.exact("0.2")
        XCTAssertEqual(sum, .exact("0.3"))
        var total = Decimal(0)
        for _ in 0..<1000 { total += .exact("0.01") }
        XCTAssertEqual(total, 10)
    }

    func testParseFrenchAndEnglishInput() {
        XCTAssertEqual(Money.parse("1 234,56"), .exact("1234.56"))
        XCTAssertEqual(Money.parse("1234.56"), .exact("1234.56"))
        XCTAssertEqual(Money.parse("12,5 €"), .exact("12.5"))
        XCTAssertEqual(Money.parse("5,5 %"), .exact("5.5"))
        XCTAssertEqual(Money.parse("-3"), -3)
        XCTAssertEqual(Money.parse("1\u{202F}000"), 1000)
        XCTAssertNil(Money.parse(""))
        XCTAssertNil(Money.parse("abc"))
        XCTAssertNil(Money.parse("1,2,3"))
        XCTAssertNil(Money.parse("3-"))
        XCTAssertNil(Money.parse(","))
    }

    func testPlainStringAndFormat() {
        XCTAssertEqual(Money.plainString(.exact("1234.5")), "1234.50")
        XCTAssertEqual(Money.plainString(.exact("-0.5")), "-0.50")
        XCTAssertEqual(Money.plainString(0), "0.00")
        XCTAssertEqual(Money.plainString(.exact("0.004")), "0.00")
        XCTAssertEqual(Money.plainString(.exact("12.34567"), scale: 4), "12.3457")
        XCTAssertEqual(Money.format(.exact("1234567.8")), "1\u{202F}234\u{202F}567,80\u{00A0}€")
        XCTAssertEqual(Money.format(.exact("-12")), "-12,00\u{00A0}€")
        XCTAssertEqual(Money.format(.exact("999")), "999,00\u{00A0}€")
        XCTAssertEqual(Money.formatQuantity(.exact("5.50")), "5,5")
        XCTAssertEqual(Money.formatQuantity(20), "20")
        XCTAssertEqual(Money.formatQuantity(.exact("0.125")), "0,125")
    }

    func testAllocationSumsExactly() {
        let parts = Money.allocate(10, weights: [1, 1, 1])
        XCTAssertEqual(parts.reduce(0, +), 10)
        XCTAssertEqual(parts, [.exact("3.34"), .exact("3.33"), .exact("3.33")])

        let uneven = Money.allocate(.exact("0.05"), weights: [.exact("33.33"), .exact("66.67")])
        XCTAssertEqual(uneven.reduce(0, +), .exact("0.05"))

        XCTAssertEqual(Money.allocate(7, weights: [0, 0]), [7, 0])
        XCTAssertEqual(Money.allocate(5, weights: []), [])
        let negative = Money.allocate(-10, weights: [1, 2])
        XCTAssertEqual(negative.reduce(0, +), -10)
    }

    func testAllocationRandomizedInvariant() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<300 {
            let count = Int.random(in: 1...6, using: &generator)
            let weights = (0..<count).map { _ in Decimal(Int.random(in: 0...100_000, using: &generator)) / 100 }
            let total = Decimal(Int.random(in: 0...1_000_000, using: &generator)) / 100
            let parts = Money.allocate(total, weights: weights)
            XCTAssertEqual(parts.reduce(0, +), total)
            XCTAssertTrue(parts.allSatisfy { $0 >= 0 })
        }
    }
}
