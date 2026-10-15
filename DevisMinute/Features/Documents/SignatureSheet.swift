import SwiftUI
import UIKit
import DevisCore

/// Signature du devis par le client, au doigt, directement sur l'iPhone.
/// Le devis passe en « Accepté » et le PDF imprime la signature dans la zone « Bon pour accord ».
struct SignatureSheet: View {
    @Environment(AppDataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let record: DocumentRecord
    let onSigned: () -> Void

    @State private var signerName: String
    @State private var place: String
    @State private var agreed = false
    @State private var strokes: [[CGPoint]] = []
    @State private var padSize: CGSize = .zero
    @State private var error: PresentedError?

    init(record: DocumentRecord, initialStrokes: [[CGPoint]] = [], onSigned: @escaping () -> Void) {
        self.record = record
        self.onSigned = onSigned
        _strokes = State(initialValue: initialStrokes)
        _agreed = State(initialValue: !initialStrokes.isEmpty)
        let customer = record.document.customer
        _signerName = State(initialValue: customer.contactName.isEmpty ? (customer.kind == .individual ? customer.name : "") : customer.contactName)
        _place = State(initialValue: customer.address.city)
    }

    private var hasDrawing: Bool { strokes.contains { $0.count > 1 } }

    var body: some View {
        let document = record.document
        let totals = DocumentCalculator.totals(for: document)
        Form {
            Section {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("Devis \(document.number) · \(document.customer.name)").font(.footnote).foregroundStyle(Theme.neutral)
                    AmountText(value: totals.totalTTC, style: .title)
                    Text(document.chargesVAT ? "Total TTC" : "Total").font(.footnote).foregroundStyle(Theme.neutral)
                }
                .padding(.vertical, Theme.Space.xs)
            }
            Section("Signataire") {
                TextField("Nom et prénom", text: $signerName)
                    .textContentType(.name)
                TextField("Lieu (facultatif)", text: $place)
                    .textContentType(.addressCity)
            }
            Section {
                Toggle(isOn: $agreed) {
                    Text("« \(QuoteSignature.acceptanceMention) »").font(.subheadline)
                }
                .tint(Theme.petrol)
                SignaturePad(strokes: $strokes, size: $padSize)
                    .frame(height: 200)
                    .listRowInsets(EdgeInsets())
                if hasDrawing {
                    Button("Effacer la signature", role: .destructive) { strokes.removeAll() }
                }
            } header: {
                Text("Signature du client")
            } footer: {
                Text("Signature électronique simple : la date, le nom et une empreinte du devis sont enregistrés. Une fois signé, le devis ne peut plus être modifié.")
            }
        }
        .appBackground()
        .navigationTitle("Faire signer")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(hasDrawing)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Valider") { sign() }
                    .fontWeight(.semibold)
                    .disabled(!agreed || !hasDrawing || signerName.trimmed.isEmpty)
            }
        }
        .errorAlert($error)
    }

    private func sign() {
        guard let jpeg = SignatureRenderer.jpeg(strokes: strokes, canvasSize: padSize) else {
            error = PresentedError(SignatureError.missingDrawing)
            return
        }
        do {
            _ = try store.signQuote(id: record.id, signerName: signerName, place: place, imageJPEG: jpeg)
            onSigned()
            dismiss()
        } catch {
            self.error = PresentedError(error)
        }
    }
}

/// Zone de dessin au doigt.
struct SignaturePad: View {
    @Binding var strokes: [[CGPoint]]
    @Binding var size: CGSize

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                Color.white
                // Ligne de signature
                Rectangle().fill(Theme.neutral.opacity(0.35)).frame(height: 1)
                    .padding(.horizontal, 24).padding(.bottom, 44)
                if strokes.isEmpty {
                    Text("Signez ici avec le doigt")
                        .font(.callout).foregroundStyle(Theme.neutral.opacity(0.8))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Path { path in SignatureRenderer.add(strokes, to: &path) }
                    .stroke(Color(red: 0.08, green: 0.12, blue: 0.25), style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
            }
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        let point = CGPoint(x: min(max(0, value.location.x), proxy.size.width), y: min(max(0, value.location.y), proxy.size.height))
                        if value.translation == .zero || strokes.isEmpty {
                            strokes.append([point])
                        } else {
                            strokes[strokes.count - 1].append(point)
                        }
                    }
            )
            .onAppear { size = proxy.size }
            .onChange(of: proxy.size) { _, newSize in size = newSize }
        }
        .accessibilityLabel("Zone de signature")
    }
}

/// Conversion du tracé en JPEG (fond blanc, recadré sur la signature).
enum SignatureRenderer {
    static func add(_ strokes: [[CGPoint]], to path: inout Path) {
        for stroke in strokes {
            guard let first = stroke.first else { continue }
            path.move(to: first)
            if stroke.count == 1 {
                path.addLine(to: CGPoint(x: first.x + 0.5, y: first.y + 0.5))
                continue
            }
            // Courbes lissées entre les milieux des segments.
            for index in 1..<stroke.count {
                let previous = stroke[index - 1]
                let current = stroke[index]
                let middle = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
                path.addQuadCurve(to: middle, control: previous)
            }
            if let last = stroke.last { path.addLine(to: last) }
        }
    }

    static func jpeg(strokes: [[CGPoint]], canvasSize: CGSize) -> Data? {
        let points = strokes.flatMap { $0 }
        guard points.count > 1, canvasSize.width > 0 else { return nil }
        let margin: CGFloat = 8
        let minX = max(0, (points.map(\.x).min() ?? 0) - margin)
        let minY = max(0, (points.map(\.y).min() ?? 0) - margin)
        let maxX = min(canvasSize.width, (points.map(\.x).max() ?? 0) + margin)
        let maxY = min(canvasSize.height, (points.map(\.y).max() ?? 0) + margin)
        let crop = CGRect(x: minX, y: minY, width: max(maxX - minX, 20), height: max(maxY - minY, 20))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: crop.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: crop.size))
            var path = Path()
            add(strokes, to: &path)
            let cgContext = context.cgContext
            cgContext.translateBy(x: -crop.minX, y: -crop.minY)
            cgContext.addPath(path.cgPath)
            cgContext.setStrokeColor(UIColor(red: 0.08, green: 0.12, blue: 0.25, alpha: 1).cgColor)
            cgContext.setLineWidth(2.6)
            cgContext.setLineCap(.round)
            cgContext.setLineJoin(.round)
            cgContext.strokePath()
        }
        return image.jpegData(compressionQuality: 0.85)
    }
}
