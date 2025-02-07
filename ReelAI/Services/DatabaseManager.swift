import Foundation
import FirebaseDatabase

protocol DatabaseManager {
    func updateProfile(_ profile: UserProfile) async throws
    func fetchProfile(userId: String) async throws -> UserProfile
    func updateVideo(_ video: Video) async throws
    func deleteVideo(id: String) async throws
    func fetchVideos(limit: Int, after key: String?) async throws -> [Video]
    // ... other methods
}
