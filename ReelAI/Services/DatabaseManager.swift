import Foundation

protocol DatabaseManager {
    func updateProfile(_ profile: UserProfile) async throws
    func fetchProfile(userId: String) async throws -> UserProfile
    func updateVideo(_ video: Video) async throws
    func deleteVideo(id: String) async throws
    func fetchVideos(limit: Int, after key: String?) async throws -> [Video]
    func softDeleteVideo(_ videoId: String) async throws
    func restoreVideo(_ videoId: String) async throws
    func updateVideoPrivacy(_ videoId: String, privacyLevel: Video.PrivacyLevel) async throws
    func updateVideoMetadata(_ videoId: String, caption: String) async throws
}
