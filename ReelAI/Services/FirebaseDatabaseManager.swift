import FirebaseDatabase

final class FirebaseDatabaseManager: DatabaseManager {
    private let db = Database.database().reference()

    func updateProfile(_ profile: UserProfile) async throws {
        let data = try JSONEncoder().encode(profile)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        try await db.child("users").child(profile.id).updateChildValues(dict)
    }

    func fetchProfile(userId: String) async throws -> UserProfile {
        let snapshot = try await db.child("users").child(userId).getData()
        guard let data = snapshot.value as? [String: Any] else {
            throw DatabaseError.invalidData
        }
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

    func fetchVideos(limit: Int, after key: String?) async throws -> [Video] {
        var query = db.child("videos")
            .queryOrdered(byChild: "timestamp")
            .queryLimited(toFirst: UInt(limit))

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
