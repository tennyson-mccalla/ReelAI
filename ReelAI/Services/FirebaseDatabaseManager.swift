import FirebaseDatabase
import FirebaseStorage
import FirebaseAuth
import os

@MainActor
final class FirebaseDatabaseManager: DatabaseManager {
    @MainActor static let shared = FirebaseDatabaseManager()
    private let db: DatabaseReference
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReelAI", category: "DatabaseManager")
    private let networkMonitor = NetworkMonitor.shared
    private var isInitialFetch = true

    private init() {
        // Configure Firebase persistence with a size limit
        Database.database().persistenceCacheSizeBytes = 100 * 1024 * 1024 // 100MB limit for better caching
        Database.database().isPersistenceEnabled = true
        db = Database.database().reference()

        // Keep the database connection alive
        db.keepSynced(true)

        // Setup initial listeners for key paths to maintain disk cache
        setupInitialListeners()
        setupDatabaseConnection()
    }

    private func setupInitialListeners() {
        // Setup a small limit listener to maintain cache
        db.child("videos")
            .queryLimited(toLast: 5)
            .observe(.value) { [weak self] snapshot in
                self?.logger.debug("🔄 Background sync: \(snapshot.childrenCount) videos")
            }
    }

    private func setupDatabaseConnection() {
        // Start with online mode
        db.database.goOnline()

        networkMonitor.startMonitoring { [weak self] status in
            guard let self = self else { return }
            switch status {
            case .satisfied:
                self.logger.debug("✅ Network available, enabling database")
                self.db.database.goOnline()

                // Only purge if not initial connection
                if !self.isInitialFetch {
                    Database.database().purgeOutstandingWrites()
                }
                self.isInitialFetch = false

                NotificationCenter.default.post(name: .databaseConnectionEstablished, object: nil)
            case .unsatisfied:
                self.logger.warning("⚠️ Network unavailable, database going offline")
                self.db.database.goOffline()
            default:
                break
            }
        }
    }

    // Convert DatabaseError to NetworkErrorType
    private func handleDatabaseError(_ error: Error) -> NetworkErrorType {
        if let dbError = error as? DatabaseError {
            switch dbError {
            case .offline:
                return .connectionLost
            case .notAuthenticated:
                return .unauthorized
            case .invalidData:
                return .serverError
            }
        }
        return (error as NSError).networkErrorType
    }

    // Add error handling helper
    private func handleError(_ error: Error, operation: String) {
        _ = handleDatabaseError(error)  // Ignore the return value since we're just logging
        logger.error("❌ \(operation) failed with error: \(error.localizedDescription)")
        NetworkErrorHandler.handle(error,
            retryAction: { [weak self] in
                self?.logger.debug("🔄 Will retry \(operation)")
            },
            fallbackAction: { [weak self] in
                self?.logger.error("❌ \(operation) failed, using fallback")
            })
    }

    // Sendable-compliant struct for database updates
    private struct DatabaseUpdate<T: Encodable & Sendable>: Sendable {
        let path: String
        let value: T
    }

    // Sendable-compliant struct for profile updates
    private struct ProfileUpdateData: Codable, Sendable {
        let id: String
        let displayName: String
        let bio: String
        let socialLinks: [UserProfile.SocialLink]
        let photoURL: String?

        init(from profile: UserProfile) {
            self.id = profile.id
            self.displayName = profile.displayName
            self.bio = profile.bio
            self.socialLinks = profile.socialLinks
            self.photoURL = profile.photoURL?.absoluteString
        }
    }

    // Sendable-compliant structs for video updates
    private struct VideoUpdateData: Codable, Sendable {
        let id: String
        let isDeleted: Bool
        let lastEditedAt: Int

        init(id: String, isDeleted: Bool) {
            self.id = id
            self.isDeleted = isDeleted
            self.lastEditedAt = Int(Date().timeIntervalSince1970 * 1000)
        }
    }

    private struct VideoCaptionUpdate: Codable, Sendable {
        let caption: String
        let lastEditedAt: Int

        init(caption: String) {
            self.caption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
            self.lastEditedAt = Int(Date().timeIntervalSince1970 * 1000)
        }
    }

    // Helper method for safe JSON conversion
    @MainActor
    private func convertToDict<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    @MainActor
    func updateProfile(_ profile: UserProfile) async throws {
        // Create Sendable update data
        let updateData = ProfileUpdateData(from: profile)
        let update = DatabaseUpdate(path: "users/\(profile.id)", value: updateData)
        let dict = try convertToDict(update.value)
        do {
            try await db.child(update.path).updateChildValues(dict)
        } catch {
            handleError(error, operation: "Update profile")
            throw error
        }
    }

    @MainActor
    func fetchProfile(userId: String) async throws -> UserProfile {
        do {
            let snapshot = try await db.child("users").child(userId).getData()
            guard var data = snapshot.value as? [String: Any] else {
                throw DatabaseError.invalidData
            }

            // Since we're already on the main actor, we can do this directly
            // Ensure all required fields exist with defaults
            data["id"] = userId
            if data["displayName"] == nil { data["displayName"] = "New User" }
            if data["bio"] == nil { data["bio"] = "" }
            if data["socialLinks"] == nil { data["socialLinks"] = [] }

            // Explicitly handle photoURL
            if let photoURLString = data["photoURL"] as? String {
                data["photoURL"] = photoURLString
                print("🔍 Fetched Photo URL from Database: \(photoURLString)")
            } else {
                print("⚠️ No Photo URL found in database")
                data["photoURL"] = NSNull()
            }

            let jsonData = try JSONSerialization.data(withJSONObject: data)
            return try JSONDecoder().decode(UserProfile.self, from: jsonData)
        } catch {
            handleError(error, operation: "Fetch profile")
            throw error
        }
    }

    @MainActor
    func updateVideo(_ video: Video) async throws {
        guard let userId = video.userId else {
            logger.error("❌ No userId provided in video data")
            throw DatabaseError.invalidData
        }

        // Debug auth state
        if let currentUser = Auth.auth().currentUser {
            logger.debug("🔐 Attempting database write with auth - UID: \(currentUser.uid)")
            logger.debug("🔄 Video userId: \(userId), Current user: \(currentUser.uid)")
        } else {
            logger.error("❌ No authenticated user found when attempting database write")
            throw DatabaseError.notAuthenticated
        }

        // Create a safe ID by removing any invalid characters
        let safeId = video.id.replacingOccurrences(of: ".", with: "-")
                            .replacingOccurrences(of: "#", with: "-")
                            .replacingOccurrences(of: "$", with: "-")
                            .replacingOccurrences(of: "[", with: "-")
                            .replacingOccurrences(of: "]", with: "-")
        logger.debug("🆔 Generated safe ID: \(safeId) from original: \(video.id)")

        // Extract videoName from URL
        let videoName = video.videoURL.lastPathComponent
        logger.debug("📹 Video name: \(videoName)")

        // Ensure all required fields are present and properly formatted
        let videoData: [String: Any] = [
            "userId": userId,
            "timestamp": ServerValue.timestamp(),
            "caption": video.caption,
            "likes": video.likes,
            "comments": video.comments,
            "isDeleted": video.isDeleted,
            "privacyLevel": video.privacyLevel.rawValue,
            "videoName": videoName
        ]

        logger.debug("📝 Full video data to write: \(videoData)")
        logger.debug("🔗 Writing to database path: videos/\(safeId)")

        do {
            try await db.child("videos").child(safeId).setValue(videoData)
            logger.debug("✅ Video data successfully written to database")
        } catch {
            handleError(error, operation: "Database write")
            throw error
        }
    }

    func deleteVideo(id: String) async throws {
        try await db.child("videos").child(id).removeValue()
    }

    @MainActor
    func softDeleteVideo(_ videoId: String) async throws {
        logger.debug("🗑️ DatabaseManager: Starting soft delete for video: \(videoId)")

        let updateData = VideoUpdateData(id: videoId, isDeleted: true)
        let update = DatabaseUpdate(path: "videos/\(videoId)", value: updateData)
        let dict = try convertToDict(update.value)
        do {
            try await db.child(update.path).updateChildValues(dict)
            logger.debug("✅ DatabaseManager: Video marked as deleted in database")
        } catch {
            handleError(error, operation: "Soft delete video")
            throw error
        }
    }

    @MainActor
    func restoreVideo(_ videoId: String) async throws {
        logger.debug("🔄 DatabaseManager: Starting restore for video: \(videoId)")

        let updateData = VideoUpdateData(id: videoId, isDeleted: false)
        let update = DatabaseUpdate(path: "videos/\(videoId)", value: updateData)
        let dict = try convertToDict(update.value)
        do {
            try await db.child(update.path).updateChildValues(dict)
            logger.debug("✅ DatabaseManager: Video restored in database")
        } catch {
            handleError(error, operation: "Restore video")
            throw error
        }
    }

    @MainActor
    func updateVideoPrivacy(_ videoId: String, privacyLevel: Video.PrivacyLevel) async throws {
        logger.debug("🔒 Attempting to update privacy for video: \(videoId) to \(String(describing: privacyLevel))")

        let update = VideoPrivacyUpdate(
            id: videoId,
            privacyLevel: privacyLevel,
            lastEditedAt: Date()
        )
        let dict = try convertToDict(update)
        do {
            try await db.child("videos").child(videoId).updateChildValues(dict)
            logger.debug("✅ Privacy updated in database")
        } catch {
            handleError(error, operation: "Update video privacy")
            throw error
        }
    }

    @MainActor
    func updateVideoMetadata(_ videoId: String, caption: String) async throws {
        logger.debug("📝 Attempting to update caption for video: \(videoId)")

        let updateData = VideoCaptionUpdate(caption: caption)
        let update = DatabaseUpdate(path: "videos/\(videoId)", value: updateData)
        let dict = try convertToDict(update.value)
        do {
            try await db.child(update.path).updateChildValues(dict)
            logger.debug("✅ Caption updated in database")
        } catch {
            handleError(error, operation: "Update video metadata")
            throw error
        }
    }

    @MainActor
    func fetchVideos(limit: Int, after key: String?) async throws -> [Video] {
        logger.debug("📥 Fetching videos from database")

        // Create a reference that we'll keep synced
        let videosQuery = db.child("videos")
            .queryOrdered(byChild: "timestamp")
            .queryLimited(toLast: UInt(limit))

        // Keep this query synced for offline access
        videosQuery.keepSynced(true)

        if let key = key {
            videosQuery.queryEnding(beforeValue: key)
        }

        do {
            let snapshot = try await videosQuery.getData()
            guard let dict = snapshot.value as? [String: [String: Any]] else {
                logger.debug("📭 No videos found in database")
                return []
            }

            logger.debug("🔍 Raw video data: \(dict)")
            var videos: [Video] = []

            for (id, data) in dict {
                var mutableData = data
                mutableData["id"] = id

                // Get video URL from Storage using videoName
                if let videoName = mutableData["videoName"] as? String {
                    let videoRef = Storage.storage().reference().child("videos/\(videoName)")
                    // Ensure thumbnail path always has .jpg extension
                    let thumbnailName = videoName.hasSuffix(".jpg") ? videoName : videoName.replacingOccurrences(of: ".mp4", with: "") + ".jpg"
                    let thumbnailRef = Storage.storage().reference().child("thumbnails/\(thumbnailName)")

                    do {
                        // Check if video exists and get URL
                        let videoURL = try await videoRef.downloadURL()
                        mutableData["videoURL"] = videoURL.absoluteString
                        logger.debug("✅ Got video URL for \(id): \(videoURL.absoluteString)")

                        // Try to get thumbnail URL if it exists
                        do {
                            let thumbnailURL = try await thumbnailRef.downloadURL()
                            mutableData["thumbnailURL"] = thumbnailURL.absoluteString
                            logger.debug("✅ Got thumbnail URL for \(id): \(thumbnailURL.absoluteString)")
                        } catch {
                            logger.debug("⚠️ No thumbnail found for video \(id): \(error.localizedDescription)")
                            mutableData["thumbnailURL"] = nil
                        }

                        // Ensure required fields exist with defaults
                        if mutableData["timestamp"] == nil {
                            logger.debug("⚠️ No timestamp found for video \(id), using current time")
                            mutableData["timestamp"] = Date().timeIntervalSince1970 * 1000
                        }

                        // Add default values for optional fields if missing
                        if mutableData["caption"] == nil { mutableData["caption"] = "" }
                        if mutableData["likes"] == nil { mutableData["likes"] = 0 }
                        if mutableData["comments"] == nil { mutableData["comments"] = 0 }
                        if mutableData["isDeleted"] == nil { mutableData["isDeleted"] = false }
                        if mutableData["privacyLevel"] == nil { mutableData["privacyLevel"] = "public" }

                        let jsonData = try JSONSerialization.data(withJSONObject: mutableData)
                        let video = try JSONDecoder().decode(Video.self, from: jsonData)
                        videos.append(video)
                        logger.debug("✅ Successfully processed video \(id)")
                    } catch {
                        logger.error("❌ Failed to process video \(id): \(error.localizedDescription)")
                        continue
                    }
                } else {
                    logger.warning("⚠️ Missing videoName for video \(id)")
                    continue
                }
            }

            logger.debug("📦 Processed \(videos.count) video entries")
            return videos.sorted { $0.createdAt > $1.createdAt }
        } catch {
            handleError(error, operation: "Fetch videos")
            throw error
        }
    }

    enum DatabaseError: Error {
        case invalidData
        case notAuthenticated
        case offline
    }
}

// Make VideoPrivacyUpdate Sendable
private struct VideoPrivacyUpdate: Codable, Sendable {
    let id: String
    let privacyLevel: Video.PrivacyLevel
    let lastEditedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case privacyLevel
        case lastEditedAt
    }
}

extension Notification.Name {
    static let databaseConnectionEstablished = Notification.Name("DatabaseConnectionEstablished")
}
