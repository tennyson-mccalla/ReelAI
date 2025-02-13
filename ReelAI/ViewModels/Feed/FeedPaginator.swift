import Foundation
import FirebaseDatabase
import FirebaseStorage
import os

@MainActor
class FeedPaginator {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReelAI", category: "FeedPaginator")
    private let storage = Storage.storage()
    private let database: DatabaseReference
    private var lastFetchedTimestamp: Date?
    private let batchSize = 10
    private var processedVideoCache: [String: Video] = [:]

    init() {
        self.database = Database.database().reference()
        // Keep videos synced for offline access
        database.child("videos").keepSynced(true)
        logger.debug("🔄 Initialized FeedPaginator with offline sync enabled")
    }

    func fetchNextBatch() async throws -> [Video] {
        logger.debug("📥 Fetching next batch of videos")
        let videosRef = database.child("videos")
        var query = videosRef.queryOrdered(byChild: "timestamp")

        if let lastTimestamp = lastFetchedTimestamp {
            query = query.queryEnding(beforeValue: lastTimestamp.timeIntervalSince1970)
        }

        query = query.queryLimited(toLast: UInt(batchSize))
        query.keepSynced(true)

        let snapshot = try await query.getData()

        guard let value = snapshot.value as? [String: [String: Any]] else {
            if snapshot.value == nil || snapshot.value is NSNull {
                logger.debug("📭 No videos found in database")
                return []
            }
            logger.error("❌ Invalid data structure in Firebase")
            throw NSError(domain: "FeedPaginator",
                         code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "Invalid data structure in Firebase"])
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let processedVideos = try await withThrowingTaskGroup(of: ProcessedVideoResult.self) { group in
            // Only process videos that haven't been cached
            for (key, dict) in value {
                if let cachedVideo = processedVideoCache[key] {
                    group.addTask {
                        return .success(cachedVideo)
                    }
                } else {
                    group.addTask { [weak self] in
                        guard let self = self else {
                            return .skipped(key)
                        }
                        return try await self.processVideoEntry(key: key, dict: dict, decoder: decoder)
                    }
                }
            }

            var videos: [Video] = []
            var skippedVideos: [String] = []

            for try await result in group {
                switch result {
                case .success(let video):
                    videos.append(video)
                    processedVideoCache[video.id] = video
                case .skipped(let videoId):
                    skippedVideos.append(videoId)
                }
            }

            if !skippedVideos.isEmpty {
                logger.warning("⚠️ Skipped \(skippedVideos.count) videos: \(skippedVideos)")
            }

            return videos.sorted { $0.createdAt > $1.createdAt }
        }

        if !processedVideos.isEmpty {
            lastFetchedTimestamp = processedVideos.last?.createdAt
        }

        logger.debug("📼 Fetched \(processedVideos.count) videos")
        return processedVideos
    }

    private enum ProcessedVideoResult {
        case success(Video)
        case skipped(String)
    }

    private func processVideoEntry(key: String, dict: [String: Any], decoder: JSONDecoder) async throws -> ProcessedVideoResult {
        var videoDict = dict
        videoDict["id"] = key

        guard let videoName = videoDict["videoName"] as? String else {
            logger.warning("❌ Missing videoName for video \(key)")
            return .skipped(key)
        }

        do {
            let videoRef = storage.reference().child("videos/\(videoName)")
            let thumbnailName = videoName.hasSuffix(".jpg") ? videoName : videoName.replacingOccurrences(of: ".mp4", with: "") + ".jpg"
            let thumbnailRef = storage.reference().child("thumbnails/\(thumbnailName)")

            // Get URLs serially to prevent concurrent requests
            let url = try await videoRef.downloadURL()
            videoDict["videoURL"] = url.absoluteString

            // Get thumbnail URL
            do {
                let thumbnailURL = try await thumbnailRef.downloadURL()
                videoDict["thumbnailURL"] = thumbnailURL.absoluteString
            } catch {
                videoDict["thumbnailURL"] = nil
            }

            // Ensure timestamp exists and is a number
            if let timestamp = videoDict["timestamp"] as? TimeInterval {
                videoDict["timestamp"] = timestamp
            } else {
                videoDict["timestamp"] = Date().timeIntervalSince1970
            }

            // Add default values for optional fields if missing
            if videoDict["caption"] == nil { videoDict["caption"] = "" }
            if videoDict["likes"] == nil { videoDict["likes"] = 0 }
            if videoDict["comments"] == nil { videoDict["comments"] = 0 }
            if videoDict["isDeleted"] == nil { videoDict["isDeleted"] = false }
            if videoDict["privacyLevel"] == nil { videoDict["privacyLevel"] = "public" }

            let data = try JSONSerialization.data(withJSONObject: videoDict)
            let video = try decoder.decode(Video.self, from: data)
            return .success(video)
        } catch {
            logger.error("❌ Failed to process video \(key): \(error.localizedDescription)")
            return .skipped(key)
        }
    }

    func reset() {
        lastFetchedTimestamp = nil
    }
}
