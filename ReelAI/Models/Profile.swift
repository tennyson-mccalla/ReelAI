import Foundation

struct Profile: Identifiable, Codable {
    let id: String
    var displayName: String
    var username: String?
    var bio: String?
    var photoURL: URL?
    var videoCount: Int
    var followersCount: Int
    var followingCount: Int

    init(userId: String, data: [String: Any]) {
        self.id = userId
        self.displayName = data["displayName"] as? String ?? "New User"
        self.username = data["username"] as? String
        self.bio = data["bio"] as? String
        if let photoURLString = data["photoURL"] as? String {
            self.photoURL = URL(string: photoURLString)
        }
        self.videoCount = data["videoCount"] as? Int ?? 0
        self.followersCount = data["followersCount"] as? Int ?? 0
        self.followingCount = data["followingCount"] as? Int ?? 0
    }

    static var empty: Profile {
        Profile(userId: "", data: [:])
    }

    static var mock: Profile {
        Profile(
            userId: "mock",
            data: [
                "displayName": "Test User",
                "username": "testuser",
                "bio": "This is a test profile",
                "videoCount": 5,
                "followersCount": 100,
                "followingCount": 50
            ]
        )
    }
}

enum ProfileError: LocalizedError {
    case notAuthenticated
    case invalidData
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User is not authenticated"
        case .invalidData:
            return "Invalid profile data received"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
