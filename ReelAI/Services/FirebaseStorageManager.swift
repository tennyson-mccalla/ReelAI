import Foundation
import FirebaseStorage

final class FirebaseStorageManager: StorageManager {
    private let storage = Storage.storage().reference()

    func uploadProfilePhoto(_ data: Data, userId: String) async throws -> URL {
        let photoRef = storage.child("profile_photos/\(userId).jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        _ = try await photoRef.putDataAsync(data, metadata: metadata)
        return try await photoRef.downloadURL()
    }

    func uploadVideo(_ url: URL, name: String) async throws -> URL {
        let videoRef = storage.child("videos/\(name)")
        let metadata = StorageMetadata()
        metadata.contentType = "video/mp4"

        _ = try await videoRef.putFileAsync(from: url, metadata: metadata)
        return try await videoRef.downloadURL()
    }

    func uploadThumbnail(_ data: Data, for videoId: String) async throws -> URL {
        let thumbRef = storage.child("thumbnails/\(videoId).jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        _ = try await thumbRef.putDataAsync(data, metadata: metadata)
        return try await thumbRef.downloadURL()
    }

    func getDownloadURL(for path: String) async throws -> URL {
        try await storage.child(path).downloadURL()
    }

    func deleteFile(at path: String) async throws {
        try await storage.child(path).delete()
    }
}
