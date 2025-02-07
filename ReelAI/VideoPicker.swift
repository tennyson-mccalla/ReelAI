import SwiftUI
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers  // Add back for UTType

struct VideoPicker: UIViewControllerRepresentable {
    @ObservedObject var viewModel: VideoUploadViewModel

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 1
        config.filter = .videos

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: VideoPicker

        init(parent: VideoPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            guard let provider = results.first?.itemProvider else {
                parent.viewModel.setError("No video selected")
                return
            }

            if provider.canLoadObject(ofClass: URL.self) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                    if let error = error {
                        Task { @MainActor in
                            self.parent.viewModel.setError(error.localizedDescription)
                        }
                        return
                    }

                    guard let url = url else {
                        Task { @MainActor in
                            self.parent.viewModel.setError("Could not load video")
                        }
                        return
                    }

                    // Copy to temporary location
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension("mp4")

                    do {
                        try FileManager.default.copyItem(at: url, to: tempURL)
                        Task { @MainActor in
                            self.parent.viewModel.setSelectedVideo(url: tempURL)
                        }
                    } catch {
                        Task { @MainActor in
                            self.parent.viewModel.setError("Could not copy video: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    Color.clear // VideoPicker needs to be presented in a sheet
        .sheet(isPresented: .constant(true)) {
            VideoPicker(viewModel: VideoUploadViewModel())
        }
}
