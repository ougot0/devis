import XCTest
@testable import DevisCore

final class PaymentTests: XCTestCase {

    func testPartialPaymentsAndBalance() throws {
        var ledger = PaymentLedger(amountDue: 1200)
        try ledger.validate(500)
        ledger.payments.append(PaymentRecord(date: Fixtures.date(2026, 10, 5), amount: 500))
        XCTAssertEqual(ledger.balance, 700)
        XCTAssertEqual(ledger.state(dueDate: Fixtures.date(2026, 10, 31), today: Fixtures.date(2026, 10, 10)), .partiallyPaid)
        XCTAssertThrowsError(try ledger.validate(701)) { error in
            XCTAssertEqual(error as? PaymentError, .exceedsBalance(balance: 700))
        }
        XCTAssertThrowsError(try ledger.validate(0))
        XCTAssertThrowsError(try ledger.validate(-5))
        ledger.payments.append(PaymentRecord(date: Fixtures.date(2026, 10, 20), amount: 700))
        XCTAssertEqual(ledger.balance, 0)
        XCTAssertEqual(ledger.state(dueDate: Fixtures.date(2026, 10, 31), today: Fixtures.date(2026, 12, 1)), .paid)
    }

    func testOverdueDetection() {
        let ledger = PaymentLedger(amountDue: 100)
        let due = Fixtures.date(2026, 10, 31)
        XCTAssertEqual(ledger.state(dueDate: due, today: Fixtures.date(2026, 10, 31)), .unpaid, "Le jour de l'échéance n'est pas un retard")
        XCTAssertEqual(ledger.state(dueDate: due, today: Fixtures.date(2026, 11, 1)), .overdue)
        XCTAssertEqual(ledger.daysOverdue(dueDate: due, today: Fixtures.date(2026, 11, 10)), 10)
    }

    func testCreditNoteCancelsInvoice() {
        let ledger = PaymentLedger(amountDue: 100, creditedAmount: 100)
        XCTAssertEqual(ledger.state(dueDate: nil, today: Fixtures.date(2026, 11, 1)), .cancelled)
        XCTAssertEqual(ledger.balance, 0)
        let partial = PaymentLedger(amountDue: 100, creditedAmount: 30)
        XCTAssertEqual(partial.balance, 70)
    }

    func testCentRoundingOfPayments() throws {
        var ledger = PaymentLedger(amountDue: .exact("0.03"))
        ledger.payments = [
            PaymentRecord(date: Date(), amount: .exact("0.01")),
            PaymentRecord(date: Date(), amount: .exact("0.01")),
            PaymentRecord(date: Date(), amount: .exact("0.01")),
        ]
        XCTAssertEqual(ledger.balance, 0)
    }
}

final class NumberingTests: XCTestCase {

    func testSequentialNumbering() throws {
        var state = NumberingState()
        let scheme = NumberingScheme.defaultInvoice
        var numbers: [String] = []
        for day in 1...3 {
            let result = try NumberingService.next(scheme: scheme, state: state, issueDate: Fixtures.date(2026, 3, day))
            numbers.append(result.number)
            state = result.state
        }
        XCTAssertEqual(numbers, ["F-2026-0001", "F-2026-0002", "F-2026-0003"])
    }

    func testYearlyReset() throws {
        let state = NumberingState(lastSequence: 57, lastYear: 2026, lastIssueDate: Fixtures.date(2026, 12, 30), lastNumber: "F-2026-0057")
        let result = try NumberingService.next(scheme: .defaultInvoice, state: state, issueDate: Fixtures.date(2027, 1, 2))
        XCTAssertEqual(result.number, "F-2027-0001")
        let continuous = NumberingScheme(pattern: "FAC{N:5}", resetsYearly: false)
        let other = try NumberingService.next(scheme: continuous, state: state, issueDate: Fixtures.date(2027, 1, 2))
        XCTAssertEqual(other.number, "FAC00058")
    }

    func testRejectsBackdatedInvoice() {
        let state = NumberingState(lastSequence: 4, lastYear: 2026, lastIssueDate: Fixtures.date(2026, 5, 10), lastNumber: "F-2026-0004")
        XCTAssertThrowsError(try NumberingService.next(scheme: .defaultInvoice, state: state, issueDate: Fixtures.date(2026, 5, 9))) { error in
            guard case NumberingError.notChronological = error else { return XCTFail("\(error)") }
        }
        XCTAssertNoThrow(try NumberingService.next(scheme: .defaultInvoice, state: state, issueDate: Fixtures.date(2026, 5, 10)), "Même jour autorisé")
    }

    func testInvalidPatterns() {
        XCTAssertThrowsError(try NumberingScheme(pattern: "F-{AAAA}", resetsYearly: true).validate())
        XCTAssertThrowsError(try NumberingScheme(pattern: "F-{N}", resetsYearly: true).validate())
        XCTAssertNoThrow(try NumberingScheme(pattern: "F-{N}", resetsYearly: false).validate())
        XCTAssertThrowsError(try NumberingScheme(pattern: String(repeating: "X", count: 50) + "{N}", resetsYearly: false).validate())
    }

    func testDuplicateDetection() {
        XCTAssertThrowsError(try NumberingService.next(scheme: .defaultInvoice, state: NumberingState(), issueDate: Fixtures.date(2026, 1, 1), existingNumbers: ["F-2026-0001"]))
    }

    func testFormatTokens() {
        let scheme = NumberingScheme(pattern: "{AA}{MM}-{N:3}", resetsYearly: true)
        XCTAssertEqual(scheme.format(sequence: 7, date: Fixtures.date(2026, 4, 2)), "2604-007")
        XCTAssertEqual(scheme.format(sequence: 12345, date: Fixtures.date(2026, 4, 2)), "2604-12345", "Le compteur n'est jamais tronqué")
    }

    func testGapDetection() {
        XCTAssertEqual(NumberingService.gaps(in: [1, 2, 3]), [])
        XCTAssertEqual(NumberingService.gaps(in: [1, 2, 5, 6, 8]), [3...4, 7...7])
    }

    func testSeriesMapping() {
        XCTAssertEqual(NumberingSeries.series(for: .depositInvoice), .invoice)
        XCTAssertEqual(NumberingSeries.series(for: .creditNote), .creditNote)
    }
}

final class LifecycleTests: XCTestCase {

    func testQuoteTransitions() throws {
        XCTAssertEqual(try QuoteLifecycle.transition(from: .draft, to: .sent), .sent)
        XCTAssertEqual(try QuoteLifecycle.transition(from: .sent, to: .accepted), .accepted)
        XCTAssertEqual(try QuoteLifecycle.transition(from: .sent, to: .refused), .refused)
        XCTAssertThrowsError(try QuoteLifecycle.transition(from: .draft, to: .accepted))
        XCTAssertThrowsError(try QuoteLifecycle.transition(from: .accepted, to: .draft))
        XCTAssertThrowsError(try QuoteLifecycle.transition(from: .refused, to: .sent))
        XCTAssertFalse(QuoteStatus.accepted.isEditable)
        XCTAssertTrue(QuoteStatus.sent.isEditable)
    }

    func testQuoteExpiry() {
        let validUntil = Fixtures.date(2026, 10, 15)
        XCTAssertEqual(QuoteLifecycle.effectiveStatus(.sent, validUntil: validUntil, today: Fixtures.date(2026, 10, 15)), .sent)
        XCTAssertEqual(QuoteLifecycle.effectiveStatus(.sent, validUntil: validUntil, today: Fixtures.date(2026, 10, 16)), .expired)
        XCTAssertEqual(QuoteLifecycle.effectiveStatus(.accepted, validUntil: validUntil, today: Fixtures.date(2027, 1, 1)), .accepted)
        XCTAssertEqual(QuoteLifecycle.effectiveStatus(.draft, validUntil: validUntil, today: Fixtures.date(2027, 1, 1)), .draft)
    }

    func testIssuedInvoiceIsLocked() {
        XCTAssertThrowsError(try InvoiceLifecycle.ensureEditable(.issued)) { error in
            XCTAssertEqual(error as? LifecycleError, .documentLocked)
        }
        XCTAssertNoThrow(try InvoiceLifecycle.ensureEditable(.draft))
        XCTAssertThrowsError(try InvoiceLifecycle.ensureIssuable(Fixtures.invoice(lines: []), status: .draft))
    }

    func testQuoteToInvoiceConversion() {
        var quote = Fixtures.invoice(lines: [Fixtures.line("A", qty: "2", price: "50")])
        quote.kind = .quote
        quote.number = "D-2026-0010"
        let invoice = DocumentFactory.invoice(from: quote, seller: Fixtures.companySeller, issueDate: Fixtures.date(2026, 11, 1))
        XCTAssertEqual(invoice.kind, .invoice)
        XCTAssertEqual(invoice.number, "")
        XCTAssertEqual(invoice.sourceQuoteNumber, "D-2026-0010")
        XCTAssertNotEqual(invoice.id, quote.id)
        XCTAssertNotEqual(invoice.lines[0].id, quote.lines[0].id)
        XCTAssertEqual(DocumentCalculator.totals(for: invoice).totalTTC, DocumentCalculator.totals(for: quote).totalTTC)
        XCTAssertEqual(invoice.dueDate, Fixtures.date(2026, 12, 1))
    }

    func testCreditNotes() {
        var invoice = Fixtures.invoice(lines: [Fixtures.line("A", qty: "2", price: "50")])
        invoice.number = "F-2026-0042"
        let full = DocumentFactory.fullCreditNote(for: invoice, issueDate: Fixtures.date(2026, 11, 2), reason: "Annulation de la commande")
        XCTAssertEqual(full.kind, .creditNote)
        XCTAssertEqual(full.correctedInvoiceNumber, "F-2026-0042")
        XCTAssertEqual(DocumentCalculator.totals(for: full).totalTTC, 120)
        let partial = DocumentFactory.partialCreditNote(for: invoice, issueDate: Fixtures.date(2026, 11, 2), amountHT: 10, vatRate: 20, reason: "Geste commercial")
        XCTAssertEqual(DocumentCalculator.totals(for: partial).totalTTC, 12)
        XCTAssertTrue(ComplianceValidator.validate(partial, today: Fixtures.date(2026, 11, 2)).allSatisfy { $0.code != "credit.reference" })
    }

    func testDuplicateQuote() {
        var quote = Fixtures.invoice(lines: [Fixtures.line("A", qty: "1", price: "10")])
        quote.kind = .quote
        quote.number = "D-2026-0001"
        let copy = DocumentFactory.duplicate(quote, issueDate: Fixtures.date(2026, 11, 1), seller: Fixtures.companySeller)
        XCTAssertEqual(copy.number, "")
        XCTAssertEqual(copy.validUntil, Fixtures.date(2026, 12, 1))
        XCTAssertEqual(copy.lines.count, 1)
    }
}

final class ComplianceTests: XCTestCase {

    func testCompleteInvoiceHasNoBlockingIssue() {
        let issues = ComplianceValidator.validate(Fixtures.invoice(lines: [Fixtures.line("Prestation", qty: "1", price: "200")]), today: Fixtures.date(2026, 10, 1))
        XCTAssertFalse(ComplianceValidator.hasBlockingIssues(issues), "\(issues)")
    }

    func testMissingSellerDataIsBlocking() {
        var seller = Fixtures.companySeller
        seller.siren = ""
        seller.vatNumber = ""
        seller.address = PostalAddress()
        let issues = ComplianceValidator.validate(Fixtures.invoice(lines: [Fixtures.line("P", qty: "1", price: "200")], seller: seller), today: Fixtures.date(2026, 10, 1))
        let codes = Set(issues.filter { $0.severity == .blocking }.map(\.code))
        XCTAssertTrue(codes.isSuperset(of: ["seller.siren", "seller.vat", "seller.address"]))
    }

    func testVATNumberNotRequiredUnder150() {
        var seller = Fixtures.companySeller
        seller.vatNumber = ""
        let issues = ComplianceValidator.validate(Fixtures.invoice(lines: [Fixtures.line("P", qty: "1", price: "150")], seller: seller), today: Fixtures.date(2026, 10, 1))
        XCTAssertFalse(issues.contains { $0.code == "seller.vat" })
    }

    func testCustomerSIRENBecomesBlockingIn2027() {
        var customer = Fixtures.businessCustomer
        customer.siren = ""
        let doc = Fixtures.invoice(lines: [Fixtures.line("P", qty: "1", price: "100")], customer: customer)
        XCTAssertEqual(ComplianceValidator.validate(doc, today: Fixtures.date(2026, 10, 1)).first { $0.code == "customer.siren" }?.severity, .info)
        XCTAssertEqual(ComplianceValidator.validate(doc, today: Fixtures.date(2027, 9, 1)).first { $0.code == "customer.siren" }?.severity, .blocking)
    }

    func testPaymentTermBeyond60DaysWarnsForB2B() {
        var doc = Fixtures.invoice(lines: [Fixtures.line("P", qty: "1", price: "100")])
        doc.dueDate = Fixtures.date(2027, 1, 15)
        XCTAssertTrue(ComplianceValidator.validate(doc, today: Fixtures.date(2026, 10, 1)).contains { $0.code == "invoice.dueDate.limit" })
    }

    func testMentionsB2BvsB2C() {
        let b2b = Fixtures.invoice(lines: [Fixtures.line("P", qty: "1", price: "100")])
        let b2bMentions = LegalMentionsBuilder.mentions(for: b2b, totals: DocumentCalculator.totals(for: b2b))
        XCTAssertTrue(b2bMentions.contains { $0.contains("40 €") })
        XCTAssertTrue(b2bMentions.contains(LegalTexts.noEarlyPaymentDiscount))
        XCTAssertTrue(b2bMentions.contains { $0.contains("pénalités") })

        let b2c = Fixtures.invoice(lines: [Fixtures.line("P", qty: "1", price: "100")], customer: Fixtures.individualCustomer)
        let b2cMentions = LegalMentionsBuilder.mentions(for: b2c, totals: DocumentCalculator.totals(for: b2c))
        XCTAssertFalse(b2cMentions.contains { $0.contains("40 €") }, "L'indemnité forfaitaire ne concerne que les clients professionnels")
    }

    func testSellerLegalLine() {
        let company = LegalMentionsBuilder.sellerLegalLine(Fixtures.companySeller)
        XCTAssertTrue(company.contains("SARL au capital de 10\u{202F}000,00"))
        XCTAssertTrue(company.contains("RCS Lyon"))
        XCTAssertTrue(company.contains("SIREN 732 829 320"))
        XCTAssertTrue(company.contains("FR44732829320"))
        let micro = LegalMentionsBuilder.sellerLegalLine(Fixtures.microSeller)
        XCTAssertTrue(micro.hasPrefix("Camille Durand EI"))
        XCTAssertFalse(micro.contains("TVA intracom"))
    }

    func testVATOnDebitsMention() {
        var seller = Fixtures.companySeller
        seller.vatOnDebits = true
        let doc = Fixtures.invoice(lines: [Fixtures.line("Conseil", qty: "1", price: "100")], seller: seller)
        XCTAssertTrue(LegalMentionsBuilder.mentions(for: doc, totals: DocumentCalculator.totals(for: doc)).contains(LegalTexts.vatOnDebitsMention))
    }

    func testOperationNature() {
        var doc = Fixtures.invoice(lines: [Fixtures.line("A", qty: "1", price: "1")])
        XCTAssertEqual(doc.operationNatureLabel, "Prestation de services")
        doc.lines.append(DocumentLine(designation: "Pièce", unitPriceHT: 5, nature: .goods))
        XCTAssertEqual(doc.operationNatureLabel, "Livraison de biens et prestation de services")
    }

    func testIdentifiers() {
        XCTAssertTrue(Identifiers.isValidSIREN("732829320"))
        XCTAssertFalse(Identifiers.isValidSIREN("732829321"))
        XCTAssertFalse(Identifiers.isValidSIREN("12345678"))
        XCTAssertTrue(Identifiers.isValidSIRET("73282932000074"))
        XCTAssertFalse(Identifiers.isValidSIRET("73282932000075"))
        XCTAssertEqual(Identifiers.frenchVATNumber(fromSIREN: "732829320"), "FR44732829320")
        XCTAssertTrue(Identifiers.isValidFrenchVATNumber("FR 44 732829320"))
        XCTAssertFalse(Identifiers.isValidFrenchVATNumber("FR45732829320"))
        XCTAssertTrue(Identifiers.isValidIBAN("FR76 3000 6000 0112 3456 7890 189"))
        XCTAssertFalse(Identifiers.isValidIBAN("FR76 3000 6000 0112 3456 7890 188"))
        XCTAssertEqual(LegalMentionsBuilder.formatSiret("73282932000074"), "732 829 320 00074")
    }
}

final class SealTests: XCTestCase {

    func testSealDetectsModification() {
        var invoice = Fixtures.invoice(lines: [Fixtures.line("A", qty: "1", price: "100")])
        invoice.number = "F-2026-0001"
        let seal = DocumentSealer.seal(invoice, previousSealHash: "", sealedAt: Date())
        XCTAssertTrue(DocumentSealer.verify(invoice, seal: seal))
        XCTAssertEqual(seal.contentHash.count, 64)

        var tampered = invoice
        tampered.lines[0].unitPriceHT = 90
        XCTAssertFalse(DocumentSealer.verify(tampered, seal: seal))

        var renamed = invoice
        renamed.customer.name = "Autre client"
        XCTAssertFalse(DocumentSealer.verify(renamed, seal: seal))
    }

    func testCanonicalRepresentationIsStableAndEscaped() {
        var invoice = Fixtures.invoice(lines: [Fixtures.line("A;B=C\nD", qty: "1", price: "100")])
        invoice.number = "F-2026-0001"
        XCTAssertEqual(DocumentSealer.canonicalRepresentation(of: invoice), DocumentSealer.canonicalRepresentation(of: invoice))
        XCTAssertTrue(DocumentSealer.canonicalRepresentation(of: invoice).contains("A\\;B\\=C\\nD"))
    }

    func testChainVerification() {
        var first = Fixtures.invoice(lines: [Fixtures.line("A", qty: "1", price: "100")])
        first.number = "F-2026-0001"
        var second = Fixtures.invoice(lines: [Fixtures.line("B", qty: "1", price: "200")])
        second.number = "F-2026-0002"
        var third = Fixtures.invoice(lines: [Fixtures.line("C", qty: "1", price: "300")])
        third.number = "F-2026-0003"
        let s1 = DocumentSealer.seal(first, previousSealHash: "", sealedAt: Date())
        let s2 = DocumentSealer.seal(second, previousSealHash: s1.sealHash, sealedAt: Date())
        let s3 = DocumentSealer.seal(third, previousSealHash: s2.sealHash, sealedAt: Date())
        XCTAssertEqual(SealVerifier.verifyChain([(first, s1), (second, s2), (third, s3)]), [])
        // Suppression de la facture du milieu : rupture de chaîne détectée.
        XCTAssertEqual(SealVerifier.verifyChain([(first, s1), (third, s3)]), [.brokenChain(number: "F-2026-0003")])
    }

    func testKnownSHA256Vector() {
        XCTAssertEqual(DocumentSealer.hash(of: "abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
