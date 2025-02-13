import Foundation
import FirebaseStorage

protocol StorageManager {
    func uploadProfilePhoto(_ data: Data, userId: String) async throws -> URL
    func uploadVideo(_ url: URL, name: String, progressHandler: @escaping (Double) -> Void) async throws -> URL
    func uploadThumbnail(_ data: Data, for videoId: String) async throws -> URL
    func getDownloadURL(for path: String) async throws -> URL
    func deleteFile(at path: String) async throws
    func cancelUpload(for url: URL)
}
