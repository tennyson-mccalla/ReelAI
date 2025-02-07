import Foundation

struct VideoMetadata {
    let userId: String
    let videoName: String
    let caption: String
    let timestamp: Date
    let thumbnailURL: String?
}

struct VideoUploadResult {
    let videoURL: URL
    let thumbnailURL: URL?
}
