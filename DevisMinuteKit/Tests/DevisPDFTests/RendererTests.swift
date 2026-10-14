import XCTest
import DevisCore
@testable import DevisPDF

final class RendererTests: XCTestCase {

    /// Répertoire où écrire les PDF pour inspection visuelle (variable d'environnement facultative).
    private var outputDirectory: URL? {
        ProcessInfo.processInfo.environment["DEVIS_PDF_OUTPUT"].map { URL(fileURLWithPath: $0) }
    }

    private func save(_ data: Data, _ name: String) throws {
        guard let directory = outputDirectory else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(name))
    }

    /// Vérifie la structure : en-tête, fin de fichier, table xref cohérente.
    private func assertValidPDF(_ data: Data, file: StaticString = #filePath, line: UInt = #line) {
        let bytes = [UInt8](data)
        XCTAssertEqual(Array(bytes.prefix(8)), Array("%PDF-1.7".utf8), file: file, line: line)
        let text = String(decoding: bytes, as: UTF8.self)
        XCTAssertTrue(text.hasSuffix("%%EOF\n"), file: file, line: line)
        guard let startRange = text.range(of: "startxref\n", options: .backwards) else { return XCTFail("startxref absent", file: file, line: line) }
        let offsetString = text[startRange.upperBound...].prefix { $0.isNumber }
        guard let xrefOffset = Int(offsetString) else { return XCTFail("offset xref invalide", file: file, line: line) }
        XCTAssertEqual(Array(bytes[xrefOffset..<xrefOffset + 4]), Array("xref".utf8), file: file, line: line)
        // Chaque entrée de la table xref doit pointer sur « n 0 obj ».
        let xrefText = String(decoding: bytes[xrefOffset...], as: UTF8.self)
        let entries = xrefText.split(separator: "\n").dropFirst(3).prefix { $0.hasSuffix(" n ") || $0.hasSuffix(" n") }
        for (index, entry) in entries.enumerated() {
            guard let offset = Int(entry.prefix(10)) else { return XCTFail("entrée xref invalide", file: file, line: line) }
            let expected = Array("\(index + 1) 0 obj".utf8)
            XCTAssertEqual(Array(bytes[offset..<offset + expected.count]), expected, "objet \(index + 1)", file: file, line: line)
        }
    }

    func testAllTemplatesRenderValidPDF() throws {
        for template in DocumentTemplate.allCases {
            for (kind, document) in [("devis", SampleData.quote()), ("facture", SampleData.invoice())] {
                let document = kind == "devis" ? SampleData.quote(lineCount: 3) : SampleData.invoice(lineCount: 3)
                let request = RenderRequest(document: document, appearance: DocumentAppearance(template: template), logoJPEG: SampleData.logoJPEG,
                                            payment: kind == "facture" ? PaymentSummary(paid: 100, balance: DocumentCalculator.totals(for: document).netToPay - 100) : nil,
                                            generatedAt: SampleData.date(2026, 10, 14))
                let result = DocumentPDFRenderer.render(request)
                assertValidPDF(result.data)
                XCTAssertLessThanOrEqual(result.pageCount, 2, "\(template) \(kind) : document court sur deux pages au plus")
                XCTAssertTrue(result.warnings.isEmpty, "\(result.warnings)")
                try save(result.data, "\(template.rawValue)-\(kind).pdf")
            }
        }
    }

    func testMultipageDocumentRepeatsHeaderAndNumbersPages() throws {
        for template in DocumentTemplate.allCases {
            let document = SampleData.invoice(lineCount: 70)
            let result = DocumentPDFRenderer.render(RenderRequest(document: document, appearance: DocumentAppearance(template: template), generatedAt: SampleData.date(2026, 10, 14)))
            assertValidPDF(result.data)
            XCTAssertGreaterThan(result.pageCount, 2, "\(template)")
            let text = String(decoding: result.data, as: UTF8.self)
            XCTAssertTrue(text.contains("(Page 1 / \(result.pageCount))"), "\(template)")
            XCTAssertTrue(text.contains("\\(suite\\)"), "\(template)")
            try save(result.data, "\(template.rawValue)-multipage.pdf")
        }
    }

    func testVeryLongFieldsAreSplitAcrossPages() throws {
        var document = SampleData.quote(lineCount: 8, longText: true)
        document.customer.name = String(repeating: "Société au nom particulièrement long ", count: 4)
        document.specialConditions = String(repeating: "Clause contractuelle détaillée. ", count: 300)
        document.lines.append(DocumentLine(designation: "RéférenceSansEspaceTrèsLongueQuiDoitÊtreCoupéeAuCaractèrePourNePasDéborderDeLaColonne", quantity: 1, unitPriceHT: 1))
        for template in DocumentTemplate.allCases {
            let result = DocumentPDFRenderer.render(RenderRequest(document: document, appearance: DocumentAppearance(template: template), logoJPEG: SampleData.logoJPEG, isDraft: true))
            assertValidPDF(result.data)
            XCTAssertGreaterThan(result.pageCount, 2)
            try save(result.data, "\(template.rawValue)-long.pdf")
        }
    }

    func testFranchiseAndCreditNote() throws {
        var document = SampleData.invoice()
        document.seller.vatRegime = .franchise
        document.seller.legalForm = .microEntrepreneur
        document.seller.ownerName = "Camille Durand"
        document.depositDeductions = []
        let result = DocumentPDFRenderer.render(RenderRequest(document: document, appearance: DocumentAppearance(template: .moderne)))
        let text = String(decoding: result.data, as: UTF8.self)
        XCTAssertTrue(text.contains("(TVA non applicable, art. 293 B du CGI)"))
        XCTAssertFalse(text.contains("(Total TTC)"))
        try save(result.data, "franchise.pdf")

        var credit = DocumentFactory.fullCreditNote(for: SampleData.invoice(), issueDate: SampleData.date(2026, 10, 20), reason: "Annulation partielle de la commande")
        credit.number = "AV-2026-0003"
        let creditResult = DocumentPDFRenderer.render(RenderRequest(document: credit, appearance: DocumentAppearance(template: .classique)))
        assertValidPDF(creditResult.data)
        XCTAssertTrue(String(decoding: creditResult.data, as: UTF8.self).contains("F-2026-0118"))
        try save(creditResult.data, "avoir.pdf")
    }

    func testDraftBannerAndNoLogo() {
        let result = DocumentPDFRenderer.render(RenderRequest(document: SampleData.invoice(), appearance: DocumentAppearance(template: .artisan), isDraft: true))
        XCTAssertTrue(String(decoding: result.data, as: UTF8.self).contains("BROUILLON"))
    }

    func testInvalidLogoProducesWarning() {
        let result = DocumentPDFRenderer.render(RenderRequest(document: SampleData.quote(), appearance: DocumentAppearance(), logoJPEG: Data([0x89, 0x50, 0x4E, 0x47])))
        XCTAssertEqual(result.warnings.count, 1)
        assertValidPDF(result.data)
    }

    func testUnsupportedCharactersWarning() {
        var document = SampleData.quote()
        document.lines[1].designation = "Prestation 🚀 日本"
        let result = DocumentPDFRenderer.render(RenderRequest(document: document, appearance: DocumentAppearance()))
        XCTAssertTrue(result.warnings.contains { $0.contains("caractères") })
    }

    func testWinAnsiEncoding() {
        XCTAssertEqual(WinAnsi.encode("é€œ’…"), [0xE9, 0x80, 0x9C, 0x92, 0x85])
        XCTAssertEqual(WinAnsi.encode("e\u{0301}"), [0xE9], "Normalisation NFC")
        XCTAssertEqual(WinAnsi.encode("1\u{202F}000"), [0x31, 0xA0, 0x30, 0x30, 0x30])
        XCTAssertEqual(WinAnsi.encode("😀"), [0x3F])
        XCTAssertFalse(WinAnsi.hasUnsupportedCharacters("Crème brûlée, œuvre — « 12 € »"))
        XCTAssertTrue(WinAnsi.hasUnsupportedCharacters("Ελληνικά"))
    }

    func testTextWrapping() {
        let style = TextStyle(font: .helvetica, size: 10)
        let lines = TextLayout.wrap("Un texte assez long pour être coupé en plusieurs lignes distinctes", style: style, width: 100)
        XCTAssertGreaterThan(lines.count, 1)
        XCTAssertTrue(lines.allSatisfy { style.font.width(of: $0, size: 10) <= 100 })
        XCTAssertEqual(TextLayout.wrap("A\n\nB", style: style, width: 100), ["A", "", "B"])
        let long = TextLayout.wrap(String(repeating: "W", count: 80), style: style, width: 50)
        XCTAssertTrue(long.allSatisfy { style.font.width(of: $0, size: 10) <= 50 })
        XCTAssertEqual(StandardFont.helvetica.width(of: "Hello", size: 10), 22.78, accuracy: 0.01)
        XCTAssertTrue(TextLayout.truncate(String(repeating: "x", count: 100), style: style, width: 40).hasSuffix("…"))
    }

    func testJPEGParsing() {
        let image = PDFImage(jpegData: SampleData.logoJPEG)
        XCTAssertEqual(image?.pixelWidth, 240)
        XCTAssertEqual(image?.pixelHeight, 80)
        XCTAssertEqual(image?.components, 3)
        XCTAssertNil(PDFImage(jpegData: Data([1, 2, 3])))
    }

    func testSuggestedFileName() {
        var document = SampleData.invoice()
        document.customer.name = "A/B: \"Client\""
        XCTAssertEqual(DocumentPDFRenderer.suggestedFileName(for: document), "Facture F-2026-0118 - A-B- -Client-.pdf")
    }

    func testZlibWrapperChecksum() {
        // Adler-32 de « Wikipedia » = 0x11E60398 (exemple de référence).
        let wrapped = ZlibWrapper.wrap(rawDeflate: Data(), original: Data("Wikipedia".utf8))
        XCTAssertEqual(Array(wrapped.suffix(4)), [0x11, 0xE6, 0x03, 0x98])
    }

    func testColorParsing() {
        XCTAssertEqual(PDFColor(hex: "#245A64")?.hex, "#245A64")
        XCTAssertNil(PDFColor(hex: "zzz"))
        XCTAssertLessThan(PDFColor(hex: "#245A64")!.luminance, 0.2)
    }
}
