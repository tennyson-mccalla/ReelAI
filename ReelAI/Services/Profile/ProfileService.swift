import Foundation
import os
import FirebaseAuth

/// An actor responsible for coordinating all profile-related operations.
/// This includes profile updates, photo management, and data synchronization.
actor ProfileService {
    // MARK: - Types

    enum ProfileError: Error {
        case notAuthenticated
        case invalidUser
        case storageError(Error)
        case databaseError(Error)
        case invalidData

        var localizedDescription: String {
            switch self {
            case .notAuthenticated:
                return "User is not authenticated"
            case .invalidUser:
                return "Invalid user ID or permissions"
            case .storageError(let error):
                return "Storage error: \(error.localizedDescription)"
            case .databaseError(let error):
                return "Database error: \(error.localizedDescription)"
            case .invalidData:
                return "Invalid profile data"
            }
        }
    }

    // MARK: - Properties

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ReelAI",
        category: "ProfileService"
    )

    /// Shared instance of the ProfileService
    private static let instance = ProfileService()

    /// Thread-safe access to the shared instance
    static var shared: ProfileService {
        get async {
            await instance
        }
    }

    // MARK: - Initialization

    private init() {
        logger.debug("🔨 ProfileService initialized")
    }

    // MARK: - Profile Operations

    /// Updates the user's profile photo
    /// - Parameters:
    ///   - imageData: The JPEG image data to upload
    ///   - userId: The ID of the user whose photo is being updated
    /// - Returns: The URL of the uploaded photo
    func updateProfilePhoto(_ imageData: Data, for userId: String) async throws -> URL {
        logger.debug("📸 Starting profile photo update for user: \(userId)")

        // Verify authentication
        guard let currentUser = Auth.auth().currentUser else {
            logger.error("❌ No authenticated user found")
            throw ProfileError.notAuthenticated
        }

        guard currentUser.uid == userId else {
            logger.error("❌ User does not have permission to update this profile")
            throw ProfileError.invalidUser
        }

        do {
            // 1. Upload photo to storage
            let storage = await ProfileStorageActor.shared
            let photoURL = try await storage.uploadProfilePhoto(imageData, userId: userId)

            // 2. Update database with new photo URL
            let database = await ProfileDatabaseActor.shared
            try await database.updateProfilePhotoURL(photoURL, for: userId)

            // 3. Notify UI of update
            await MainActor.run {
                NotificationCenter.default.post(
                    name: Notification.Name("ProfilePhotoUpdated"),
                    object: photoURL
                )
            }

            logger.debug("✅ Profile photo update completed successfully")
            return photoURL

        } catch let error as ProfileStorageActor.StorageError {
            logger.error("❌ Storage error during profile photo update: \(error.localizedDescription)")
            throw ProfileError.storageError(error)

        } catch let error as ProfileDatabaseActor.DatabaseError {
            logger.error("❌ Database error during profile photo update: \(error.localizedDescription)")
            throw ProfileError.databaseError(error)

        } catch {
            logger.error("❌ Unexpected error during profile photo update: \(error.localizedDescription)")
            throw error
        }
    }

    /// Fetches the current user's profile
    /// - Parameter userId: The ID of the user whose profile to fetch
    /// - Returns: The user's profile data
    func fetchProfile(userId: String) async throws -> UserProfile {
        logger.debug("📥 Fetching profile for user: \(userId)")

        // Verify authentication
        guard Auth.auth().currentUser != nil else {
            logger.error("❌ No authenticated user found")
            throw ProfileError.notAuthenticated
        }

        do {
            let database = await ProfileDatabaseActor.shared
            return try await database.fetchProfile(userId: userId)
        } catch let error as ProfileDatabaseActor.DatabaseError {
            logger.error("❌ Database error during profile fetch: \(error.localizedDescription)")
            throw ProfileError.databaseError(error)
        } catch {
            logger.error("❌ Unexpected error during profile fetch: \(error.localizedDescription)")
            throw error
        }
    }

    /// Updates a user's profile
    /// - Parameter profile: The profile data to update
    func updateProfile(_ profile: UserProfile) async throws {
        logger.debug("📝 Updating profile for user: \(profile.id)")

        // Verify authentication
        guard let currentUser = Auth.auth().currentUser else {
            logger.error("❌ No authenticated user found")
            throw ProfileError.notAuthenticated
        }

        guard currentUser.uid == profile.id else {
            logger.error("❌ User does not have permission to update this profile")
            throw ProfileError.invalidUser
        }

        do {
            let database = await ProfileDatabaseActor.shared
            try await database.updateProfile(profile)
            logger.debug("✅ Profile update completed successfully")
        } catch let error as ProfileDatabaseActor.DatabaseError {
            logger.error("❌ Database error during profile update: \(error.localizedDescription)")
            throw ProfileError.databaseError(error)
        } catch {
            logger.error("❌ Unexpected error during profile update: \(error.localizedDescription)")
            throw error
        }
    }
}
