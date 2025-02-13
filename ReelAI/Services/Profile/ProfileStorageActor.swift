import Foundation
import FirebaseStorage
import os

/// An actor responsible for managing profile photo storage operations.
/// This actor ensures thread-safe access to Firebase Storage for profile-related content.
actor ProfileStorageActor {
    // MARK: - Types

    enum StorageError: Error {
        case uploadFailed(Error)
        case invalidData
        case networkError
        case verificationFailed

        var localizedDescription: String {
            switch self {
            case .uploadFailed(let error):
                return "Upload failed: \(error.localizedDescription)"
            case .invalidData:
                return "Invalid image data"
            case .networkError:
                return "Network error during storage operation"
            case .verificationFailed:
                return "Failed to verify uploaded file"
            }
        }
    }

    // MARK: - Properties

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ReelAI",
        category: "ProfileStorage"
    )

    private let storage = Storage.storage().reference()
    private let maxRetries = 3
    private let baseRetryDelay: TimeInterval = 1.0

    // MARK: - Initialization

    private static let instance = ProfileStorageActor()

    static var shared: ProfileStorageActor {
        get async {
            await instance
        }
    }

    private init() {
        logger.debug("🔨 ProfileStorageActor initialized")
    }

    // MARK: - Storage Operations

    /// Uploads a profile photo to Firebase Storage
    /// - Parameters:
    ///   - imageData: The JPEG image data to upload
    ///   - userId: The ID of the user whose photo is being uploaded
    /// - Returns: The download URL of the uploaded photo
    func uploadProfilePhoto(_ imageData: Data, userId: String) async throws -> URL {
        logger.debug("📤 Starting profile photo upload for user: \(userId)")

        // Create storage reference
        let photoRef = storage.child("profile_photos").child(userId).child("profile.jpg")

        // Create metadata
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        metadata.customMetadata = [
            "userId": userId,
            "uploadTimestamp": "\(Date().timeIntervalSince1970)"
        ]

        // Attempt upload with retries
        var lastError: Error?
        for attempt in 0..<maxRetries {
            do {
                logger.debug("📤 Upload attempt \(attempt + 1) for user: \(userId)")

                // Try to delete any existing photo first
                try? await photoRef.delete()

                // Upload the new photo
                _ = try await photoRef.putDataAsync(imageData, metadata: metadata)

                // Get and verify the download URL
                let downloadURL = try await photoRef.downloadURL()

                // Verify the upload
                let verifyMetadata = try await photoRef.getMetadata()
                guard verifyMetadata.size > 0 else {
                    throw StorageError.verificationFailed
                }

                logger.debug("✅ Profile photo uploaded successfully: \(downloadURL)")
                return downloadURL

            } catch {
                lastError = error

                if !shouldRetry(error: error) {
                    break
                }

                let delay = exponentialBackoff(attempt: attempt)
                logger.debug("⏳ Retrying upload in \(delay) seconds")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        logger.error("❌ Profile photo upload failed after \(maxRetries) attempts")
        throw StorageError.uploadFailed(lastError ?? StorageError.networkError)
    }

    // MARK: - Helper Methods

    private func exponentialBackoff(attempt: Int) -> TimeInterval {
        return baseRetryDelay * pow(2.0, Double(attempt))
    }

    private func shouldRetry(error: Error) -> Bool {
        let nsError = error as NSError

        // Common network-related error codes to retry
        let retryErrorCodes = [
            NSURLErrorNetworkConnectionLost,
            NSURLErrorNotConnectedToInternet,
            NSURLErrorTimedOut,
            NSURLErrorInternationalRoamingOff,
            NSURLErrorDataNotAllowed,
            NSURLErrorCannotConnectToHost,
            NSURLErrorCannotFindHost,
            NSURLErrorDNSLookupFailed
        ]

        return retryErrorCodes.contains(nsError.code) ||
               nsError.domain == NSURLErrorDomain ||
               nsError.domain == "FIRStorageErrorDomain"
    }
}
