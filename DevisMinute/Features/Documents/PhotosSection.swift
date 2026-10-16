import SwiftUI
import PhotosUI
import UIKit
import DevisCore

/// Photos jointes au document (chantier avant/après, produit…), imprimées en fin de PDF.
struct PhotosSection: View {
    @Binding var photos: [DocumentPhoto]?
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showCamera = false

    private var list: [DocumentPhoto] { photos ?? [] }
    private var remaining: Int { DocumentPhoto.maximumCount - list.count }

    var body: some View {
        Section {
            if !list.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Space.m) {
                        ForEach(list) { photo in
                            PhotoThumbnail(photo: photo, caption: binding(for: photo.id)) {
                                photos = list.filter { $0.id != photo.id }
                            }
                        }
                    }
                    .padding(.vertical, Theme.Space.xs)
                }
            }
            if remaining > 0 {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { showCamera = true } label: { Label("Prendre une photo", systemImage: "camera") }
                }
                PhotosPicker(selection: $pickerItems, maxSelectionCount: remaining, matching: .images) {
                    Label("Ajouter depuis la photothèque", systemImage: "photo.on.rectangle")
                }
            }
        } header: {
            Text("Photos")
        } footer: {
            Text("Jusqu'à \(DocumentPhoto.maximumCount) photos, imprimées avec leur légende à la fin du PDF.")
        }
        .onChange(of: pickerItems) { _, items in load(items) }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                showCamera = false
                if let image { append(image) }
            }
            .ignoresSafeArea()
        }
    }

    private func binding(for id: UUID) -> Binding<String> {
        Binding(
            get: { list.first { $0.id == id }?.caption ?? "" },
            set: { value in photos = list.map { $0.id == id ? DocumentPhoto(id: $0.id, jpeg: $0.jpeg, caption: value) : $0 } }
        )
    }

    private func append(_ image: UIImage) {
        guard remaining > 0, let jpeg = ReceiptProcessor.jpeg(from: image, maxDimension: 1400) else { return }
        photos = list + [DocumentPhoto(jpeg: jpeg)]
    }

    private func load(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task { @MainActor in
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { append(image) }
            }
            pickerItems = []
        }
    }
}

private struct PhotoThumbnail: View {
    let photo: DocumentPhoto
    @Binding var caption: String
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                if let image = UIImage(data: photo.jpeg) {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: 120, height: 90)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.55))
                }
                .buttonStyle(.plain)
                .padding(4)
                .accessibilityLabel("Retirer la photo")
            }
            TextField("Légende", text: $caption)
                .font(.caption)
                .frame(width: 120)
        }
    }
}

/// Appareil photo d'iOS.
struct CameraPicker: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void
        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onFinish(nil) }
    }
}
