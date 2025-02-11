import SwiftUI
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers
import Foundation
import Photos

public struct VideoPicker: UIViewControllerRepresentable {
    @Binding var selectedVideoURLs: [URL]
    private let viewModelWrapper: VideoUploadViewModelProtocol

    public init(selectedVideoURLs: Binding<[URL]>, viewModel: VideoUploadViewModelProtocol) {
        self._selectedVideoURLs = selectedVideoURLs
        self.viewModelWrapper = viewModel
    }

    public func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .videos
        configuration.selectionLimit = 0 // Allow multiple selections
        configuration.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    public func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private var parent: VideoPicker
        private let fileManager = FileManager.default
        private lazy var videosDirectory: URL = {
            let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let videosDirectory = documentsDirectory.appendingPathComponent("SelectedVideos", isDirectory: true)
            try? fileManager.createDirectory(at: videosDirectory, withIntermediateDirectories: true)
            return videosDirectory
        }()

        public init(_ parent: VideoPicker) {
            self.parent = parent
            super.init()
            // Clean up any existing files
            try? fileManager.removeItem(at: videosDirectory)
            try? fileManager.createDirectory(at: videosDirectory, withIntermediateDirectories: true)
        }

        public func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            print("📱 VideoPicker: Finished picking, results count: \(results.count)")

            guard !results.isEmpty else {
                print("❌ VideoPicker: No videos selected")
                self.parent.viewModelWrapper.setError(.videoProcessingFailed(reason: "No videos selected"))
                return
            }

            Task {
                do {
                    // Request photo library access
                    let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                    guard status == .authorized else {
                        throw NSError(domain: "VideoPicker", code: -1, userInfo: [NSLocalizedDescriptionKey: "Photo library access denied"])
                    }

                    var processedURLs: [(Int, URL)] = []

                    // Process videos sequentially to avoid any race conditions
                    for (index, result) in results.enumerated() {
                        print("🎬 Processing video \(index + 1) of \(results.count)")

                        // Get asset identifier
                        guard let assetIdentifier = result.assetIdentifier else {
                            print("❌ No asset identifier for video \(index)")
                            continue
                        }

                        // Fetch the asset
                        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
                        guard let asset = fetchResult.firstObject else {
                            print("❌ Could not fetch asset for video \(index)")
                            continue
                        }

                        // Get video resources
                        let resources = PHAssetResource.assetResources(for: asset)
                        guard let videoResource = resources.first(where: { $0.type == .video }) else {
                            print("❌ No video resource found for asset \(index)")
                            continue
                        }

                        print("📼 Found video resource: \(videoResource.originalFilename)")

                        // Create destination URL
                        let destinationURL = videosDirectory.appendingPathComponent("\(UUID().uuidString).mp4")

                        // Use async/await with continuation to handle the file writing
                        print("📝 Starting video copy to: \(destinationURL.path)")

                        // Copy the video file
                        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) -> Void in
                            PHAssetResourceManager.default().writeData(
                                for: videoResource,
                                toFile: destinationURL,
                                options: nil
                            ) { error in
                                if let error = error {
                                    print("❌ Error copying video resource: \(error.localizedDescription)")
                                    continuation.resume(throwing: error)
                                } else {
                                    print("✅ Successfully copied video resource")
                                    continuation.resume(returning: ())
                                }
                            }
                        }

                        // Verify the file exists and is readable
                        guard fileManager.fileExists(atPath: destinationURL.path),
                              fileManager.isReadableFile(atPath: destinationURL.path) else {
                            throw NSError(domain: "VideoPicker", code: -1, userInfo: [NSLocalizedDescriptionKey: "File verification failed"])
                        }

                        // Get file size for logging
                        let attributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
                        guard let fileSize = attributes[.size] as? Int64 else {
                            throw NSError(domain: "VideoPicker", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not read file size"])
                        }
                        print("📊 Copied file size: \(Float(fileSize) / 1_000_000)MB")

                        processedURLs.append((index, destinationURL))
                        print("✅ Successfully processed video \(index)")
                    }

                    // Update UI on main thread
                    try await MainActor.run {
                        let selectedVideoURLs = processedURLs.sorted { $0.0 < $1.0 }.map { $0.1 }

                        if selectedVideoURLs.isEmpty {
                            throw NSError(domain: "VideoPicker", code: -1, userInfo: [NSLocalizedDescriptionKey: "No valid videos found"])
                        }

                        print("📱 VideoPicker: Successfully processed \(selectedVideoURLs.count) videos")
                        print("📁 Video locations:")
                        selectedVideoURLs.forEach { url in
                            print("   - \(url.path)")
                            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
                                print("     Size: \(Float(attrs[.size] as? Int64 ?? 0) / 1_000_000)MB")
                            }
                        }
                        self.parent.selectedVideoURLs = selectedVideoURLs
                        self.parent.viewModelWrapper.setSelectedVideos(urls: selectedVideoURLs)
                        self.parent.viewModelWrapper.uploadVideos()
                    }
                } catch {
                    print("❌ Error processing videos: \(error.localizedDescription)")
                    await MainActor.run {
                        self.parent.viewModelWrapper.setError(.videoProcessingFailed(reason: error.localizedDescription))
                    }
                }
            }
        }
    }
}

#Preview {
    Color.clear // VideoPicker needs to be presented in a sheet
        .sheet(isPresented: .constant(true)) {
            VideoPicker(selectedVideoURLs: .constant([]), viewModel: DefaultVideoUploadViewModel())
        }
}
