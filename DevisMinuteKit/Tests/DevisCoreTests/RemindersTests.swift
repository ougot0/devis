import XCTest
@testable import DevisCore

final class RemindersTests: XCTestCase {
    private func issuedInvoice(number: String = "F-2026-0007") -> DocumentRecord {
        var document = Fixtures.invoice(lines: [Fixtures.line("Prestation", qty: "1", price: "1000")])
        document.number = number
        document.paymentLink = "https://buy.stripe.com/test_1"
        return DocumentRecord(document: document, invoiceStatus: .issued)
    }

    func testSendingEmailForInvoice() {
        let draft = EmailTemplates.sending(issuedInvoice().document)
        XCTAssertTrue(draft.subject.hasPrefix("Facture F-2026-0007"))
        XCTAssertTrue(draft.body.contains(Money.format(1200)), draft.body)
        XCTAssertTrue(draft.body.contains("31/10/2026"))
        XCTAssertTrue(draft.body.contains("https://buy.stripe.com/test_1"))
        XCTAssertTrue(draft.body.contains("Cordialement"))
    }

    func testSendingEmailForQuoteMentionsAcceptance() {
        var document = issuedInvoice().document
        document.kind = .quote
        document.number = "D-2026-0003"
        let draft = EmailTemplates.sending(document)
        XCTAssertTrue(draft.subject.hasPrefix("Devis D-2026-0003"))
        XCTAssertTrue(draft.body.contains(QuoteSignature.acceptanceMention))
        XCTAssertFalse(draft.body.contains("stripe"), "Pas de lien de paiement sur un devis")
    }

    func testReminderLevelsEscalate() {
        XCTAssertEqual(ReminderPolicy.suggestedLevel(after: []), .friendly)
        XCTAssertEqual(ReminderPolicy.suggestedLevel(after: [ReminderRecord(date: Date(), level: .friendly)]), .firm)
        XCTAssertEqual(ReminderPolicy.suggestedLevel(after: [ReminderRecord(date: Date(), level: .firm), ReminderRecord(date: Date(), level: .friendly)]), .formalNotice)
    }

    func testFormalNoticeForBusinessMentionsIndemnity() {
        let record = issuedInvoice()
        let draft = EmailTemplates.reminder(.formalNotice, for: record.document, balance: 1200, daysOverdue: 40)
        XCTAssertTrue(draft.subject.hasPrefix("Mise en demeure"))
        XCTAssertTrue(draft.body.contains("40 jours de retard"))
        XCTAssertTrue(draft.body.contains("40 €"))
        var individual = record.document
        individual.customer = Fixtures.individualCustomer
        XCTAssertFalse(EmailTemplates.reminder(.formalNotice, for: individual, balance: 1200, daysOverdue: 40).body.contains("40 €"), "Indemnité réservée aux professionnels")
    }

    func testAlertsOnlyForUnpaidFutureDates() {
        let unpaid = issuedInvoice()
        var paid = issuedInvoice(number: "F-2026-0008")
        paid.document.id = UUID()
        paid.payments = [PaymentRecord(date: Fixtures.date(2026, 10, 5), amount: 1200)]
        let draft = DocumentRecord(document: Fixtures.invoice(lines: [Fixtures.line("A", qty: "1", price: "10")]))
        let alerts = ReminderPolicy.alerts(for: [unpaid, paid, draft], now: Fixtures.date(2026, 10, 15))
        XCTAssertEqual(alerts.count, 2, "Échéance du 31/10 puis rappel du 07/11")
        XCTAssertTrue(alerts.allSatisfy { $0.documentID == unpaid.id })
        XCTAssertTrue(alerts[0].identifier.hasPrefix(ReminderPolicy.identifierPrefix))
        let afterDue = ReminderPolicy.alerts(for: [unpaid], now: Fixtures.date(2026, 11, 2))
        XCTAssertEqual(afterDue.map(\.title), ["Facture en retard"])
        XCTAssertTrue(ReminderPolicy.alerts(for: [unpaid], now: Fixtures.date(2026, 12, 1)).isEmpty)
    }
}
