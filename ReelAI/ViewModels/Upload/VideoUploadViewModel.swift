import SwiftUI
import FirebaseAuth
import FirebaseStorage
import FirebaseDatabase
import AVFoundation
import CoreMedia
import Network
import UIKit
import Foundation

@MainActor
final class VideoUploadViewModel: ObservableObject, VideoUploadViewModelProtocol {
    // MARK: - Published Properties
    @Published var uploadProgress: Double = 0
    @Published var isUploading = false
    @Published var errorMessage: String?
    @Published var selectedVideoURL: URL?
    @Published var thumbnailImage: UIImage?
    @Published var caption: String = ""
    @Published var uploadComplete = false
    @Published var lastUploadedVideoURL: URL?
    @Published var selectedQuality: VideoQuality = .medium
    @Published var shouldNavigateToProfile = false
    @Published var selectedVideoURLs: [URL] = []
    @Published var uploadedVideoURLs: [URL] = []
    @Published var uploadStatuses: [URL: UploadStatus] = [:]
    @Published var thumbnails: [URL: UIImage] = [:]
    @Published var networkStatus: NetworkMonitor.NetworkStatus = .unknown
    @Published var captions: [URL: String] = [:]

    // MARK: - Dependencies
    private let networkMonitor = NetworkMonitor.shared
    private let videoProcessor = VideoProcessor()
    private let storageManager: StorageManager
    private let databaseManager: FirebaseDatabaseManager

    // MARK: - Initialization
    init(storageManager: StorageManager, databaseManager: FirebaseDatabaseManager) {
        self.storageManager = storageManager
        self.databaseManager = databaseManager
        setupNetworkMonitoring()
    }

    // Convenience initializer with default dependencies
    convenience init() {
        self.init(storageManager: FirebaseStorageManager(), databaseManager: FirebaseDatabaseManager.shared)
    }

    private func setupNetworkMonitoring() {
        networkMonitor.startMonitoring { [weak self] status in
            guard let self = self else { return }
            self.networkStatus = status
        }
    }

    // MARK: - VideoUploadViewModelProtocol Implementation
    public func setSelectedVideos(urls: [URL]) {
        selectedVideoURLs = urls
        uploadStatuses = Dictionary(uniqueKeysWithValues: urls.map { ($0, .pending) })

        Task {
            await self.generateThumbnails(for: urls)
        }
    }

    public func setError(_ error: PublicUploadError) {
        errorMessage = error.localizedDescription
    }

    public func uploadVideos() {
        guard !selectedVideoURLs.isEmpty else {
            setError(.videoProcessingFailed(reason: "No videos selected"))
            return
        }

        guard networkMonitor.isConnected else {
            setError(.networkUnavailable)
            return
        }

        Task {
            self.isUploading = true

            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for url in selectedVideoURLs {
                        group.addTask {
                            try await self.uploadSingleVideo(url)
                        }
                    }
                    try await group.waitForAll()
                }

                await MainActor.run {
                    self.uploadComplete = true
                    self.isUploading = false
                }
            } catch {
                await MainActor.run {
                    self.setError(.videoProcessingFailed(reason: error.localizedDescription))
                    self.isUploading = false
                }
            }
        }
    }

    @MainActor
    private func uploadSingleVideo(_ url: URL) async throws {
        uploadStatuses[url] = .uploading(progress: 0)

        do {
            let processedURL = try await videoProcessor.compressVideo(at: url, quality: mapQuality(selectedQuality))
            let videoName = "\(UUID().uuidString)".replacingOccurrences(of: "-", with: "")

            // Upload video with progress tracking
            let downloadURL = try await storageManager.uploadVideo(processedURL, name: videoName) { progress in
                Task { @MainActor in
                    self.uploadStatuses[url] = .uploading(progress: progress)
                }
            }

            var thumbnailURL: URL?
            if let thumbnailImage = thumbnails[url],
               let thumbnailData = thumbnailImage.jpegData(compressionQuality: 0.8) {
                thumbnailURL = try await storageManager.uploadThumbnail(thumbnailData, for: videoName)
            }

            let video = Video(
                id: videoName,
                userId: Auth.auth().currentUser?.uid,
                videoURL: downloadURL,
                thumbnailURL: thumbnailURL,
                createdAt: Date(),
                caption: captions[url] ?? "",
                likes: 0,
                comments: 0,
                isDeleted: false,
                privacyLevel: .public
            )

            try await databaseManager.updateVideo(video)
            uploadStatuses[url] = .completed(downloadURL)
            uploadedVideoURLs.append(downloadURL)

        } catch {
            uploadStatuses[url] = .failed(error)
            throw error
        }
    }

    @MainActor
    func cancelUpload(for url: URL) {
        // Cancel the specific upload task
        storageManager.cancelUpload(for: url)
        uploadStatuses[url] = .failed(NSError(domain: "Upload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Upload cancelled"]))
    }

    func cancelUpload() {
        // Cancel all uploads
        for url in selectedVideoURLs {
            cancelUpload(for: url)
        }
        isUploading = false
    }

    // MARK: - Private Methods
    private func generateThumbnails(for urls: [URL]) async {
        await withTaskGroup(of: (URL, UIImage?).self) { group in
            for url in urls {
                group.addTask {
                    return (url, await self.generateThumbnail(for: url))
                }
            }

            for await (url, thumbnail) in group {
                if let thumbnail = thumbnail {
                    self.thumbnails[url] = thumbnail
                }
            }
        }
    }

    private func mapQuality(_ quality: VideoQuality) -> VideoProcessor.Quality {
        switch quality {
        case .high:
            return .high
        case .medium:
            return .medium
        case .low:
            return .low
        }
    }

    private func generateThumbnail(for videoURL: URL) async -> UIImage? {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        return await withCheckedContinuation { continuation in
            generator.generateCGImageAsynchronously(
                for: CMTime(seconds: 1, preferredTimescale: 60)
            ) { cgImage, _, error in
                if let error = error {
                    print("❌ Could not generate thumbnail for video: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }

                if let cgImage = cgImage {
                    continuation.resume(returning: UIImage(cgImage: cgImage))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
