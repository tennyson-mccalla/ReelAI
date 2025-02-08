// Core view model with main upload flow and state management
// ~100 lines

import SwiftUI
import FirebaseAuth
import FirebaseStorage

@MainActor
final class VideoUploadViewModel: ObservableObject {
    @Published private(set) var uploadProgress: Double = 0
    @Published private(set) var isUploading = false
    @Published private(set) var errorMessage: String?
    @Published var selectedVideoURL: URL?
    @Published var thumbnailImage: UIImage?
    @Published var caption: String = ""
    @Published private(set) var uploadComplete = false
    @Published var lastUploadedVideoURL: URL?
    @Published var selectedQuality: VideoProcessor.Quality = .medium
    @Published var shouldNavigateToProfile = false

    private let processor: VideoProcessor
    private let uploadManager: UploadManager
    private let progressTracker: UploadProgress

    init(processor: VideoProcessor = .init(),
         uploadManager: UploadManager = .init(),
         progressTracker: UploadProgress = .init()) {
        self.processor = processor
        self.uploadManager = uploadManager
        self.progressTracker = progressTracker
        
        // Observe upload progress
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleProgressUpdate),
            name: .uploadProgressUpdated,
            object: nil
        )
    }

    @objc private func handleProgressUpdate(_ notification: Notification) {
        if let progress = notification.userInfo?["progress"] as? Double {
            DispatchQueue.main.async {
                self.uploadProgress = progress
            }
        }
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

        Task {
            do {
                try await processAndUploadVideo(from: videoURL)
            } catch {
                await handleUploadError(error)
            }
        }
    }

    private func processAndUploadVideo(from videoURL: URL) async throws {
        // 1. Compress video
        print("📱 Starting video compression")
        let compressedVideoURL = try await processor.compressVideo(at: videoURL, quality: selectedQuality)
        defer { try? FileManager.default.removeItem(at: compressedVideoURL) }

        // 2. Generate thumbnail and metadata
        let baseVideoName = UUID().uuidString
        let videoName = baseVideoName + ".mp4"
        let thumbnailName = baseVideoName + ".jpg"
        print("📱 Starting video upload: \(videoName)")

        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "UploadError", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }

        // Generate and upload thumbnail
        guard let thumbnail = thumbnailImage,
              let thumbnailData = thumbnail.jpegData(compressionQuality: 0.8) else {
            throw NSError(domain: "UploadError", code: -2, userInfo: [NSLocalizedDescriptionKey: "Could not prepare thumbnail"])
        }

        let thumbnailRef = Storage.storage().reference().child("thumbnails/\(thumbnailName)")
        let thumbnailMetadata = StorageMetadata()
        thumbnailMetadata.contentType = "image/jpeg"
        _ = try await thumbnailRef.putDataAsync(thumbnailData, metadata: thumbnailMetadata)
        let thumbnailURL = try await thumbnailRef.downloadURL()

        let metadata = VideoMetadata(
            userId: userId,
            videoName: videoName,
            caption: caption,
            timestamp: Date(),
            thumbnailURL: thumbnailURL.absoluteString
        )

        // 3. Upload video
        let result = try await uploadManager.uploadVideo(compressedVideoURL, metadata: metadata)
        lastUploadedVideoURL = result.videoURL

        // 4. Save metadata
        try await uploadManager.saveMetadata(metadata)

        // 5. Update UI
        updateUIAfterSuccess()
    }

    private func handleUploadError(_ error: Error) async {
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

    private func updateUIAfterSuccess() {
        uploadComplete = true
        isUploading = false
        selectedVideoURL = nil
        thumbnailImage = nil
        caption = ""
        errorMessage = "✅ Upload complete!"
        shouldNavigateToProfile = true
    }

    func setError(_ message: String) {
        errorMessage = message
    }

    func setSelectedVideo(url: URL) {
        print("📱 ViewModel: Setting selected video URL: \(url.path)")
        selectedVideoURL = url
        Task {
            do {
                print("📱 ViewModel: Generating thumbnail...")
                thumbnailImage = try await processor.generateThumbnail(from: url)
                print("📱 ViewModel: Thumbnail generated successfully")
            } catch {
                print("❌ ViewModel: Thumbnail generation failed: \(error.localizedDescription)")
                setError("Could not generate thumbnail: \(error.localizedDescription)")
            }
        }
    }

    func cancelUpload() {
        print("📱 Cancel button pressed")
        uploadManager.cancelUpload()
        isUploading = false
        uploadProgress = 0
        errorMessage = "Upload canceled"
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
}
