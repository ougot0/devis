import Foundation

/// Couleur RVB (composantes 0...1).
public struct PDFColor: Codable, Sendable, Equatable, Hashable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Couleur à partir d'un code hexadécimal « #245A64 ».
    public init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        red = Double((number >> 16) & 0xFF) / 255
        green = Double((number >> 8) & 0xFF) / 255
        blue = Double(number & 0xFF) / 255
    }

    public var hex: String {
        String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    /// Mélange avec le blanc (`amount` = part de blanc).
    public func tinted(_ amount: Double) -> PDFColor {
        PDFColor(red: red + (1 - red) * amount, green: green + (1 - green) * amount, blue: blue + (1 - blue) * amount)
    }

    /// Luminance relative (WCAG) : pour choisir un texte clair ou foncé sur un aplat.
    public var luminance: Double {
        func channel(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    public static let black = PDFColor(red: 0, green: 0, blue: 0)
    public static let white = PDFColor(red: 1, green: 1, blue: 1)
}

/// Image JPEG prête à être intégrée telle quelle (filtre DCTDecode, sans décodage).
public struct PDFImage: Sendable, Equatable {
    public let data: Data
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let components: Int

    /// Lit les dimensions d'un JPEG (marqueurs SOF). Retourne `nil` si les données ne sont pas un JPEG valide.
    public init?(jpegData: Data) {
        let bytes = [UInt8](jpegData)
        guard bytes.count > 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return nil }
        var index = 2
        while index + 9 < bytes.count {
            guard bytes[index] == 0xFF else { index += 1; continue }
            let marker = bytes[index + 1]
            if marker == 0xD8 || marker == 0x01 || (0xD0...0xD7).contains(marker) || marker == 0xFF {
                index += marker == 0xFF ? 1 : 2
                continue
            }
            let length = Int(bytes[index + 2]) << 8 | Int(bytes[index + 3])
            let isStartOfFrame = (0xC0...0xCF).contains(marker) && marker != 0xC4 && marker != 0xC8 && marker != 0xCC
            if isStartOfFrame {
                let height = Int(bytes[index + 5]) << 8 | Int(bytes[index + 6])
                let width = Int(bytes[index + 7]) << 8 | Int(bytes[index + 8])
                let components = Int(bytes[index + 9])
                guard width > 0, height > 0, [1, 3, 4].contains(components) else { return nil }
                self.data = jpegData
                self.pixelWidth = width
                self.pixelHeight = height
                self.components = components
                return
            }
            index += 2 + length
        }
        return nil
    }
}

/// Opérations de dessin d'une page, en coordonnées « haut-gauche » (y vers le bas), en points.
public final class PDFPage {
    public let width: Double
    public let height: Double
    private(set) var operations: String = ""
    private(set) var usedFonts: Set<StandardFont> = []
    private(set) var usedImages: [Int] = []
    /// Liens cliquables (mailto:, https:) : rectangle en coordonnées PDF.
    private(set) var links: [(rect: (Double, Double, Double, Double), url: String)] = []

    init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    private func n(_ value: Double) -> String {
        let rounded = (value * 1000).rounded() / 1000
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        var text = String(format: "%.3f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        return text
    }

    private func colorOperator(_ color: PDFColor, stroke: Bool) -> String {
        "\(n(color.red)) \(n(color.green)) \(n(color.blue)) \(stroke ? "RG" : "rg")\n"
    }

    /// Texte sur une ligne ; `y` est la ligne de base mesurée depuis le haut de la page.
    public func text(_ string: String, x: Double, baseline y: Double, font: StandardFont, size: Double, color: PDFColor = .black) {
        let bytes = WinAnsi.encode(string)
        guard !bytes.isEmpty else { return }
        usedFonts.insert(font)
        var literal = "("
        for byte in bytes {
            switch byte {
            case 0x28: literal += "\\("
            case 0x29: literal += "\\)"
            case 0x5C: literal += "\\\\"
            case 0x20...0x7E: literal.append(Character(UnicodeScalar(byte)))
            default: literal += String(format: "\\%03o", byte)
            }
        }
        literal += ")"
        operations += colorOperator(color, stroke: false)
        operations += "BT /\(font.resourceName) \(n(size)) Tf \(n(x)) \(n(height - y)) Td \(literal) Tj ET\n"
    }

    public func fillRect(x: Double, y: Double, width: Double, height rectHeight: Double, color fill: PDFColor) {
        operations += colorOperator(fill, stroke: false)
        operations += "\(n(x)) \(n(height - y - rectHeight)) \(n(width)) \(n(rectHeight)) re f\n"
    }

    public func strokeRect(x: Double, y: Double, width: Double, height rectHeight: Double, color stroke: PDFColor, lineWidth: Double = 0.5) {
        operations += colorOperator(stroke, stroke: true)
        operations += "\(n(lineWidth)) w \(n(x)) \(n(height - y - rectHeight)) \(n(width)) \(n(rectHeight)) re S\n"
    }

    public func line(from start: (x: Double, y: Double), to end: (x: Double, y: Double), color stroke: PDFColor, lineWidth: Double = 0.5, dash: [Double] = []) {
        operations += colorOperator(stroke, stroke: true)
        let dashOperator = dash.isEmpty ? "[] 0 d" : "[\(dash.map(n).joined(separator: " "))] 0 d"
        operations += "\(n(lineWidth)) w \(dashOperator) \(n(start.x)) \(n(height - start.y)) m \(n(end.x)) \(n(height - end.y)) l S [] 0 d\n"
    }

    /// Dessine une image enregistrée auprès du document (`PDFDocumentBuilder.register(image:)`).
    public func image(_ handle: Int, x: Double, y: Double, width: Double, height imageHeight: Double) {
        if !usedImages.contains(handle) { usedImages.append(handle) }
        operations += "q \(n(width)) 0 0 \(n(imageHeight)) \(n(x)) \(n(height - y - imageHeight)) cm /Im\(handle) Do Q\n"
    }

    public func link(url: String, x: Double, y: Double, width: Double, height linkHeight: Double) {
        links.append(((x, height - y - linkHeight, x + width, height - y), url))
    }
}

/// Métadonnées du fichier PDF.
public struct PDFMetadata: Sendable {
    public var title: String
    public var author: String
    public var subject: String
    public var keywords: String
    public var creationDate: Date

    public init(title: String, author: String, subject: String = "", keywords: String = "", creationDate: Date = Date()) {
        self.title = title
        self.author = author
        self.subject = subject
        self.keywords = keywords
        self.creationDate = creationDate
    }
}

/// Assemble les pages et produit un fichier PDF 1.7.
public final class PDFDocumentBuilder {
    public static let a4Width = 595.28
    public static let a4Height = 841.89

    private(set) var pages: [PDFPage] = []
    private var images: [PDFImage] = []
    /// Compression facultative des flux (zlib). Sous iOS, l'application fournit une
    /// implémentation basée sur le framework Compression ; sinon les flux restent non compressés.
    public var deflate: ((Data) -> Data?)?

    public init() {}

    public func newPage(width: Double = a4Width, height: Double = a4Height) -> PDFPage {
        let page = PDFPage(width: width, height: height)
        pages.append(page)
        return page
    }

    public func register(image: PDFImage) -> Int {
        images.append(image)
        return images.count
    }

    public func build(metadata: PDFMetadata) -> Data {
        var output = Data()
        var offsets: [Int] = []
        func append(_ string: String) { output.append(contentsOf: Array(string.utf8)) }
        func beginObject(_ number: Int) {
            while offsets.count < number { offsets.append(0) }
            offsets[number - 1] = output.count
            append("\(number) 0 obj\n")
        }

        append("%PDF-1.7\n%\u{E2}\u{E3}\u{CF}\u{D3}\n")

        // Numérotation : 1 catalogue, 2 arbre des pages, 3 infos, 4...10 polices, puis images, puis pages.
        let fontObjectBase = 4
        let fonts = StandardFont.allCases
        let imageObjectBase = fontObjectBase + fonts.count
        var next = imageObjectBase + images.count

        var pageObjects: [(page: Int, content: Int, annotations: [Int])] = []
        for page in pages {
            let pageNumber = next
            let contentNumber = next + 1
            next += 2
            var annotationNumbers: [Int] = []
            for _ in page.links {
                annotationNumbers.append(next)
                next += 1
            }
            pageObjects.append((pageNumber, contentNumber, annotationNumbers))
        }

        beginObject(1)
        append("<< /Type /Catalog /Pages 2 0 R /Lang (fr-FR) /ViewerPreferences << /DisplayDocTitle true >> >>\nendobj\n")

        beginObject(2)
        let kids = pageObjects.map { "\($0.page) 0 R" }.joined(separator: " ")
        append("<< /Type /Pages /Kids [\(kids)] /Count \(pages.count) >>\nendobj\n")

        beginObject(3)
        let date = Self.pdfDate(metadata.creationDate)
        append("<< /Title \(Self.textString(metadata.title)) /Author \(Self.textString(metadata.author)) /Subject \(Self.textString(metadata.subject)) /Keywords \(Self.textString(metadata.keywords)) /Creator (DevisMinute) /Producer (DevisMinute PDF) /CreationDate (\(date)) /ModDate (\(date)) >>\nendobj\n")

        for (index, font) in fonts.enumerated() {
            beginObject(fontObjectBase + index)
            append("<< /Type /Font /Subtype /Type1 /BaseFont /\(font.rawValue) /Encoding /WinAnsiEncoding >>\nendobj\n")
        }

        for (index, image) in images.enumerated() {
            beginObject(imageObjectBase + index)
            let colorSpace = image.components == 1 ? "/DeviceGray" : (image.components == 4 ? "/DeviceCMYK /Decode [1 0 1 0 1 0 1 0]" : "/DeviceRGB")
            append("<< /Type /XObject /Subtype /Image /Width \(image.pixelWidth) /Height \(image.pixelHeight) /ColorSpace \(colorSpace) /BitsPerComponent 8 /Filter /DCTDecode /Length \(image.data.count) >>\nstream\n")
            output.append(image.data)
            append("\nendstream\nendobj\n")
        }

        let fontResources = fonts.enumerated().map { "/\($0.element.resourceName) \(fontObjectBase + $0.offset) 0 R" }.joined(separator: " ")
        for (page, numbers) in zip(pages, pageObjects) {
            let imageResources = page.usedImages.map { "/Im\($0) \(imageObjectBase + $0 - 1) 0 R" }.joined(separator: " ")
            let annotations = numbers.annotations.isEmpty ? "" : " /Annots [\(numbers.annotations.map { "\($0) 0 R" }.joined(separator: " "))]"
            beginObject(numbers.page)
            append("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 \(page.width) \(page.height)] /Resources << /Font << \(fontResources) >> /XObject << \(imageResources) >> /ProcSet [/PDF /Text /ImageC /ImageB] >> /Contents \(numbers.content) 0 R\(annotations) >>\nendobj\n")

            let raw = Data(page.operations.utf8)
            beginObject(numbers.content)
            if let deflate, let compressed = deflate(raw) {
                append("<< /Length \(compressed.count) /Filter /FlateDecode >>\nstream\n")
                output.append(compressed)
            } else {
                append("<< /Length \(raw.count) >>\nstream\n")
                output.append(raw)
            }
            append("\nendstream\nendobj\n")

            for (annotationNumber, link) in zip(numbers.annotations, page.links) {
                beginObject(annotationNumber)
                let rect = link.rect
                append("<< /Type /Annot /Subtype /Link /Rect [\(rect.0) \(rect.1) \(rect.2) \(rect.3)] /Border [0 0 0] /A << /S /URI /URI \(Self.textString(link.url)) >> >>\nendobj\n")
            }
        }

        let xrefOffset = output.count
        append("xref\n0 \(offsets.count + 1)\n0000000000 65535 f \n")
        for offset in offsets { append(String(format: "%010d 00000 n \n", offset)) }
        let identifier = DocumentIdentifier.make(metadata: metadata, size: output.count)
        append("trailer\n<< /Size \(offsets.count + 1) /Root 1 0 R /Info 3 0 R /ID [<\(identifier)> <\(identifier)>] >>\nstartxref\n\(xrefOffset)\n%%EOF\n")
        return output
    }

    /// Chaîne texte PDF en UTF-16BE (métadonnées : accents conservés).
    static func textString(_ text: String) -> String {
        var hex = "<FEFF"
        for unit in text.utf16 { hex += String(format: "%04X", unit) }
        return hex + ">"
    }

    static func pdfDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMddHHmmss"
        return "D:\(formatter.string(from: date))Z"
    }
}

enum DocumentIdentifier {
    /// Identifiant de fichier déterministe (FNV-1a 128 bits simplifié) : deux exports identiques
    /// produisent le même identifiant.
    static func make(metadata: PDFMetadata, size: Int) -> String {
        var h1: UInt64 = 0xcbf29ce484222325
        var h2: UInt64 = 0x84222325cbf29ce4
        let seed = "\(metadata.title)|\(metadata.author)|\(metadata.creationDate.timeIntervalSince1970)|\(size)"
        for byte in seed.utf8 {
            h1 = (h1 ^ UInt64(byte)) &* 0x100000001b3
            h2 = (h2 ^ UInt64(byte)) &* 0x100000001b3 &+ 0x9E3779B97F4A7C15
        }
        return String(format: "%016llX%016llX", h1, h2)
    }
}

/// Enveloppe zlib (RFC 1950) autour d'un flux DEFLATE brut (RFC 1951), requise par FlateDecode.
/// `NSData.compressed(using: .zlib)` d'Apple produit un flux brut : cette fonction l'encapsule.
public enum ZlibWrapper {
    public static func wrap(rawDeflate: Data, original: Data) -> Data {
        var result = Data([0x78, 0x9C])
        result.append(rawDeflate)
        var a: UInt32 = 1
        var b: UInt32 = 0
        for byte in original {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        let checksum = (b << 16) | a
        result.append(contentsOf: [UInt8(checksum >> 24), UInt8((checksum >> 16) & 0xFF), UInt8((checksum >> 8) & 0xFF), UInt8(checksum & 0xFF)])
        return result
    }
}
