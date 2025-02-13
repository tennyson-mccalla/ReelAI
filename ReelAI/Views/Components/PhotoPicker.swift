import SwiftUI
import PhotosUI
import Photos
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "PhotoPicker")

struct PhotoPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedImage: UIImage?

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        config.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker

        init(_ parent: PhotoPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else {
                logger.debug("No image selected")
                parent.dismiss()
                return
            }

            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { [weak self] image, error in
                    DispatchQueue.main.async {
                        if let error = error {
                            logger.error("Failed to load image: \(error.localizedDescription)")
                            self?.parent.dismiss()
                            return
                        }

                        guard let image = image as? UIImage else {
                            logger.error("Invalid image format")
                            self?.parent.dismiss()
                            return
                        }

                        self?.parent.selectedImage = image
                        self?.parent.dismiss()
                    }
                }
            } else {
                logger.error("Selected item is not an image")
                parent.dismiss()
            }
        }
    }
}

#Preview {
    // Wrap in a button to demonstrate typical usage
    Button("Select Photo") {
        // This view would normally be shown in a sheet
    }
    .sheet(isPresented: .constant(true)) {
        PhotoPicker(selectedImage: .constant(nil))
    }
}
