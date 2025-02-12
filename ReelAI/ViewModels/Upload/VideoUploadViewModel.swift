import SwiftUI
import FirebaseAuth
import FirebaseStorage
import FirebaseDatabase
import AVFoundation
import CoreMedia
import Network
import UIKit
import Foundation
import os

// MARK: - Network Types
public enum NetworkStatus {
    case satisfied
    case unsatisfied
    case requiresConnection
    case unknown
}

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
    @Published private(set) var networkStatus: NetworkMonitor.NetworkStatus = .unknown
    @Published var captions: [URL: String] = [:]
    @Published var successMessage: String?

    // MARK: - Private Properties
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReelAI", category: "VideoUploadViewModel")

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
        switch error {
        case .videoProcessingFailed(let reason):
            errorMessage = "Failed to process video: \(reason)"
        case .networkUnavailable:
            errorMessage = "Network is unavailable"
        case .storageError:
            errorMessage = "Storage error occurred"
        case .networkError:
            errorMessage = "Network error occurred"
        case .unknownError:
            errorMessage = "An unknown error occurred"
        }
    }

    @MainActor
    func uploadVideos() {
        Task {
            guard !selectedVideoURLs.isEmpty else {
                setError(.videoProcessingFailed(reason: "No videos selected"))
                return
            }

            guard NetworkMonitor.shared.isConnected else {
                setError(.networkUnavailable)
                return
            }

            var successCount = 0
            var failedCount = 0

            for (index, url) in selectedVideoURLs.enumerated() {
                if case .cancelled = uploadStatuses[url] {
                    continue
                }

                // Update UI to show we're processing this video
                uploadStatuses[url] = .uploading(progress: 0.0)

                var encounteredError: Error?
                // Process and upload video in background
                await withTaskGroup(of: Result<URL, Error>.self) { group in
                    group.addTask { [self] in
                        do {
                            await MainActor.run {
                                uploadStatuses[url] = .uploading(progress: 0.0)
                            }
                            let _ = try await processAndUploadVideo(at: url, index: index)
                            if let downloadURL = await uploadedVideoURLs.last {
                                return .success(downloadURL)
                            } else {
                                return .failure(PublicUploadError.unknownError)
                            }
                        } catch {
                            await MainActor.run {
                                uploadStatuses[url] = .failed(error)
                                logger.error("Failed to upload video: \(error.localizedDescription)")
                            }
                            return .failure(error)
                        }
                    }

                    // Wait for task completion and handle result
                    for await result in group {
                        switch result {
                        case .success(let downloadURL):
                            await MainActor.run {
                                successCount += 1
                                uploadStatuses[url] = .completed(downloadURL)
                            }
                        case .failure(let error):
                            await MainActor.run {
                                failedCount += 1
                                uploadStatuses[url] = .failed(error)
                                logger.error("Failed to upload video: \(error.localizedDescription)")
                            }
                            encounteredError = error
                        }
                    }
                }

                if encounteredError != nil {
                    break
                }
            }

            // Only navigate if we had at least one successful upload
            if successCount > 0 {
                // Clear successful uploads but keep failed ones
                selectedVideoURLs = selectedVideoURLs.filter { url in
                    if case .failed = uploadStatuses[url] {
                        return true
                    }
                    return false
                }
                thumbnails = thumbnails.filter { url, _ in
                    if case .failed = uploadStatuses[url] {
                        return true
                    }
                    return false
                }
                captions = captions.filter { url, _ in
                    if case .failed = uploadStatuses[url] {
                        return true
                    }
                    return false
                }
                uploadStatuses = uploadStatuses.filter { url, status in
                    if case .failed = status {
                        return true
                    }
                    return false
                }

                // Set success message and navigate
                let message = successCount == 1 ? "Video uploaded successfully!" :
                             "Successfully uploaded \(successCount) videos!"
                successMessage = message
                shouldNavigateToProfile = true
            }

            // Reset Create tab state if all uploads completed
            if failedCount == 0 {
                resetState()
            }
        }
    }

    @MainActor
    private func processAndUploadVideo(at url: URL, index: Int) async throws {
        uploadStatuses[url] = .uploading(progress: 0.0)

        do {
            let processedURL = try await videoProcessor.compressVideo(at: url, quality: mapQuality(selectedQuality))
            let videoName = "\(UUID().uuidString)".replacingOccurrences(of: "-", with: "")

            // Upload video with progress tracking
            let downloadURL = try await storageManager.uploadVideo(
                processedURL,
                name: videoName,
                progressHandler: { progress in
                    Task { @MainActor in
                        self.uploadStatuses[url] = .uploading(progress: progress)
                    }
                }
            )

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
            logger.error("Failed to process and upload video: \(error.localizedDescription)")
            uploadStatuses[url] = .failed(error)
            throw error
        }
    }

    @MainActor
    func cancelUpload(for url: URL) {
        // Cancel the specific upload task
        storageManager.cancelUpload(for: url)
        uploadStatuses[url] = .cancelled
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

    private func resetState() {
        // Implementation of resetState method
    }
}

// Add Equatable conformance for UploadStatus
extension UploadStatus: Equatable {
    public static func == (lhs: UploadStatus, rhs: UploadStatus) -> Bool {
        switch (lhs, rhs) {
        case (.pending, .pending):
            return true
        case let (.uploading(p1), .uploading(p2)):
            return p1 == p2
        case let (.completed(url1), .completed(url2)):
            return url1 == url2
        case let (.failed(e1), .failed(e2)):
            return e1.localizedDescription == e2.localizedDescription
        case (.cancelled, .cancelled):
            return true
        default:
            return false
        }
    }
}
