import Foundation
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
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
    static func renderPDF(for record: DocumentRecord, store: AppDataStore) -> RenderResult {
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
        var qrCode: Data?
        if let link = document.paymentLink, PaymentLink.isValid(link) {
            qrCode = QRCodeGenerator.jpeg(for: link.trimmed)
        }
        let request = RenderRequest(
            document: document,
            appearance: store.appearance,
            logoJPEG: store.logoJPEG,
            payment: payment,
            isDraft: isDraft,
            generatedAt: Date(),
            paymentQRCodeJPEG: qrCode,
            signature: record.document.kind == .quote ? record.signature : nil
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
    static func pdfFile(for record: DocumentRecord, store: AppDataStore) throws -> URL {
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

/// QR code généré sur l'appareil (Core Image), sans service externe.
enum QRCodeGenerator {
    static func jpeg(for text: String, pixels: CGFloat = 480) -> Data? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        // Agrandissement sans lissage pour garder des modules nets.
        let scale = max(1, (pixels / output.extent.width).rounded(.down))
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = CIContext(options: [.useSoftwareRenderer: false]).createCGImage(scaled, from: scaled.extent) else { return nil }
        let margin = scale * 2
        let size = CGSize(width: scaled.extent.width + margin * 2, height: scaled.extent.height + margin * 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.interpolationQuality = .none
            UIImage(cgImage: cgImage).draw(in: CGRect(x: margin, y: margin, width: scaled.extent.width, height: scaled.extent.height))
        }
        return image.jpegData(compressionQuality: 1.0)
    }
}
