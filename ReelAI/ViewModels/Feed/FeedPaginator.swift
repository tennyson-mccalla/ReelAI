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
    
    init() {
        self.database = Database.database().reference()
    }
    
    func fetchNextBatch() async throws -> [Video] {
        let videosRef = database.child("videos")
        var query = videosRef.queryOrdered(byChild: "timestamp")
        
        if let lastTimestamp = lastFetchedTimestamp {
            query = query.queryEnding(beforeValue: lastTimestamp.timeIntervalSince1970)
        }
        
        query = query.queryLimited(toLast: UInt(batchSize))
        let snapshot = try await query.getData()
        
        guard let value = snapshot.value as? [String: [String: Any]] else {
            if snapshot.value == nil || snapshot.value is NSNull {
                logger.debug("📭 No videos found in database")
                return []
            }
            throw NSError(domain: "FeedPaginator", 
                         code: 1, 
                         userInfo: [NSLocalizedDescriptionKey: "Invalid data structure in Firebase"])
        }
        
        logger.debug("📦 Processing \(value.count) video entries")
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        
        let processedVideos = try await withThrowingTaskGroup(of: ProcessedVideoResult.self) { group in
            // Spawn tasks
            for (key, dict) in value {
                group.addTask { [weak self] in
                    guard let self = self else { 
                        return .skipped(key) 
                    }
                    return try await self.processVideoEntry(key: key, dict: dict, decoder: decoder)
                }
            }
            
            // Collect results
            var videos: [Video] = []
            var skippedVideos: [String] = []
            
            for try await result in group {
                switch result {
                case .success(let video):
                    videos.append(video)
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
            
            // Check if video exists before attempting to download
            do {
                _ = try await videoRef.getMetadata()
            } catch {
                logger.error("❌ Video \(key) does not exist: \(error.localizedDescription)")
                return .skipped(key)
            }
            
            let url = try await videoRef.downloadURL()
            videoDict["videoURL"] = url.absoluteString
            
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
