import Foundation
import FirebaseStorage

@MainActor
protocol StorageManager {
    func uploadProfilePhoto(_ data: Data, userId: String) async throws -> URL
    func uploadVideo(_ url: URL, name: String) async throws -> URL
    func uploadThumbnail(_ data: Data, for videoId: String) async throws -> URL
    func getDownloadURL(for path: String) async throws -> URL
    func deleteFile(at path: String) async throws
}
