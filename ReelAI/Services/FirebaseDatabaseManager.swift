import FirebaseDatabase
import FirebaseStorage
import FirebaseAuth
import os

actor FirebaseDatabaseManager: ReelDB.Manager {
    // MARK: - Shared Instance
    private static let instance = FirebaseDatabaseManager()

    static var shared: any ReelDB.Manager {
        get async {
            return await instance
        }
    }

    // MARK: - Protocol Requirements
    nonisolated let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReelAI", category: "DatabaseManager")
    nonisolated let databaseRef: DatabaseReference = Database.database().reference()

    // MARK: - Private Properties
    private nonisolated let networkMonitor = NetworkMonitor.shared
    private var isInitialFetch = true
    private var isConfigured = false

    private init() {
        // Configure Firebase persistence synchronously during initialization
        Database.database().persistenceCacheSizeBytes = 100 * 1024 * 1024
        Database.database().isPersistenceEnabled = true

        // Start async configuration
        Task {
            await configure()
        }
    }

    nonisolated func configure() async {
        // Configure Firebase persistence with a size limit
        Database.database().persistenceCacheSizeBytes = 100 * 1024 * 1024 // 100MB limit
        Database.database().isPersistenceEnabled = true

        // Keep the database reference synchronized
        databaseRef.keepSynced(true)

        // Setup connection handling
        await setupDatabaseConnection()
    }

    nonisolated func setupDatabaseConnection() async {
        // Start with online mode
        databaseRef.database.goOnline()

        await networkMonitor.startMonitoring { [weak self] status in
            guard let self = self else { return }
            Task { @MainActor in
                switch status {
                case .satisfied:
                    self.logger.debug("✅ Network available, enabling database")
                    self.databaseRef.database.goOnline()
                    NotificationCenter.default.post(name: .databaseConnectionEstablished, object: nil)
                case .unsatisfied:
                    self.logger.warning("⚠️ Network unavailable, database going offline")
                    self.databaseRef.database.goOffline()
                default:
                    break
                }
            }
        }
    }

    private func setupInitialListeners() async {
        // Setup a small limit listener to maintain cache
        databaseRef.child("videos")
            .queryLimited(toLast: 5)
            .observe(.value) { [weak self] snapshot in
                self?.logger.debug("🔄 Background sync: \(snapshot.childrenCount) videos")
            }
    }

    // Convert ReelDB.Error to NetworkErrorType
    private func handleDatabaseError(_ error: Error) -> NetworkErrorType {
        if let dbError = error as? ReelDB.Error {
            switch dbError {
            case .offline:
                return .connectionLost
            case .notAuthenticated:
                return .unauthorized
            case .invalidData:
                return .serverError
            default:
                return .serverError
            }
        }
        return (error as NSError).networkErrorType
    }

    // Add error handling helper
    nonisolated func handleError(_ error: Error, operation: String) {
        logger.error("❌ \(operation) failed with error: \(error.localizedDescription)")
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
        }
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
        let lastEditedAt: Int64

        init(id: String, isDeleted: Bool) {
            self.id = id
            self.isDeleted = isDeleted
            self.lastEditedAt = Int64(Date().timeIntervalSince1970 * 1000)
        }
    }

    private struct VideoCaptionUpdate: Codable, Sendable {
        let caption: String
        let lastEditedAt: Int64

        init(caption: String) {
            self.caption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
            self.lastEditedAt = Int64(Date().timeIntervalSince1970 * 1000)
        }
    }

    // Helper method for safe JSON conversion
    private func convertToDict<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    func updateProfile(_ profile: UserProfile) async throws {
        let updateData = ProfileUpdateData(from: profile)
        let update = DatabaseUpdate(path: "users/\(profile.id)", value: updateData)
        let dict = try convertToDict(update.value)
        let dbRef = self.databaseRef

        do {
            try await dbRef.child(update.path).updateChildValues(dict)
        } catch {
            handleError(error, operation: "Update profile")
            throw error
        }
    }

    func fetchProfile(userId: String) async throws -> UserProfile {
        let dbRef = self.databaseRef
        do {
            let snapshot = try await dbRef.child("users").child(userId).getData()
            guard var data = snapshot.value as? [String: Any] else {
                throw ReelDB.Error.invalidData
            }

            // Ensure all required fields exist with defaults
            data["id"] = userId
            if data["displayName"] == nil { data["displayName"] = "New User" }
            if data["bio"] == nil { data["bio"] = "" }
            if data["socialLinks"] == nil { data["socialLinks"] = [] }

            // Handle photoURL
            if data["photoURL"] is String {
                let photoRef = Storage.storage().reference().child("profile_photos/\(userId)/profile.jpg")
                do {
                    let freshURL = try await photoRef.downloadURL()
                    data["photoURL"] = freshURL.absoluteString
                } catch {
                    data["photoURL"] = NSNull()
                }
            } else {
                data["photoURL"] = NSNull()
            }

            let jsonData = try JSONSerialization.data(withJSONObject: data)
            return try JSONDecoder().decode(UserProfile.self, from: jsonData)
        } catch {
            handleError(error, operation: "Fetch profile")
            throw error
        }
    }

    func updateVideo(_ video: Video) async throws {
        guard let userId = video.userId else {
            logger.error("❌ No userId provided in video data")
            throw ReelDB.Error.invalidData
        }

        // Debug auth state
        if let currentUser = Auth.auth().currentUser {
            logger.debug("🔐 Attempting database write with auth - UID: \(currentUser.uid)")
            logger.debug("🔄 Video userId: \(userId), Current user: \(currentUser.uid)")
        } else {
            logger.error("❌ No authenticated user found when attempting database write")
            throw ReelDB.Error.notAuthenticated
        }

        let dbRef = self.databaseRef

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

        // Fix the ambiguous type annotations
        let timestamp: [String: Any] = ReelDB.Utils.serverTimestamp()

        // In updateVideo method
        let videoData: [String: Any] = [
            "userId": userId,
            "timestamp": timestamp,
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
            try await dbRef.child("videos").child(safeId).setValue(videoData)
            logger.debug("✅ Video data successfully written to database")
        } catch {
            handleError(error, operation: "Database write")
            throw error
        }
    }

    func deleteVideo(id: String) async throws {
        let dbRef = self.databaseRef
        try await dbRef.child("videos").child(id).removeValue()
    }

    func softDeleteVideo(_ videoId: String) async throws {
        let dbRef = self.databaseRef
        logger.debug("🗑️ DatabaseManager: Starting soft delete for video: \(videoId)")

        let updateData = VideoUpdateData(id: videoId, isDeleted: true)
        let update = DatabaseUpdate(path: "videos/\(videoId)", value: updateData)
        let dict = try convertToDict(update.value)
        do {
            try await dbRef.child(update.path).updateChildValues(dict)
            logger.debug("✅ DatabaseManager: Video marked as deleted in database")
        } catch {
            handleError(error, operation: "Soft delete video")
            throw error
        }
    }

    func restoreVideo(_ videoId: String) async throws {
        let dbRef = self.databaseRef
        logger.debug("🔄 DatabaseManager: Starting restore for video: \(videoId)")

        let updateData = VideoUpdateData(id: videoId, isDeleted: false)
        let update = DatabaseUpdate(path: "videos/\(videoId)", value: updateData)
        let dict = try convertToDict(update.value)
        do {
            try await dbRef.child(update.path).updateChildValues(dict)
            logger.debug("✅ DatabaseManager: Video restored in database")
        } catch {
            handleError(error, operation: "Restore video")
            throw error
        }
    }

    func updateVideoPrivacy(_ videoId: String, privacyLevel: Video.PrivacyLevel) async throws {
        let dbRef = self.databaseRef
        logger.debug("🔒 Attempting to update privacy for video: \(videoId) to \(String(describing: privacyLevel))")

        let update = VideoPrivacyUpdate(
            id: videoId,
            privacyLevel: privacyLevel,
            lastEditedAt: Date()
        )
        var dict = try ReelDB.Utils.convertToDict(update) as [String: Any]
        let timestamp: [String: Any] = ReelDB.Utils.serverTimestamp()
        dict["timestamp"] = timestamp
        do {
            try await dbRef.child("videos").child(videoId).updateChildValues(dict)
            logger.debug("✅ Privacy updated in database")
        } catch {
            handleError(error, operation: "Update video privacy")
            throw error
        }
    }

    func updateVideoMetadata(_ videoId: String, caption: String) async throws {
        let dbRef = self.databaseRef
        logger.debug("📝 Attempting to update caption for video: \(videoId)")

        let updateData = VideoCaptionUpdate(caption: caption)
        let update = DatabaseUpdate(path: "videos/\(videoId)", value: updateData)
        let dict = try convertToDict(update.value)
        do {
            try await dbRef.child(update.path).updateChildValues(dict)
            logger.debug("✅ Caption updated in database")
        } catch {
            handleError(error, operation: "Update video metadata")
            throw error
        }
    }

    func fetchVideos(limit: Int, after key: String?) async throws -> [Video] {
        let dbRef = self.databaseRef
        logger.debug("📥 Fetching videos from database")

        // Create a reference that we'll keep synced
        let videosQuery = dbRef.child("videos")
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

                        // Try to get thumbnail URL if it exists
                        do {
                            let thumbnailURL = try await thumbnailRef.downloadURL()
                            mutableData["thumbnailURL"] = thumbnailURL.absoluteString
                        } catch {
                            mutableData["thumbnailURL"] = nil
                        }

                        // Ensure required fields exist with defaults
                        if mutableData["timestamp"] == nil {
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
                    } catch {
                        logger.error("Failed to process video \(id): \(error.localizedDescription)")
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

    // Helper method to debug data structure
    private func debugDataStructure(_ data: [String: Any], prefix: String = "") {
        logger.debug("🔍 Data Structure:")
        for (key, value) in data {
            if let nestedDict = value as? [String: Any] {
                logger.debug("\(prefix)[\(key)]")
                debugDataStructure(nestedDict, prefix: prefix + "  ")
            } else {
                logger.debug("\(prefix)\(key): \(value)")
            }
        }
    }

    func updateProfilePhoto(userId: String, photoURL: URL) async throws {
        let dbRef = self.databaseRef
        logger.debug("📸 Updating profile photo URL for user: \(userId)")

        // Verify user is authenticated and has permission
        guard let currentUser = Auth.auth().currentUser else {
            logger.error("❌ No authenticated user found")
            throw ReelDB.Error.notAuthenticated
        }

        guard currentUser.uid == userId else {
            logger.error("❌ User does not have permission to update this profile")
            throw ReelDB.Error.permissionDenied
        }

        // Reference directly to the user's node
        let userRef = dbRef.child("users").child(userId)

        // First fetch the current profile to ensure it exists
        let snapshot = try await userRef.getData()
        guard snapshot.exists() else {
            logger.error("❌ User profile does not exist")
            throw ReelDB.Error.invalidData
        }

        // Log current profile data
        if let userData = snapshot.value as? [String: Any] {
            logger.debug("📸 Current user data structure:")
            for (key, value) in userData {
                logger.debug("  \(key): \(value)")
            }
        }

        // In updateProfilePhoto method
        let timestamp: [String: Any] = ReelDB.Utils.serverTimestamp()
        let update: [String: Any] = [
            "photoURL": photoURL.absoluteString,
            "lastUpdated": timestamp
        ]

        do {
            // Update the profile
            try await userRef.updateChildValues(update)
            logger.debug("✅ Profile photo URL update operation completed")

            // Fetch and verify the updated profile
            let verifySnapshot = try await userRef.getData()
            guard let userData = verifySnapshot.value as? [String: Any] else {
                logger.error("❌ Could not read user data")
                throw ReelDB.Error.invalidData
            }

            // Extract and verify the photoURL
            guard let updatedPhotoURL = userData["photoURL"] as? String else {
                logger.error("❌ Could not find photoURL in user data")
                logger.debug("📸 Available fields:")
                for (key, value) in userData {
                    logger.debug("  \(key): \(value)")
                }
                throw ReelDB.Error.invalidData
            }

            logger.debug("✅ Verified photo URL in database: \(updatedPhotoURL)")

            // Notify UI to refresh
            await MainActor.run {
                NotificationCenter.default.post(
                    name: Notification.Name("ProfilePhotoUpdated"),
                    object: URL(string: updatedPhotoURL)
                )
            }
        } catch {
            logger.error("❌ Failed to update profile photo: \(error.localizedDescription)")
            if let dbError = error as? ReelDB.Error {
                logger.error("❌ Database error type: \(String(describing: dbError))")
            }
            handleError(error, operation: "Update profile photo")
            throw error
        }
    }
}

// Make VideoPrivacyUpdate Sendable
private struct VideoPrivacyUpdate: Codable, Sendable {
    let id: String
    let privacyLevel: Video.PrivacyLevel
    let lastEditedAt: Int64

    init(id: String, privacyLevel: Video.PrivacyLevel, lastEditedAt: Date) {
        self.id = id
        self.privacyLevel = privacyLevel
        self.lastEditedAt = Int64(lastEditedAt.timeIntervalSince1970 * 1000)
    }
}

extension Notification.Name {
    static let databaseConnectionEstablished = Notification.Name("DatabaseConnectionEstablished")
}
