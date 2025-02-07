import Foundation
import FirebaseFirestore

struct Video: Identifiable, Codable {
    let id: String
    let userId: String?
    let videoURL: URL
    let thumbnailURL: URL?
    let createdAt: Date  // This is what we're using for timestamp
    let caption: String
    let likes: Int
    let comments: Int

    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case videoURL
        case thumbnailURL
        case createdAt = "timestamp"  // Map createdAt to timestamp in Firebase
        case caption
        case likes
        case comments
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
    }

    // Add direct initializer
    init(id: String, userId: String?, videoURL: URL, thumbnailURL: URL?, createdAt: Date, caption: String, likes: Int, comments: Int) {
        self.id = id
        self.userId = userId
        self.videoURL = videoURL
        self.thumbnailURL = thumbnailURL
        self.createdAt = createdAt
        self.caption = caption
        self.likes = likes
        self.comments = comments
    }

    // Add any other fields your upload is saving
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
