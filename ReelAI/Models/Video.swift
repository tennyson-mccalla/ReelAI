import Foundation
import FirebaseFirestore

struct Video: Identifiable, Codable, Hashable {
    let id: String
    let userId: String?
    let videoURL: URL
    let thumbnailURL: URL?
    let createdAt: Date
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
        case createdAt = "timestamp"
        case caption
        case likes
        case comments
        case isDeleted
        case privacyLevel
        case lastEditedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decodeIfPresent(String.self, forKey: .userId)
        
        // Handle video URL
        let videoURLString = try container.decode(String.self, forKey: .videoURL)
        guard let videoURL = URL(string: videoURLString) else {
            throw DecodingError.dataCorruptedError(forKey: .videoURL,
                  in: container,
                  debugDescription: "Invalid URL string: \(videoURLString)")
        }
        self.videoURL = videoURL
        
        // Handle optional thumbnail URL
        if let thumbnailURLString = try container.decodeIfPresent(String.self, forKey: .thumbnailURL) {
            self.thumbnailURL = URL(string: thumbnailURLString)
        } else {
            self.thumbnailURL = nil
        }
        
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        caption = try container.decodeIfPresent(String.self, forKey: .caption) ?? ""
        likes = try container.decodeIfPresent(Int.self, forKey: .likes) ?? 0
        comments = try container.decodeIfPresent(Int.self, forKey: .comments) ?? 0
        isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        privacyLevel = try container.decodeIfPresent(PrivacyLevel.self, forKey: .privacyLevel) ?? .public
        lastEditedAt = try container.decodeIfPresent(Date.self, forKey: .lastEditedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(videoURL.absoluteString, forKey: .videoURL)
        try container.encode(thumbnailURL?.absoluteString, forKey: .thumbnailURL)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(caption, forKey: .caption)
        try container.encode(likes, forKey: .likes)
        try container.encode(comments, forKey: .comments)
        try container.encode(isDeleted, forKey: .isDeleted)
        try container.encode(privacyLevel, forKey: .privacyLevel)
        try container.encode(lastEditedAt, forKey: .lastEditedAt)
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
