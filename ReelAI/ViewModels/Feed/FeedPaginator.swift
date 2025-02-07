// Pagination logic and batch loading
// ~80 lines

import FirebaseDatabase
import FirebaseStorage

final class FeedPaginator {
    private let batchSize = 10
    private var retryCount = 0
    private let maxRetries = 3
    private var lastLoadedKey: String?
    private let storage = Storage.storage().reference()

    func fetchNextBatch(from database: DatabaseReference) async throws -> [Video] {
        var query = database.child("videos")
            .queryOrdered(byChild: "timestamp")
            .queryLimited(toFirst: UInt(batchSize))

        if let lastKey = lastLoadedKey {
            query = query.queryStarting(afterValue: nil, childKey: lastKey)
        }

        return try await withCheckedThrowingContinuation { continuation in
            query.observeSingleEvent(of: .value, with: { snapshot in
                guard let videosDict = snapshot.value as? [String: [String: Any]] else {
                    print("❌ No videos found or wrong data format. Raw value: \(String(describing: snapshot.value))")
                    continuation.resume(throwing: NSError(
                        domain: "FeedPaginator",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "No videos found or invalid data format"]
                    ))
                    return
                }

                Task {
                    do {
                        let videos = try await self.processVideos(from: videosDict)
                        if let lastChild = snapshot.children.allObjects.last as? DataSnapshot {
                            self.lastLoadedKey = lastChild.key
                        }
                        continuation.resume(returning: videos)
                    } catch {
                        print("❌ Failed to process videos: \(error)")
                        continuation.resume(throwing: error)
                    }
                }
            })
        }
    }

    private func processVideos(from dict: [String: [String: Any]]) async throws -> [Video] {
        var videos: [Video] = []

        for (id, data) in dict {
            do {
                if let videoName = data["videoName"] as? String,
                   let timestamp = data["timestamp"] as? TimeInterval {

                    let videoRef = storage.child("videos/\(videoName)")
                    let videoURL = try await videoRef.downloadURL()

                    let thumbnailRef = storage.child("thumbnails/\(videoName)")
                    let thumbnailURL = try? await thumbnailRef.downloadURL()

                    let video = Video(
                        id: id,
                        userId: data["userId"] as? String,
                        videoURL: videoURL,
                        thumbnailURL: thumbnailURL,
                        createdAt: Date(timeIntervalSince1970: timestamp / 1000),
                        caption: data["caption"] as? String ?? "",
                        likes: data["likes"] as? Int ?? 0,
                        comments: data["comments"] as? Int ?? 0
                    )
                    videos.append(video)
                } else {
                    print("❌ Missing videoName or timestamp for video \(id)")
                }
            } catch {
                print("❌ Failed to process video \(id): \(error.localizedDescription)")
                continue
            }
        }

        print("📊 Processed \(videos.count) valid videos out of \(dict.count) entries")
        return videos.sorted(by: { $0.createdAt > $1.createdAt })
    }

    func cleanup() {
        retryCount = 0
        lastLoadedKey = nil
    }
}
