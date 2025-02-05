import Foundation
import FirebaseStorage
import AVFoundation
import UIKit
import FirebaseFirestore
import FirebaseAuth

enum VideoQuality {
    case high    // 1080p, 8Mbps
    case medium  // 720p, 5Mbps
    case low     // 480p, 2Mbps
    case custom(width: Int, bitrate: Int)

    var configuration: (width: Int, bitrate: Int) {
        switch self {
        case .high:    return (1920, 8_000_000)
        case .medium:  return (1280, 5_000_000)
        case .low:     return (858, 2_000_000)
        case .custom(let width, let bitrate): return (width, bitrate)
        }
    }

    var exportPreset: String {
        switch self {
        case .high: return AVAssetExportPreset1920x1080
        case .medium: return AVAssetExportPreset1280x720
        case .low: return AVAssetExportPreset640x480
        case .custom: return AVAssetExportPresetPassthrough
        }
    }
}

class VideoUploadViewModel: ObservableObject {
    @Published var uploadProgress: Double = 0
    @Published var isUploading = false
    @Published var errorMessage: String?
    @Published var selectedVideoURL: URL?
    @Published var thumbnailImage: UIImage?
    @Published var caption: String = ""
    @Published var uploadComplete = false
    @Published var lastUploadedVideoURL: URL?
    @Published var selectedQuality: VideoQuality = .medium

    private let storage = Storage.storage().reference()
    private let db = Firestore.firestore()
    private var thumbnailURL: String?
    private var currentUploadTask: StorageUploadTask?

    private func compressVideo(at sourceURL: URL, quality: VideoQuality) async throws -> URL {
        let inputSize = try sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        print("📱 Original video size: \(Float(inputSize) / 1_000_000)MB")

        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent(UUID().uuidString + ".mp4")

        let asset = AVURLAsset(url: sourceURL)

        // Simplified approach - use export session directly on asset
        guard let exportSession = AVAssetExportSession(asset: asset,
                                                     presetName: quality.exportPreset) else {
            throw NSError(domain: "VideoCompression",
                         code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Could not create export session"])
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        // New iOS 18 API
        try await exportSession.export(to: outputURL, as: .mp4)

        // Just check if the export completed successfully
        if let outputSize = try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            print("📱 Compressed video size: \(Float(outputSize) / 1_000_000)MB")
            print("📱 Compression ratio: \(Float(outputSize) / Float(inputSize))")
            return outputURL
        }

        // If we get here, something went wrong
        throw NSError(domain: "VideoCompression", code: -1)
    }

    func uploadVideo() {
        print("📱 Starting upload process")
        guard let videoURL = selectedVideoURL else {
            print("❌ No video URL selected")
            errorMessage = "No video selected"
            return
        }

        guard NetworkMonitor.shared.isConnected else {
            print("❌ No network connection")
            errorMessage = "No internet connection. Please try again."
            return
        }

        isUploading = true
        errorMessage = nil
        handleVideoUpload(from: videoURL)
    }

    private func handleVideoUpload(from videoURL: URL) {
        Task {
            do {
                try await processUploadedVideo(from: videoURL)
            } catch {
                await handleUploadError(error)
            }
        }
    }

    private func processUploadedVideo(from videoURL: URL) async throws {
        print("📱 Starting video compression")
        let compressedVideoURL = try await compressVideo(at: videoURL, quality: selectedQuality)

        let videoName = UUID().uuidString + ".mp4"
        print("📱 Starting video upload: \(videoName)")

        try await uploadVideoFile(compressedVideoURL, name: videoName)
        print("✅ Video upload complete")

        try? FileManager.default.removeItem(at: compressedVideoURL)
        print("✅ Cleaned up temporary files")

        if let thumbnail = thumbnailImage {
            print("�� Starting thumbnail upload")
            try await uploadThumbnail(thumbnail, for: videoName)
            print("✅ Thumbnail upload complete")
        }

        try await handleMetadataSave(for: videoName)
    }

    private func handleMetadataSave(for videoName: String) async throws {
        print("📱 Saving metadata")
        do {
            try await saveVideoMetadata(videoName: videoName)
            print("✅ Metadata saved")
            print("📱 About to start final UI update")

            await updateUIAfterSuccess()
        } catch let error as NSError {
            print("❌ Metadata save failed: \(error.localizedDescription)")
            await updateUIAfterMetadataError(error)
        }
    }

    private func handleUploadError(_ error: Error) async {
        print("❌ Error occurred: \(error.localizedDescription)")
        await MainActor.run {
            print("❌ Upload error: \(error.localizedDescription)")
            let nsError = error as NSError
            if nsError.domain == StorageErrorDomain &&
               nsError.code == StorageErrorCode.cancelled.rawValue {
                errorMessage = "Upload canceled"
            } else {
                errorMessage = "Upload failed: \(error.localizedDescription)"
            }
            isUploading = false
        }
    }

    @MainActor
    private func updateUIAfterSuccess() {
        print("📱 Inside MainActor.run")
        print("📱 Starting final UI update")
        uploadComplete = true
        isUploading = false
        selectedVideoURL = nil
        thumbnailImage = nil
        caption = ""
        errorMessage = "✅ Upload complete! Your video will appear in your profile soon."
        print("✅ Upload complete with UI update")
    }

    @MainActor
    private func updateUIAfterMetadataError(_ error: NSError) {
        uploadComplete = true
        isUploading = false
        selectedVideoURL = nil
        thumbnailImage = nil
        caption = ""
        if error.domain == "NSPOSIXErrorDomain" && error.code == 50 {
            errorMessage = "✅ Video uploaded! Details will sync when network improves."
        } else {
            errorMessage = "Video uploaded but details couldn't be saved: \(error.localizedDescription)"
        }
    }

    private func uploadVideoFile(_ url: URL, name: String) async throws {
        let videoRef = storage.child("videos/\(name)")
        let metadata = StorageMetadata()
        metadata.contentType = "video/mp4"

        return try await withCheckedThrowingContinuation { continuation in
            let uploadTask = videoRef.putFile(from: url, metadata: metadata) { _, error in
                if let error = error as NSError? {
                    if error.domain == StorageErrorDomain && error.code == StorageErrorCode.cancelled.rawValue {
                        // Handle canceled upload
                        print("📱 Upload canceled by user")
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                continuation.resume(returning: ())
            }

            self.currentUploadTask = uploadTask

            uploadTask.observe(.progress) { [weak self] snapshot in
                let progress = Double(snapshot.progress?.completedUnitCount ?? 0) / Double(snapshot.progress?.totalUnitCount ?? 1)
                print("📱 Upload progress: \(progress * 100)%")
                Task { @MainActor in
                    self?.uploadProgress = progress
                }
            }
        }
    }

    private func uploadThumbnail(_ image: UIImage, for videoName: String) async throws {
        guard let thumbnailData = image.jpegData(compressionQuality: 0.7) else {
            throw NSError(domain: "ThumbnailError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not create thumbnail data"])
        }

        let thumbnailName = UUID().uuidString + ".jpg"
        let thumbnailRef = storage.child("thumbnails/\(thumbnailName)")

        return try await withCheckedThrowingContinuation { continuation in
            thumbnailRef.putData(thumbnailData, metadata: nil) { [weak self] _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                thumbnailRef.downloadURL { url, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }

                    if let thumbnailURL = url?.absoluteString {
                        self?.thumbnailURL = thumbnailURL
                        continuation.resume(returning: ())
                    } else {
                        continuation.resume(throwing: NSError(domain: "ThumbnailError", code: -1))
                    }
                }
            }
        }
    }

    private func saveVideoMetadata(videoName: String) async throws {
        print("📱 Starting metadata save...")

        // Try up to 3 times with increasing delays
        for attempt in 1...3 {
            guard NetworkMonitor.shared.isConnected else {
                print("❌ Attempt \(attempt): No network connection")
                if attempt == 3 {
                    throw NSError(domain: "UploadError",
                                code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "Network connection lost"])
                }
                try await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
                continue
            }

            do {
                guard let user = Auth.auth().currentUser else {
                    print("❌ No authenticated user")
                    throw NSError(domain: "UploadError", code: -1)
                }
                print("📱 Got user (attempt \(attempt))")
                print("📱 Network status: \(NetworkMonitor.shared.connectionType)")

                let videoRef = storage.child("videos/\(videoName)")
                print("📱 Getting download URL (attempt \(attempt))")
                let downloadURL = try await videoRef.downloadURL()
                print("✅ Got download URL")
                self.lastUploadedVideoURL = downloadURL

                let videoData: [String: Any] = [
                    "userId": user.uid,
                    "videoName": videoName,
                    "caption": caption.trimmingCharacters(in: .whitespacesAndNewlines),
                    "thumbnailURL": thumbnailURL ?? "",
                    "timestamp": FieldValue.serverTimestamp(),
                    "likes": 0,
                    "comments": 0,
                    "videoURL": downloadURL.absoluteString  // Add video URL to metadata
                ]

                print("📱 Attempting Firestore write (\(attempt)/3)")
                try await db.collection("videos").addDocument(data: videoData)
                print("✅ Document added to Firestore")
                return

            } catch {
                print("❌ Attempt \(attempt) failed: \(error.localizedDescription)")
                if attempt == 3 {
                    throw error
                }
                try await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
            }
        }
    }

    func generateThumbnail(from url: URL) async throws -> UIImage {
        let asset = AVURLAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true

        return try await withCheckedThrowingContinuation { continuation in
            imageGenerator.generateCGImageAsynchronously(for: .zero) { cgImage, _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let cgImage = cgImage else {
                    continuation.resume(throwing: NSError(domain: "ThumbnailError", code: -1))
                    return
                }

                let thumbnail = UIImage(cgImage: cgImage)
                continuation.resume(returning: thumbnail)
            }
        }
    }

    func reset() {
        selectedVideoURL = nil
        thumbnailImage = nil
        caption = ""
        uploadComplete = false
        uploadProgress = 0
        errorMessage = nil
        isUploading = false
    }

    @MainActor
    func setSelectedVideo(url: URL) {
        print("📱 Setting selected video URL: \(url)")
        selectedVideoURL = url

        // Generate thumbnail asynchronously
        Task {
            do {
                print("📱 Generating thumbnail")
                thumbnailImage = try await generateThumbnail(from: url)
                print("✅ Thumbnail generated")
            } catch {
                print("❌ Thumbnail generation failed: \(error.localizedDescription)")
                errorMessage = "Could not generate thumbnail: \(error.localizedDescription)"
            }
        }
    }

    func cancelUpload() {
        print("📱 Cancel button pressed")
        if let task = currentUploadTask {
            print("📱 Found upload task to cancel")
            task.cancel()
            print("📱 Called cancel on upload task")

            Task { @MainActor in
                isUploading = false
                uploadProgress = 0
                errorMessage = "Upload canceled"
                print("📱 Reset UI after cancel")
            }
        } else {
            print("❌ No upload task found to cancel")
        }
    }
}
