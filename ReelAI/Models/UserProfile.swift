import Foundation

struct UserProfile: Codable, Identifiable {
    let id: String
    var displayName: String
    var bio: String
    var photoURL: URL?
    var socialLinks: [SocialLink]

    private enum CodingKeys: String, CodingKey {
        case id, displayName, bio, photoURL, socialLinks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)

        // Handle optional fields with defaults
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? "New User"
        bio = try container.decodeIfPresent(String.self, forKey: .bio) ?? ""
        photoURL = try container.decodeIfPresent(URL.self, forKey: .photoURL)
        socialLinks = try container.decodeIfPresent([SocialLink].self, forKey: .socialLinks) ?? []
    }

    init(id: String, displayName: String, bio: String = "", photoURL: URL? = nil, socialLinks: [SocialLink] = []) {
        self.id = id
        self.displayName = displayName
        self.bio = bio
        self.photoURL = photoURL
        self.socialLinks = socialLinks
    }

    struct SocialLink: Codable, Identifiable {
        var id: String { platform }
        let platform: String
        var url: String

        static let supportedPlatforms = [
            "Instagram",
            "Twitter",
            "TikTok",
            "YouTube"
        ]
    }
}

enum Platform: String, Codable, CaseIterable {
    case instagram, twitter, tiktok, youtube
}
