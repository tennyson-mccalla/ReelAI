import Foundation

extension UserProfile {
    static var mock: UserProfile {
        return UserProfile(
            id: "mock-id",
            displayName: "Mock User",
            bio: "This is a mock profile used for testing.",
            photoURL: URL(string: "https://example.com/mock.jpg"),
            socialLinks: []
        )
    }
}
