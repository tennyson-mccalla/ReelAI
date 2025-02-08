import FirebaseDatabase
import os

final class FirebaseDatabaseManager: DatabaseManager {
    private let db = Database.database().reference()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReelAI", category: "DatabaseManager")

    func updateProfile(_ profile: UserProfile) async throws {
        let data = try JSONEncoder().encode(profile)
        var dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        // Ensure required fields
        dict["id"] = profile.id
        dict["displayName"] = profile.displayName
        dict["bio"] = profile.bio
        dict["socialLinks"] = profile.socialLinks
        if let photoURL = profile.photoURL?.absoluteString {
            dict["photoURL"] = photoURL
        }

        try await db.child("users").child(profile.id).updateChildValues(dict)
    }

    func fetchProfile(userId: String) async throws -> UserProfile {
        let snapshot = try await db.child("users").child(userId).getData()
        guard var data = snapshot.value as? [String: Any] else {
            throw DatabaseError.invalidData
        }

        // Ensure all required fields exist with defaults
        data["id"] = userId
        if data["displayName"] == nil { data["displayName"] = "New User" }
        if data["bio"] == nil { data["bio"] = "" }
        if data["socialLinks"] == nil { data["socialLinks"] = [] }

        let jsonData = try JSONSerialization.data(withJSONObject: data)
        return try JSONDecoder().decode(UserProfile.self, from: jsonData)
    }

    func updateVideo(_ video: Video) async throws {
        let data = try JSONEncoder().encode(video)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        try await db.child("videos").child(video.id).updateChildValues(dict)
    }

    func deleteVideo(id: String) async throws {
        try await db.child("videos").child(id).removeValue()
    }

    func softDeleteVideo(_ videoId: String) async throws {
        logger.debug("🗑️ DatabaseManager: Starting soft delete for video: \(videoId)")

        // Get current state first
        let snapshot = try await db.child("videos/\(videoId)").getData()
        if let value = snapshot.value {
            logger.debug("📥 DatabaseManager: Current state - \(String(describing: value))")
        }

        try await db.child("videos/\(videoId)").updateChildValues([
            "isDeleted": true
        ])

        // Verify the update
        let updatedSnapshot = try await db.child("videos/\(videoId)").getData()
        if let value = updatedSnapshot.value {
            logger.debug("📤 DatabaseManager: Updated state - \(String(describing: value))")
        }

        logger.debug("✅ DatabaseManager: Video marked as deleted in database")
    }

    func restoreVideo(_ videoId: String) async throws {
        logger.debug("🔄 DatabaseManager: Starting restore for video: \(videoId)")

        // Get current state first
        let snapshot = try await db.child("videos/\(videoId)").getData()
        if let value = snapshot.value {
            logger.debug("📥 DatabaseManager: Current state - \(String(describing: value))")
        }

        let updates: [String: Any] = [
            "isDeleted": false,
            "lastEditedAt": Int(Date().timeIntervalSince1970 * 1000)
        ]
        try await db.child("videos/\(videoId)").updateChildValues(updates)

        // Verify the update
        let updatedSnapshot = try await db.child("videos/\(videoId)").getData()
        if let value = updatedSnapshot.value {
            logger.debug("📤 DatabaseManager: Updated state - \(String(describing: value))")
        }

        logger.debug("✅ DatabaseManager: Video restored in database")
    }

    func updateVideoPrivacy(_ videoId: String, privacyLevel: Video.PrivacyLevel) async throws {
        logger.debug("🔒 Attempting to update privacy for video: \(videoId) to \(String(describing: privacyLevel))")

        // Create a Video object with just the privacy update
        let update = VideoPrivacyUpdate(
            id: videoId,
            privacyLevel: privacyLevel,
            lastEditedAt: Date()
        )

        let data = try JSONEncoder().encode(update)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        try await db.child("videos").child(videoId).updateChildValues(dict)

        logger.debug("✅ Privacy updated in database")
    }

    func updateVideoMetadata(_ videoId: String, caption: String) async throws {
        logger.debug("📝 Attempting to update caption for video: \(videoId)")
        let updates: [String: Any] = [
            "caption": caption.trimmingCharacters(in: .whitespacesAndNewlines),
            "lastEditedAt": Int(Date().timeIntervalSince1970 * 1000)
        ]
        try await db.child("videos/\(videoId)").updateChildValues(updates)
        logger.debug("✅ Caption updated in database")
    }

    func fetchVideos(limit: Int, after key: String?) async throws -> [Video] {
        logger.debug("📥 Fetching videos from database")

        // Create the query
        let query = db.child("videos")
            .queryOrdered(byChild: "timestamp")
            .queryLimited(toLast: UInt(limit))

        // Disable cache for this reference
        db.child("videos").keepSynced(false)

        // Get fresh data from server
        let snapshot = try await query.getData()
        logger.debug("📤 Got \(snapshot.childrenCount) videos from database")

        guard let dict = snapshot.value as? [String: [String: Any]] else {
            return []
        }

        // Log each video's state
        for (id, data) in dict {
            logger.debug("""
            🎥 Video in database:
            ID: \(id)
            Deleted: \(data["isDeleted"] as? Bool ?? false)
            Privacy: \(data["privacyLevel"] as? String ?? "public")
            """)
        }

        return try dict.compactMap { id, data in
            var mutableData = data
            mutableData["id"] = id
            let jsonData = try JSONSerialization.data(withJSONObject: mutableData)
            return try JSONDecoder().decode(Video.self, from: jsonData)
        }
    }

    enum DatabaseError: Error {
        case invalidData
    }
}

// Add this struct
private struct VideoPrivacyUpdate: Codable {
    let id: String
    let privacyLevel: Video.PrivacyLevel
    let lastEditedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case privacyLevel
        case lastEditedAt
    }
}
