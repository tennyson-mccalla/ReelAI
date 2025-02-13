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

// MARK: - Video Quality
public enum VideoQuality {
    case low
    case medium
    case high
}

// MARK: - Upload Status
public enum UploadStatus {
    case pending
    case uploading(progress: Double)
    case completed(URL)
    case failed(Error)
    case cancelled
}

// MARK: - Video Upload Protocol
@MainActor
public protocol VideoUploadViewModelProtocol: ObservableObject {
    var selectedVideoURLs: [URL] { get set }
    func setSelectedVideos(urls: [URL]) async
    func setError(_ error: PublicUploadError) async
}

public enum PublicUploadError: LocalizedError {
    case videoProcessingFailed(reason: String)
    case networkUnavailable

    public var errorDescription: String? {
        switch self {
        case .videoProcessingFailed(let reason):
            return "Video processing failed: \(reason)"
        case .networkUnavailable:
            return "Network connection required for upload"
        }
    }
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
    private let storage = Storage.storage().reference()
    private let database = Database.database().reference()
    private let networkMonitor: NetworkMonitor
    private let videoProcessor: VideoProcessor
    private let authService: AuthServiceProtocol
    private var uploadTasks: [URL: StorageUploadTask] = [:]

    // MARK: - Initialization
    init(authService: AuthServiceProtocol = FirebaseAuthService.shared) {
        self.authService = authService
        self.networkMonitor = NetworkMonitor.shared
        self.videoProcessor = VideoProcessor()

        Task { @MainActor in
            setupNetworkMonitoring()
        }
    }

    // MARK: - VideoUploadViewModelProtocol Implementation
    public func setSelectedVideos(urls: [URL]) async {
        selectedVideoURLs = urls
        uploadStatuses = Dictionary(uniqueKeysWithValues: urls.map { ($0, .pending) })
        await generateThumbnails(for: urls)
    }

    public func setError(_ error: PublicUploadError) async {
        errorMessage = error.localizedDescription
    }

    @MainActor
    func uploadVideos() {
        Task {
            guard !selectedVideoURLs.isEmpty else {
                await setError(.videoProcessingFailed(reason: "No videos selected"))
                return
            }

            guard networkMonitor.isConnected else {
                await setError(.networkUnavailable)
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

                do {
                    let downloadURL = try await processAndUploadVideo(at: url, index: index)
                    successCount += 1
                    uploadStatuses[url] = .completed(downloadURL)
                    uploadedVideoURLs.append(downloadURL)
                } catch {
                    failedCount += 1
                    uploadStatuses[url] = .failed(error)
                    logger.error("Failed to upload video: \(error.localizedDescription)")
                    break
                }
            }

            handleUploadCompletion(successCount: successCount, failedCount: failedCount)
        }
    }

    private func handleUploadCompletion(successCount: Int, failedCount: Int) {
        if successCount > 0 {
            // Clear successful uploads but keep failed ones
            selectedVideoURLs = selectedVideoURLs.filter { url in
                if case .failed = uploadStatuses[url] { return true }
                return false
            }

            cleanupSuccessfulUploads()

            // Set success message and navigate
            successMessage = successCount == 1 ? "Video uploaded successfully!" :
                           "Successfully uploaded \(successCount) videos!"
            shouldNavigateToProfile = true
        }

        // Reset Create tab state if all uploads completed
        if failedCount == 0 {
            resetState()
        }
    }

    private func cleanupSuccessfulUploads() {
        thumbnails = thumbnails.filter { url, _ in
            if case .failed = uploadStatuses[url] { return true }
            return false
        }
        captions = captions.filter { url, _ in
            if case .failed = uploadStatuses[url] { return true }
            return false
        }
        uploadStatuses = uploadStatuses.filter { url, status in
            if case .failed = status { return true }
            return false
        }
    }

    @MainActor
    private func processAndUploadVideo(at url: URL, index: Int) async throws -> URL {
        uploadStatuses[url] = .uploading(progress: 0.0)

        do {
            let processedURL = try await videoProcessor.compressVideo(at: url, quality: mapQuality(selectedQuality))
            let videoName = "\(UUID().uuidString)".replacingOccurrences(of: "-", with: "")
            let videoRef = storage.child("videos").child(videoName)

            // Upload video with progress tracking
            let metadata = StorageMetadata()
            metadata.contentType = "video/mp4"

            let downloadURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                let task = videoRef.putFile(from: processedURL, metadata: metadata) { metadata, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }

                    videoRef.downloadURL { url, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else if let url = url {
                            continuation.resume(returning: url)
                        } else {
                            continuation.resume(throwing: NSError(domain: "Upload", code: -1))
                        }
                    }
                }

                task.observe(.progress) { snapshot in
                    Task { @MainActor in
                        let progress = Double(snapshot.progress?.completedUnitCount ?? 0) /
                            Double(snapshot.progress?.totalUnitCount ?? 1)
                        self.uploadStatuses[url] = .uploading(progress: progress)
                    }
                }

                self.uploadTasks[url] = task
            }

            // Upload thumbnail if available
            var thumbnailURL: URL?
            if let thumbnailImage = thumbnails[url],
               let thumbnailData = thumbnailImage.jpegData(compressionQuality: 0.8) {
                let thumbnailRef = storage.child("thumbnails").child(videoName)
                _ = try await thumbnailRef.putDataAsync(thumbnailData)
                thumbnailURL = try await thumbnailRef.downloadURL()
            }

            // Update database
            let video = [
                "id": videoName,
                "userId": Auth.auth().currentUser?.uid ?? "",
                "videoURL": downloadURL.absoluteString,
                "thumbnailURL": thumbnailURL?.absoluteString as Any,
                "createdAt": ServerValue.timestamp(),
                "caption": captions[url] ?? "",
                "likes": 0,
                "comments": 0,
                "isDeleted": false,
                "privacyLevel": "public"
            ] as [String: Any]

            try await database.child("videos").child(videoName).setValue(video)
            return downloadURL

        } catch {
            logger.error("Failed to process and upload video: \(error.localizedDescription)")
            uploadStatuses[url] = .failed(error)
            throw error
        }
    }

    @MainActor
    func cancelUpload(for url: URL) {
        uploadTasks[url]?.cancel()
        uploadStatuses[url] = .cancelled
        uploadTasks[url] = nil
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

    private func setupNetworkMonitoring() {
        networkMonitor.startMonitoring { [weak self] status in
            guard let self = self else { return }
            self.networkStatus = status
        }
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
