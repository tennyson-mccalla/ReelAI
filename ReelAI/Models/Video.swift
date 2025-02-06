import Foundation
import FirebaseFirestore

struct Video: Identifiable, Codable {
    var id: String?
    let userId: String
    let videoURL: URL
    let thumbnailURL: URL?
    let createdAt: Date

    // Add Firestore document conversion
    init?(document: QueryDocumentSnapshot) {
        let data = document.data()
        guard
            let userId = data["userId"] as? String,
            let videoURLString = data["videoURL"] as? String,
            let videoURL = URL(string: videoURLString),
            let thumbnailURLString = data["thumbnailURL"] as? String,
            let thumbnailURL = URL(string: thumbnailURLString),
            let timestamp = data["timestamp"] as? Timestamp
        else {
            return nil
        }

        self.id = document.documentID
        self.userId = userId
        self.videoURL = videoURL
        self.thumbnailURL = thumbnailURL
        self.createdAt = timestamp.dateValue()
    }

    // Add direct initializer
    init(id: String?, userId: String, videoURL: URL, thumbnailURL: URL?, createdAt: Date) {
        self.id = id
        self.userId = userId
        self.videoURL = videoURL
        self.thumbnailURL = thumbnailURL
        self.createdAt = createdAt
    }

    // Add any other fields your upload is saving
}
