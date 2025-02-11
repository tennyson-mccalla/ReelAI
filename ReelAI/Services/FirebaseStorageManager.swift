import Foundation
import FirebaseStorage
import FirebaseAuth

@MainActor
final class FirebaseStorageManager: StorageManager {
    private let storage = Storage.storage().reference()
    private let maxRetries = 3
    private let baseRetryDelay: TimeInterval = 1.0

    enum StorageError: Error, LocalizedError {
        case notAuthenticated
        case uploadFailed(Error)
        case invalidUser
        case networkError
        case uploadCancelled

        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "User is not authenticated"
            case .uploadFailed(let error):
                return "Upload failed: \(error.localizedDescription)"
            case .invalidUser:
                return "Invalid user ID"
            case .networkError:
                return "Network connection failed"
            case .uploadCancelled:
                return "Upload was cancelled"
            }
        }
    }

    private func exponentialBackoff(attempt: Int) -> TimeInterval {
        return baseRetryDelay * pow(2.0, Double(attempt))
    }

    private func shouldRetry(error: Error) -> Bool {
        let nsError = error as NSError

        // Common network-related error codes to retry
        let retryErrorCodes = [
            -1200,  // SSL error
            -1009,  // No internet connection
            -1004,  // Could not connect to server
            -1001   // Timeout
        ]

        return retryErrorCodes.contains(nsError.code) ||
               nsError.domain == NSURLErrorDomain ||
               nsError.domain == "kCFErrorDomainCFNetwork"
    }

    func uploadProfilePhoto(_ data: Data, userId: String) async throws -> URL {
        guard let currentUser = Auth.auth().currentUser else {
            throw StorageError.notAuthenticated
        }

        // Verify user is uploading their own photo
        guard currentUser.uid == userId else {
            throw StorageError.notAuthenticated
        }

        // Detailed data validation
        print("📊 Image data details:")
        print("- Size: \(data.count) bytes")
        print("- Is empty: \(data.isEmpty)")

        guard !data.isEmpty else {
            print("❌ Image data is empty")
            throw StorageError.uploadFailed(NSError(domain: "PhotoUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Empty image data"]))
        }

        // Consistent filename for profile photo
        let filename = "profile.jpg"
        let photoRef = storage.child("profile_photos/\(userId)/\(filename)")

        var lastError: Error?
        for attempt in 0..<maxRetries {
            do {
                let metadata = StorageMetadata()
                metadata.contentType = "image/jpeg"

                print("📤 Upload attempt \(attempt + 1): \(photoRef.fullPath)")

                _ = try await photoRef.putDataAsync(data, metadata: metadata)
                let url = try await photoRef.downloadURL()

                print("✅ Upload successful: \(url)")
                print("📍 Download URL: \(url)")
                print("📍 URL String: \(url.absoluteString)")

                return url
            } catch {
                lastError = error

                if !shouldRetry(error: error) {
                    break
                }

                print("⏳ Retrying upload in \(exponentialBackoff(attempt: attempt)) seconds")
                try? await Task.sleep(nanoseconds: UInt64(exponentialBackoff(attempt: attempt) * 1_000_000_000))
            }
        }

        // Log final error details
        if let error = lastError {
            print("❌ Upload failed after \(maxRetries) attempts")
            print("- Error type: \(type(of: error))")
            print("- Error description: \(error.localizedDescription)")

            let nsError = error as NSError
            print("- NS Error domain: \(nsError.domain)")
            print("- NS Error code: \(nsError.code)")
            print("- NS Error userInfo: \(nsError.userInfo)")
        }

        throw lastError ?? StorageError.uploadFailed(StorageError.networkError)
    }

    private func deleteExistingProfilePhoto(for userId: String) async throws {
        let profilePhotoRef = storage.child("profile_photos/\(userId)/profile.jpg")

        do {
            try await profilePhotoRef.delete()
            print("✅ Existing profile photo deleted successfully")
        } catch let error as NSError {
            // If the error is that the file doesn't exist, we can ignore it
            if error.domain == "FIRStorageErrorDomain" && error.code == -100 {
                print("ℹ️ No existing profile photo found")
                return
            }
            throw error
        }
    }

    func uploadVideo(_ url: URL, name: String) async throws -> URL {
        let videoRef = storage.child("videos/\(name)")
        let metadata = StorageMetadata()
        metadata.contentType = "video/mp4"

        var lastError: Error?
        for attempt in 0..<maxRetries {
            do {
                print("📤 Video upload attempt \(attempt + 1): \(name)")
                _ = try await videoRef.putFileAsync(from: url, metadata: metadata)
                let downloadURL = try await videoRef.downloadURL()

                print("✅ Video upload successful: \(downloadURL)")
                return downloadURL
            } catch {
                lastError = error

                if !shouldRetry(error: error) {
                    break
                }

                print("⏳ Retrying video upload in \(exponentialBackoff(attempt: attempt)) seconds")
                try? await Task.sleep(nanoseconds: UInt64(exponentialBackoff(attempt: attempt) * 1_000_000_000))
            }
        }

        // Log final error details
        if let error = lastError {
            print("❌ Video upload failed after \(maxRetries) attempts")
            print("- Error type: \(type(of: error))")
            print("- Error description: \(error.localizedDescription)")
        }

        throw lastError ?? StorageError.uploadFailed(StorageError.networkError)
    }

    func uploadThumbnail(_ data: Data, for videoId: String) async throws -> URL {
        let thumbRef = storage.child("thumbnails/\(videoId).jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        var lastError: Error?
        for attempt in 0..<maxRetries {
            do {
                print("📤 Thumbnail upload attempt \(attempt + 1): \(videoId)")
                _ = try await thumbRef.putDataAsync(data, metadata: metadata)
                let downloadURL = try await thumbRef.downloadURL()

                print("✅ Thumbnail upload successful: \(downloadURL)")
                return downloadURL
            } catch {
                lastError = error

                if !shouldRetry(error: error) {
                    break
                }

                print("⏳ Retrying thumbnail upload in \(exponentialBackoff(attempt: attempt)) seconds")
                try? await Task.sleep(nanoseconds: UInt64(exponentialBackoff(attempt: attempt) * 1_000_000_000))
            }
        }

        // Log final error details
        if let error = lastError {
            print("❌ Thumbnail upload failed after \(maxRetries) attempts")
            print("- Error type: \(type(of: error))")
            print("- Error description: \(error.localizedDescription)")
        }

        throw lastError ?? StorageError.uploadFailed(StorageError.networkError)
    }

    func getDownloadURL(for path: String) async throws -> URL {
        try await storage.child(path).downloadURL()
    }

    func deleteFile(at path: String) async throws {
        try await storage.child(path).delete()
    }
}
