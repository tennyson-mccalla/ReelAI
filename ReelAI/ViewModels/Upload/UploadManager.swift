// Handles the actual upload process, chunking, retry logic
// ~100 lines

import FirebaseStorage
import FirebaseDatabase

extension Notification.Name {
    static let uploadProgressUpdated = Notification.Name("uploadProgressUpdated")
}

@MainActor
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

            uploadTask.observe(.progress) { snapshot in
                if let progress = snapshot.progress {
                    NotificationCenter.default.post(
                        name: .uploadProgressUpdated,
                        object: nil,
                        userInfo: ["progress": progress.fractionCompleted]
                    )
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

    func uploadMultipleVideos(_ urls: [URL], metadatas: [VideoMetadata]) async throws -> [VideoUploadResult] {
        print("🚀 Starting multiple video uploads: \(urls.count) videos")

        var uploadResults: [VideoUploadResult] = []

        // Use structured concurrency to upload videos in parallel
        try await withThrowingTaskGroup(of: VideoUploadResult.self) { group in
            for (index, url) in urls.enumerated() {
                group.addTask {
                    let metadata = metadatas[index]
                    return try await self.uploadVideo(url, metadata: metadata)
                }
            }

            // Collect results as they complete
            for try await result in group {
                uploadResults.append(result)

                // Notify progress
                NotificationCenter.default.post(
                    name: .uploadProgressUpdated,
                    object: nil,
                    userInfo: ["progress": Double(uploadResults.count) / Double(urls.count)]
                )
            }
        }

        print("✅ Completed multiple video uploads: \(uploadResults.count) videos")
        return uploadResults
    }

    func saveMultipleMetadata(_ metadatas: [VideoMetadata]) async throws {
        print("🔄 Saving metadata for multiple videos: \(metadatas.count)")

        try await withThrowingTaskGroup(of: Void.self) { group in
            for metadata in metadatas {
                group.addTask {
                    try await self.saveMetadata(metadata)
                }
            }

            // Wait for all metadata saves to complete
            try await group.waitForAll()
        }

        print("✅ Saved metadata for all videos")
    }

    func cancelUpload() {
        currentUploadTask?.cancel()
        currentUploadTask = nil
    }
}
