import SwiftUI
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers
import Foundation
import Photos

public struct VideoPicker: UIViewControllerRepresentable {
    @Binding var selectedVideoURLs: [URL]
    private let viewModelWrapper: any VideoUploadViewModelProtocol

    public init(selectedVideoURLs: Binding<[URL]>, viewModel: any VideoUploadViewModelProtocol) {
        self._selectedVideoURLs = selectedVideoURLs
        self.viewModelWrapper = viewModel
    }

    public func makeUIViewController(context: Context) -> PHPickerViewController {
        // Configure picker first
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .videos
        configuration.selectionLimit = 0 // Allow multiple selections
        configuration.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator

        // Check permissions after returning picker
        Task { @MainActor in
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            if status != .authorized {
                await viewModelWrapper.setError(.videoProcessingFailed(reason: "Photo library access is required to select videos"))
            }
        }

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
                print("ℹ️ VideoPicker: Selection cancelled or no videos selected")
                return
            }

            // Start processing in background
            Task { @MainActor in
                do {
                    var processedURLs: [(Int, URL)] = []

                    // Process videos sequentially to avoid race conditions
                    for (index, result) in results.enumerated() {
                        print("🎬 Processing video \(index + 1) of \(results.count)")

                        guard let assetIdentifier = result.assetIdentifier else {
                            print("❌ No asset identifier for video \(index)")
                            continue
                        }

                        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
                        guard let asset = fetchResult.firstObject else {
                            print("❌ Could not fetch asset for video \(index)")
                            continue
                        }

                        let resources = PHAssetResource.assetResources(for: asset)
                        guard let videoResource = resources.first(where: { $0.type == .video }) else {
                            print("❌ No video resource found for asset \(index)")
                            continue
                        }

                        print("📼 Found video resource: \(videoResource.originalFilename)")
                        let destinationURL = videosDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
                        print("📝 Starting video copy to: \(destinationURL.path)")

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

                        guard fileManager.fileExists(atPath: destinationURL.path),
                              fileManager.isReadableFile(atPath: destinationURL.path) else {
                            throw NSError(domain: "VideoPicker", code: -1, userInfo: [NSLocalizedDescriptionKey: "File verification failed"])
                        }

                        processedURLs.append((index, destinationURL))
                        print("✅ Successfully processed video \(index)")
                    }

                    let selectedVideoURLs = processedURLs.sorted { $0.0 < $1.0 }.map { $0.1 }

                    if selectedVideoURLs.isEmpty {
                        throw NSError(domain: "VideoPicker", code: -1, userInfo: [NSLocalizedDescriptionKey: "No valid videos found"])
                    }

                    print("📱 VideoPicker: Successfully processed \(selectedVideoURLs.count) videos")
                    self.parent.selectedVideoURLs = selectedVideoURLs
                    await self.parent.viewModelWrapper.setSelectedVideos(urls: selectedVideoURLs)
                } catch {
                    print("❌ Error processing videos: \(error.localizedDescription)")
                    await self.parent.viewModelWrapper.setError(.videoProcessingFailed(reason: error.localizedDescription))
                }
            }
        }
    }
}
