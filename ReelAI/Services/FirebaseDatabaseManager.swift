import FirebaseDatabase

final class FirebaseDatabaseManager: DatabaseManager {
    private let db = Database.database().reference()

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
        let updates: [String: Any] = [
            "isDeleted": true,
            "lastEditedAt": ServerValue.timestamp()
        ]
        try await db.child("videos").child(videoId).updateChildValues(updates)
    }

    func restoreVideo(_ videoId: String) async throws {
        let updates: [String: Any] = [
            "isDeleted": false,
            "lastEditedAt": ServerValue.timestamp()
        ]
        try await db.child("videos").child(videoId).updateChildValues(updates)
    }

    func updateVideoPrivacy(_ videoId: String, privacyLevel: Video.PrivacyLevel) async throws {
        let updates: [String: Any] = [
            "privacyLevel": privacyLevel.rawValue,
            "lastEditedAt": ServerValue.timestamp()
        ]
        try await db.child("videos").child(videoId).updateChildValues(updates)
    }

    func updateVideoMetadata(_ videoId: String, caption: String) async throws {
        let updates: [String: Any] = [
            "caption": caption.trimmingCharacters(in: .whitespacesAndNewlines),
            "lastEditedAt": ServerValue.timestamp()
        ]
        try await db.child("videos").child(videoId).updateChildValues(updates)
    }

    func fetchVideos(limit: Int, after key: String?) async throws -> [Video] {
        var query = db.child("videos")
            .queryOrdered(byChild: "timestamp")
            .queryLimited(toFirst: UInt(limit))
            // Only fetch non-deleted videos
            .queryEqual(toValue: false, childKey: "isDeleted")

        if let key = key {
            query = query.queryStarting(afterValue: nil, childKey: key)
        }

        let snapshot = try await query.getData()
        guard let dict = snapshot.value as? [String: [String: Any]] else {
            return []
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
