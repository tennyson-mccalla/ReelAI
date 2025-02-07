import Foundation

struct UserProfile: Codable {
    let id: String
    var displayName: String
    var bio: String
    var photoURL: URL?
    var socialLinks: [SocialLink]

    struct SocialLink: Codable, Identifiable {
        let id: String
        var platform: Platform
        var url: String

        enum Platform: String, Codable, CaseIterable {
            case instagram, twitter, tiktok, youtube
        }
    }
}
