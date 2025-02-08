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
            print("📱 VideoPicker: Finished picking, results count: \(results.count)")

            guard let provider = results.first?.itemProvider else {
                print("❌ VideoPicker: No provider available")
                parent.viewModel.setError("No video selected")
                return
            }

            print("📱 VideoPicker: Got provider, checking if file is a video")
            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                print("📱 VideoPicker: Loading video file")
                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                    if let error = error {
                        print("❌ VideoPicker: Error loading file: \(error.localizedDescription)")
                        Task { @MainActor in
                            self.parent.viewModel.setError(error.localizedDescription)
                        }
                        return
                    }

                    guard let url = url else {
                        print("❌ VideoPicker: URL is nil")
                        Task { @MainActor in
                            self.parent.viewModel.setError("Could not load video")
                        }
                        return
                    }

                    print("📱 VideoPicker: Got URL: \(url.path)")
                    // Copy to temporary location
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension("mp4")

                    do {
                        try FileManager.default.copyItem(at: url, to: tempURL)
                        print("📱 VideoPicker: Copied to temp URL: \(tempURL.path)")
                        Task { @MainActor in
                            self.parent.viewModel.setSelectedVideo(url: tempURL)
                        }
                    } catch {
                        print("❌ VideoPicker: Error copying file: \(error.localizedDescription)")
                        Task { @MainActor in
                            self.parent.viewModel.setError("Could not copy video: \(error.localizedDescription)")
                        }
                    }
                }
            } else {
                print("❌ VideoPicker: Provider cannot load URL")
                parent.viewModel.setError("Selected file is not a video")
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
