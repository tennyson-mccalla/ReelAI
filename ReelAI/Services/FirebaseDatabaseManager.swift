import FirebaseDatabase
import FirebaseStorage
import os

@MainActor
final class FirebaseDatabaseManager: DatabaseManager {
    @MainActor static let shared = FirebaseDatabaseManager()
    private let db: DatabaseReference
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReelAI", category: "DatabaseManager")

    private init() {
        Database.database().isPersistenceEnabled = true
        db = Database.database().reference()
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
        try await db.child(update.path).updateChildValues(dict)
    }

    @MainActor
    func fetchProfile(userId: String) async throws -> UserProfile {
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
    }

    @MainActor
    func updateVideo(_ video: Video) async throws {
        let update = DatabaseUpdate(path: "videos/\(video.id)", value: video)
        let dict = try convertToDict(update.value)
        try await db.child(update.path).updateChildValues(dict)
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
        try await db.child(update.path).updateChildValues(dict)

        logger.debug("✅ DatabaseManager: Video marked as deleted in database")
    }

    @MainActor
    func restoreVideo(_ videoId: String) async throws {
        logger.debug("🔄 DatabaseManager: Starting restore for video: \(videoId)")

        let updateData = VideoUpdateData(id: videoId, isDeleted: false)
        let update = DatabaseUpdate(path: "videos/\(videoId)", value: updateData)
        let dict = try convertToDict(update.value)
        try await db.child(update.path).updateChildValues(dict)

        logger.debug("✅ DatabaseManager: Video restored in database")
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
        try await db.child("videos").child(videoId).updateChildValues(dict)

        logger.debug("✅ Privacy updated in database")
    }

    @MainActor
    func updateVideoMetadata(_ videoId: String, caption: String) async throws {
        logger.debug("📝 Attempting to update caption for video: \(videoId)")

        let updateData = VideoCaptionUpdate(caption: caption)
        let update = DatabaseUpdate(path: "videos/\(videoId)", value: updateData)
        let dict = try convertToDict(update.value)
        try await db.child(update.path).updateChildValues(dict)

        logger.debug("✅ Caption updated in database")
    }

    @MainActor
    func fetchVideos(limit: Int, after key: String?) async throws -> [Video] {
        logger.debug("📥 Fetching videos from database")

        let query = db.child("videos")
            .queryOrdered(byChild: "timestamp")
            .queryLimited(toLast: UInt(limit))

        if let key = key {
            query.queryEnding(beforeValue: key)
        }

        let snapshot = try await query.getData()

        guard let dict = snapshot.value as? [String: [String: Any]] else {
            logger.debug("📭 No videos found in database")
            return []
        }

        logger.debug("🔍 Raw video data: \(dict)")
        var videos: [Video] = []

        for (id, data) in dict {
            var mutableData = data
            mutableData["id"] = id

            // Get video URL from Storage
            if let videoName = mutableData["videoName"] as? String {
                let videoRef = Storage.storage().reference().child("videos/\(videoName)")
                let thumbnailRef = Storage.storage().reference().child("thumbnails/\(videoName.replacingOccurrences(of: ".mp4", with: ".jpg"))")

                do {
                    // Check if video exists and get URL
                    _ = try await videoRef.getMetadata()
                    let videoURL = try await videoRef.downloadURL()
                    mutableData["videoURL"] = videoURL.absoluteString

                    // Try to get thumbnail URL if it exists
                    do {
                        _ = try await thumbnailRef.getMetadata()
                        let thumbnailURL = try await thumbnailRef.downloadURL()
                        mutableData["thumbnailURL"] = thumbnailURL.absoluteString
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
    }

    enum DatabaseError: Error {
        case invalidData
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
