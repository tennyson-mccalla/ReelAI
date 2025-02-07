import Foundation
import FirebaseFirestore

struct Video: Identifiable, Codable, Hashable {
    let id: String
    let userId: String?
    let videoURL: URL
    let thumbnailURL: URL?
    let createdAt: Date  // This is what we're using for timestamp
    var caption: String
    var likes: Int
    var comments: Int
    var isDeleted: Bool
    var privacyLevel: PrivacyLevel
    var lastEditedAt: Date?

    enum PrivacyLevel: String, Codable, CaseIterable {
        case `public`
        case `private`
        case friendsOnly

        var displayName: String {
            switch self {
            case .public: return "Public"
            case .private: return "Private"
            case .friendsOnly: return "Friends Only"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case videoURL
        case thumbnailURL
        case createdAt = "timestamp"  // Map createdAt to timestamp in Firebase
        case caption
        case likes
        case comments
        case isDeleted
        case privacyLevel
        case lastEditedAt
    }

    // Custom encoding to handle Date conversion for Firebase
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(videoURL.absoluteString, forKey: .videoURL)
        try container.encode(thumbnailURL?.absoluteString, forKey: .thumbnailURL)
        // Convert Date to milliseconds timestamp for Firebase
        try container.encode(Int(createdAt.timeIntervalSince1970 * 1000), forKey: .createdAt)
        try container.encode(caption, forKey: .caption)
        try container.encode(likes, forKey: .likes)
        try container.encode(comments, forKey: .comments)
        try container.encode(isDeleted, forKey: .isDeleted)
        try container.encode(privacyLevel, forKey: .privacyLevel)
        try container.encode(lastEditedAt?.timeIntervalSince1970, forKey: .lastEditedAt)
    }

    // Custom decoding to handle Firebase timestamp
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decode(String?.self, forKey: .userId)
        let videoURLString = try container.decode(String.self, forKey: .videoURL)
        guard let videoURL = URL(string: videoURLString) else {
            throw DecodingError.dataCorruptedError(forKey: .videoURL, in: container, debugDescription: "Invalid URL string")
        }
        self.videoURL = videoURL

        if let thumbnailURLString = try container.decodeIfPresent(String.self, forKey: .thumbnailURL) {
            thumbnailURL = URL(string: thumbnailURLString)
        } else {
            thumbnailURL = nil
        }

        // Handle timestamp from Firebase (milliseconds)
        let timestamp = try container.decode(Int.self, forKey: .createdAt)
        createdAt = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)

        caption = try container.decode(String.self, forKey: .caption)
        likes = try container.decode(Int.self, forKey: .likes)
        comments = try container.decode(Int.self, forKey: .comments)
        isDeleted = try container.decode(Bool.self, forKey: .isDeleted)
        privacyLevel = try container.decode(PrivacyLevel.self, forKey: .privacyLevel)
        lastEditedAt = try container.decode(Date?.self, forKey: .lastEditedAt)
    }

    // Add direct initializer
    init(id: String, userId: String?, videoURL: URL, thumbnailURL: URL?, createdAt: Date, caption: String, likes: Int, comments: Int, isDeleted: Bool = false, privacyLevel: PrivacyLevel = .public, lastEditedAt: Date? = nil) {
        self.id = id
        self.userId = userId
        self.videoURL = videoURL
        self.thumbnailURL = thumbnailURL
        self.createdAt = createdAt
        self.caption = caption
        self.likes = likes
        self.comments = comments
        self.isDeleted = isDeleted
        self.privacyLevel = privacyLevel
        self.lastEditedAt = lastEditedAt
    }

    // Add any other fields your upload is saving

    // Add hash function
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // Add equality check
    static func == (lhs: Video, rhs: Video) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Preview Helpers
#if DEBUG
extension Video {
    static var mock: Video {
        Video(
            id: "mock-id",
            userId: "mock-user",
            videoURL: URL(string: "https://example.com/video.mp4") ?? URL(fileURLWithPath: ""),
            thumbnailURL: URL(string: "https://example.com/thumb.jpg"),
            createdAt: Date(),
            caption: "Mock video",
            likes: 42,
            comments: 7
        )
    }
}
#endif
