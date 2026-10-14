import Foundation
import UIKit
import DevisCore
import DevisPDF

/// Génération des fichiers à partager (PDF, XML, CSV, sauvegardes), entièrement sur l'appareil.
enum DocumentExportService {

    /// Compression des flux PDF via le framework Foundation (DEFLATE brut) encapsulé en zlib.
    static let deflate: (Data) -> Data? = { data in
        guard let raw = try? (data as NSData).compressed(using: .zlib) as Data else { return nil }
        return ZlibWrapper.wrap(rawDeflate: raw, original: data)
    }

    @MainActor
    static func renderPDF(for record: DocumentRecord, store: DataStore) -> RenderResult {
        let isDraft = record.document.kind != .quote && record.invoiceStatus != .issued
        var payment: PaymentSummary?
        if record.isIssuedInvoice && record.document.kind != .creditNote {
            let ledger = Accounting.ledger(for: record, in: store.allRecords())
            payment = PaymentSummary(paid: ledger.totalPaid, credited: ledger.creditedAmount, balance: ledger.balance)
        }
        // Un brouillon reflète les réglages actuels ; un document émis garde l'émetteur figé.
        var document = record.document
        if isDraft || (record.document.kind == .quote && record.quoteStatus == .draft) {
            document.seller = store.company
        }
        let request = RenderRequest(
            document: document,
            appearance: store.appearance,
            logoJPEG: store.logoJPEG,
            payment: payment,
            isDraft: isDraft,
            generatedAt: Date()
        )
        return DocumentPDFRenderer.render(request, deflate: deflate)
    }

    /// Écrit des données dans un fichier temporaire protégé, prêt pour la feuille de partage.
    /// Les fichiers temporaires sont supprimés au lancement suivant (`purgeTemporaryFiles`).
    static func temporaryFile(named name: String, data: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    static func purgeTemporaryFiles() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
    }

    @MainActor
    static func pdfFile(for record: DocumentRecord, store: DataStore) throws -> URL {
        let result = renderPDF(for: record, store: store)
        return try temporaryFile(named: DocumentPDFRenderer.suggestedFileName(for: record.document), data: result.data)
    }

    static func ciiFile(for record: DocumentRecord) throws -> URL {
        let name = DocumentPDFRenderer.suggestedFileName(for: record.document).replacingOccurrences(of: ".pdf", with: " - donnees CII.xml")
        return try temporaryFile(named: name, data: CIIExporter.xml(for: record.document))
    }

    static func dateStamp(_ date: Date = Date()) -> String { DateFormatting.iso(date) }
}

/// Préparation du logo : redimensionné, aplati sur fond blanc, converti en JPEG
/// (format directement intégrable par le moteur PDF).
enum LogoProcessor {
    static let maxDimension: CGFloat = 800

    static func jpeg(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: target))
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.jpegData(compressionQuality: 0.88)
    }
}
