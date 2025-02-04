import Foundation
import FirebaseStorage
import AVFoundation
import UIKit
import FirebaseFirestore
import FirebaseAuth

class VideoUploadViewModel: ObservableObject {
    @Published var uploadProgress: Double = 0
    @Published var isUploading = false
    @Published var errorMessage: String?
    @Published var selectedVideoURL: URL?
    @Published var thumbnailImage: UIImage?
    @Published var caption: String = ""
    @Published var uploadComplete = false

    private let storage = Storage.storage().reference()
    private let db = Firestore.firestore()
    private var thumbnailURL: String?

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

        // Create a task group to handle uploads sequentially
        Task {
            do {
                let videoName = UUID().uuidString + ".mp4"
                print("📱 Starting video upload: \(videoName)")

                // Upload video first
                try await uploadVideoFile(videoURL, name: videoName)
                print("✅ Video upload complete")

                // Then upload thumbnail if available
                if let thumbnail = thumbnailImage {
                    print("📱 Starting thumbnail upload")
                    try await uploadThumbnail(thumbnail, for: videoName)
                    print("✅ Thumbnail upload complete")
                }

                // Finally save metadata
                try await saveVideoMetadata(videoName: videoName)

                await MainActor.run {
                    uploadComplete = true
                    isUploading = false
                }
            } catch {
                await MainActor.run {
                    print("❌ Upload error: \(error.localizedDescription)")
                    errorMessage = "Upload failed: \(error.localizedDescription)"
                    isUploading = false
                }
            }
        }
    }

    private func uploadVideoFile(_ url: URL, name: String) async throws {
        let videoRef = storage.child("videos/\(name)")
        let metadata = StorageMetadata()
        metadata.contentType = "video/mp4"

        return try await withCheckedThrowingContinuation { continuation in
            let uploadTask = videoRef.putFile(from: url, metadata: metadata) { _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: ())
            }

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
        guard let user = Auth.auth().currentUser else {
            throw NSError(domain: "UploadError", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }

        let videoData: [String: Any] = [
            "userId": user.uid,
            "videoName": videoName,
            "caption": caption,
            "thumbnailURL": thumbnailURL ?? "",
            "timestamp": FieldValue.serverTimestamp(),
            "likes": 0,
            "comments": 0
        ]

        do {
            try await db.collection("videos").addDocument(data: videoData)
        } catch {
            print("❌ Error saving metadata: \(error.localizedDescription)")
            throw error
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
}
