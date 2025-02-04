import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct VideoPicker: UIViewControllerRepresentable {
    @ObservedObject var viewModel: VideoUploadViewModel
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: VideoPicker
        
        init(_ parent: VideoPicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            print("📱 Video picker finished with \(results.count) results")
            parent.presentationMode.wrappedValue.dismiss()
            
            guard let provider = results.first?.itemProvider else {
                print("❌ No item provider found")
                return
            }
            
            // Check for video type identifier
            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                print("📱 Loading video file")
                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                    if let error = error {
                        DispatchQueue.main.async {
                            print("❌ Error loading video: \(error.localizedDescription)")
                            self.parent.viewModel.errorMessage = error.localizedDescription
                        }
                        return
                    }
                    
                    guard let url = url else {
                        print("❌ No URL received")
                        return
                    }
                    
                    // Create a local copy of the video
                    let fileName = url.lastPathComponent
                    let localURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                    
                    do {
                        // Remove any existing file
                        try? FileManager.default.removeItem(at: localURL)
                        // Copy the file to our temporary directory
                        try FileManager.default.copyItem(at: url, to: localURL)
                        
                        DispatchQueue.main.async {
                            print("✅ Got video URL: \(localURL)")
                            self.parent.viewModel.setSelectedVideo(url: localURL)
                        }
                    } catch {
                        DispatchQueue.main.async {
                            print("❌ Error copying video: \(error.localizedDescription)")
                            self.parent.viewModel.errorMessage = "Error preparing video: \(error.localizedDescription)"
                        }
                    }
                }
            } else {
                print("❌ Selected item is not a video")
                DispatchQueue.main.async {
                    self.parent.viewModel.errorMessage = "Please select a video file"
                }
            }
        }
    }
} 