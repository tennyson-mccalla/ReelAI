import Foundation
import FirebaseStorage
import FirebaseAuth

final class FirebaseStorageManager: StorageManager {
    private let storage = Storage.storage().reference()

    enum StorageError: Error {
        case notAuthenticated
        case uploadFailed(Error)
    }

    func uploadProfilePhoto(_ data: Data, userId: String) async throws -> URL {
        guard let currentUser = Auth.auth().currentUser else {
            throw StorageError.notAuthenticated
        }

        // Verify user is uploading their own photo
        guard currentUser.uid == userId else {
            throw StorageError.notAuthenticated
        }

        // Changed path to match storage rules structure
        let filename = "\(UUID().uuidString).jpg"
        let photoRef = storage.child("profile_photos/\(userId)/\(filename)")

        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        do {
            print("📤 Starting upload to: \(photoRef.fullPath)")
            _ = try await photoRef.putDataAsync(data, metadata: metadata)
            print("✅ Upload successful")
            let url = try await photoRef.downloadURL()
            print("📍 Download URL: \(url)")
            return url
        } catch {
            print("❌ Upload failed with error: \(error)")
            print("- Error description: \(error.localizedDescription)")
            throw StorageError.uploadFailed(error)
        }
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
