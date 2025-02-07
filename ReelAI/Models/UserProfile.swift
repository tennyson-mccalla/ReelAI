import Foundation

struct UserProfile: Codable {
    let id: String
    var displayName: String
    var bio: String
    var photoURL: URL?
    var socialLinks: [SocialLink]

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
