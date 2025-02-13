import Foundation
import FirebaseDatabase
import os

/// Namespace for database-related components
enum ReelDB {
    protocol Manager: Actor {
        // MARK: - Required Properties
        nonisolated var databaseRef: DatabaseReference { get }
        nonisolated var logger: Logger { get }

        // MARK: - Required Methods
        nonisolated func configure() async
        nonisolated func setupDatabaseConnection() async
        nonisolated func handleError(_ error: Error, operation: String)

        // MARK: - Video Operations
        func softDeleteVideo(_ videoId: String) async throws
        func restoreVideo(_ videoId: String) async throws
        func updateVideoPrivacy(_ videoId: String, privacyLevel: Video.PrivacyLevel) async throws
        func updateVideoMetadata(_ videoId: String, caption: String) async throws
        func updateVideo(_ video: Video) async throws
        func fetchVideos(limit: Int, after key: String?) async throws -> [Video]
        func deleteVideo(id: String) async throws

        // MARK: - Profile Operations
        func updateProfile(_ profile: UserProfile) async throws
        func fetchProfile(userId: String) async throws -> UserProfile
        func updateProfilePhoto(userId: String, photoURL: URL) async throws
    }
}

/// Default implementations for DatabaseManager
extension ReelDB.Manager {
    nonisolated func configure() async {
        // Configure Firebase persistence with a size limit
        Database.database().persistenceCacheSizeBytes = 100 * 1024 * 1024 // 100MB limit
        Database.database().isPersistenceEnabled = true

        // Keep the database reference synchronized
        databaseRef.keepSynced(true)

        // Setup connection handling
        await setupDatabaseConnection()
    }

    nonisolated func handleError(_ error: Error, operation: String) {
        if let dbError = error as? ReelDB.Error {
            switch dbError {
            case .invalidData:
                logger.error("❌ Invalid data in \(operation): \(error.localizedDescription)")
            case .notAuthenticated:
                logger.error("❌ Authentication required for \(operation)")
            case .offline:
                logger.error("❌ Device is offline during \(operation)")
            case .permissionDenied:
                logger.error("❌ Permission denied for \(operation)")
            case .invalidPath:
                logger.error("❌ Invalid database path in \(operation)")
            case .networkError(let underlying):
                logger.error("❌ Network error in \(operation): \(underlying.localizedDescription)")
            case .encodingError(let underlying):
                logger.error("❌ Encoding error in \(operation): \(underlying.localizedDescription)")
            case .decodingError(let underlying):
                logger.error("❌ Decoding error in \(operation): \(underlying.localizedDescription)")
            }
        } else {
            logger.error("❌ Error in \(operation): \(error.localizedDescription)")
        }
    }
}
