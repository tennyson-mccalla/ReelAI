import Foundation
import FirebaseStorage
import FirebaseAuth
import os

final class FirebaseStorageManager: StorageManager {
    private let storage = Storage.storage().reference()
    private let maxRetries = 3
    private let baseRetryDelay: TimeInterval = 1.0
    private var uploadTasks: [URL: StorageUploadTask] = [:]
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReelAI", category: "FirebaseStorageManager")

    enum StorageError: Error, LocalizedError {
        case notAuthenticated
        case uploadFailed(Error)
        case invalidUser
        case networkError
        case uploadCancelled
        case invalidImageData
        case imageTooLarge
        case invalidImageFormat

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
            case .invalidImageData:
                return "Invalid image data"
            case .imageTooLarge:
                return "Image size exceeds 5MB limit"
            case .invalidImageFormat:
                return "Invalid image format. Only JPEG images are supported"
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
        logger.debug("📤 Starting profile photo upload for user: \(userId)")

        // Verify user is authenticated
        guard let currentUser = Auth.auth().currentUser else {
            logger.error("❌ No authenticated user found")
            throw StorageError.notAuthenticated
        }

        guard currentUser.uid == userId else {
            logger.error("❌ User does not have permission to upload this photo")
            throw StorageError.notAuthenticated
        }

        // Create reference with proper path structure and file extension
        let photoRef = storage.child("profile_photos").child(userId).child("profile.jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        metadata.customMetadata = [
            "userId": userId,
            "uploadTimestamp": "\(Date().timeIntervalSince1970)"
        ]

        do {
            // First try to delete any existing photo
            try? await photoRef.delete()

            // Upload the new photo with metadata
            let _ = try await photoRef.putDataAsync(data, metadata: metadata)

            // Get the download URL
            let downloadURL = try await photoRef.downloadURL()
            logger.debug("✅ Profile photo uploaded successfully: \(downloadURL)")

            // Verify the upload
            let verifyMetadata = try await photoRef.getMetadata()
            guard verifyMetadata.size > 0 else {
                logger.error("❌ Uploaded file size verification failed")
                throw StorageError.uploadFailed(NSError(domain: "FirebaseStorage", code: -1, userInfo: [NSLocalizedDescriptionKey: "Upload verification failed"]))
            }

            return downloadURL
        } catch {
            logger.error("❌ Failed to upload profile photo: \(error.localizedDescription)")
            throw StorageError.uploadFailed(error)
        }
    }

    private func deleteExistingProfilePhoto(for userId: String) async throws {
        let profilePhotoRef = storage.child("profile_photos/\(userId)/profile.jpg")

        do {
            try await profilePhotoRef.delete()
            logger.debug("✅ Existing profile photo deleted")
        } catch let error as NSError {
            // If the error is that the file doesn't exist, we can ignore it
            if error.domain == "FIRStorageErrorDomain" && error.code == -100 {
                logger.debug("ℹ️ No existing profile photo to delete")
                return
            }
            throw error
        }
    }

    func uploadVideo(_ url: URL, name: String, progressHandler: @escaping (Double) -> Void) async throws -> URL {
        let videoRef = storage.child("videos/\(name)")
        let metadata = StorageMetadata()
        metadata.contentType = "video/mp4"

        return try await withCheckedThrowingContinuation { continuation in
            let uploadTask = videoRef.putFile(from: url, metadata: metadata)

            uploadTask.observe(.progress) { snapshot in
                if let progress = snapshot.progress {
                    let percentComplete = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
                    progressHandler(percentComplete)
                }
            }

            uploadTask.observe(.success) { _ in
                Task {
                    do {
                        let downloadURL = try await videoRef.downloadURL()
                        continuation.resume(returning: downloadURL)
                    } catch {
                        continuation.resume(throwing: StorageError.uploadFailed(error))
                    }
                }
            }

            uploadTask.observe(.failure) { snapshot in
                if let error = snapshot.error as? NSError {
                    continuation.resume(throwing: StorageError.uploadFailed(error))
                }
            }

            // Store the upload task for potential cancellation
            uploadTasks[url] = uploadTask
        }
    }

    func cancelUpload(for url: URL) {
        uploadTasks[url]?.cancel()
        uploadTasks.removeValue(forKey: url)
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
