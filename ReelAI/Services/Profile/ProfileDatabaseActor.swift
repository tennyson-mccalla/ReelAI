import Foundation
import FirebaseDatabase
import os

/// An actor responsible for managing profile data in the Firebase Realtime Database.
/// This actor ensures thread-safe access to profile-related database operations.
actor ProfileDatabaseActor {
    // MARK: - Types

    enum DatabaseError: Error {
        case invalidData
        case networkError(Error)
        case permissionDenied
        case notFound
        case serializationError(Error)

        var localizedDescription: String {
            switch self {
            case .invalidData:
                return "Invalid profile data structure"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .permissionDenied:
                return "Permission denied for database operation"
            case .notFound:
                return "Profile not found"
            case .serializationError(let error):
                return "Data serialization error: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Properties

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ReelAI",
        category: "ProfileDatabase"
    )

    private let database: DatabaseReference

    // MARK: - Initialization

    private static let instance = ProfileDatabaseActor()

    static var shared: ProfileDatabaseActor {
        get async {
            await instance
        }
    }

    private init() {
        self.database = Database.database().reference()
        logger.debug("🔨 ProfileDatabaseActor initialized")

        // Configure Firebase persistence
        Database.database().persistenceCacheSizeBytes = 100 * 1024 * 1024 // 100MB
        Database.database().isPersistenceEnabled = true
    }

    // MARK: - Database Operations

    /// Updates the profile photo URL in the database
    /// - Parameters:
    ///   - photoURL: The URL of the uploaded photo
    ///   - userId: The ID of the user whose profile is being updated
    func updateProfilePhotoURL(_ photoURL: URL, for userId: String) async throws {
        logger.debug("📝 Updating profile photo URL for user: \(userId)")

        let userRef = database.child("users").child(userId)

        // First verify the profile exists
        let snapshot = try await userRef.getData()
        guard snapshot.exists() else {
            logger.error("❌ User profile not found")
            throw DatabaseError.notFound
        }

        // Create update data with server timestamp
        let updateData: [String: Any] = [
            "photoURL": photoURL.absoluteString,
            "lastUpdated": ServerValue.timestamp()
        ]

        do {
            try await userRef.updateChildValues(updateData)
            logger.debug("✅ Profile photo URL updated successfully")

            // Verify the update
            let verifySnapshot = try await userRef.getData()
            guard let userData = verifySnapshot.value as? [String: Any],
                  let updatedPhotoURL = userData["photoURL"] as? String,
                  updatedPhotoURL == photoURL.absoluteString else {
                logger.error("❌ Profile photo URL verification failed")
                throw DatabaseError.invalidData
            }

            logger.debug("✅ Profile photo URL verified in database")
        } catch {
            logger.error("❌ Failed to update profile photo URL: \(error.localizedDescription)")
            throw DatabaseError.networkError(error)
        }
    }

    /// Fetches a user's profile from the database
    /// - Parameter userId: The ID of the user whose profile to fetch
    /// - Returns: The user's profile data
    func fetchProfile(userId: String) async throws -> UserProfile {
        logger.debug("📥 Fetching profile for user: \(userId)")

        let snapshot = try await database.child("users").child(userId).getData()

        guard var data = snapshot.value as? [String: Any] else {
            logger.error("❌ Invalid profile data structure")
            throw DatabaseError.invalidData
        }

        // Ensure required fields exist with defaults
        data["id"] = userId
        if data["displayName"] == nil { data["displayName"] = "New User" }
        if data["bio"] == nil { data["bio"] = "" }
        if data["socialLinks"] == nil { data["socialLinks"] = [] }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: data)
            let profile = try JSONDecoder().decode(UserProfile.self, from: jsonData)
            logger.debug("✅ Profile fetched successfully")
            return profile
        } catch {
            logger.error("❌ Failed to decode profile data: \(error.localizedDescription)")
            throw DatabaseError.serializationError(error)
        }
    }

    /// Updates a user's profile in the database
    /// - Parameter profile: The profile data to update
    func updateProfile(_ profile: UserProfile) async throws {
        logger.debug("📝 Updating profile for user: \(profile.id)")

        let userRef = database.child("users").child(profile.id)

        do {
            let data = try JSONEncoder().encode(profile)
            guard var dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw DatabaseError.serializationError(NSError(domain: "ProfileDatabase", code: -1))
            }

            // Add server timestamp
            dict["lastUpdated"] = ServerValue.timestamp()

            try await userRef.updateChildValues(dict)
            logger.debug("✅ Profile updated successfully")
        } catch {
            logger.error("❌ Failed to update profile: \(error.localizedDescription)")
            throw DatabaseError.networkError(error)
        }
    }
}
