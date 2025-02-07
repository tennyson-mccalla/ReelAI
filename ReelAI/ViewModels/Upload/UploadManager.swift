// Handles the actual upload process, chunking, retry logic
// ~100 lines

import FirebaseStorage
import FirebaseDatabase

final class UploadManager {
    private let storage: StorageReference
    private let database: DatabaseReference
    private var currentUploadTask: StorageUploadTask?

    init(storage: StorageReference = Storage.storage().reference(),
         database: DatabaseReference = Database.database().reference()) {
        self.storage = storage
        self.database = database
    }

    func uploadVideo(_ url: URL, metadata: VideoMetadata) async throws -> VideoUploadResult {
        let videoRef = storage.child("videos/\(metadata.videoName)")
        let storageMetadata = StorageMetadata()
        storageMetadata.contentType = "video/mp4"

        return try await withCheckedThrowingContinuation { continuation in
            let uploadTask = videoRef.putFile(from: url, metadata: storageMetadata) { _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                Task {
                    do {
                        let downloadURL = try await videoRef.downloadURL()
                        continuation.resume(returning: VideoUploadResult(
                            videoURL: downloadURL,
                            thumbnailURL: nil
                        ))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }

            self.currentUploadTask = uploadTask
        }
    }

    func saveMetadata(_ metadata: VideoMetadata) async throws {
        print("🔄 Saving metadata with userId: \(metadata.userId)")
        let videoData: [String: Any] = [
            "userId": metadata.userId,
            "videoName": metadata.videoName,
            "timestamp": ServerValue.timestamp(),
            "caption": metadata.caption.trimmingCharacters(in: .whitespacesAndNewlines),
            "likes": 0,
            "comments": 0
        ]
        print("�� Video data to save: \(videoData)")

        try await database.child("videos").childByAutoId().setValue(videoData)
        print("✅ Metadata saved successfully")
    }

    func cancelUpload() {
        currentUploadTask?.cancel()
        currentUploadTask = nil
    }
}
