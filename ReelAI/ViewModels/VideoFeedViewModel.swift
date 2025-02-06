import SwiftUI
import FirebaseStorage
import Network
import FirebaseAuth
import FirebaseDatabase
import AVFoundation
import FirebaseFirestore

class VideoFeedViewModel: ObservableObject {
    @Published var videos: [Video] = []
    @Published var error: String?
    @Published var isLoading = false
    @Published var loadingMessage: String?

    private let db = Database.database().reference()
    private var retryCount = 0
    private let maxRetries = 3
    private var videoLoadStartTime: [String: Date] = [:]
    private let loadingThreshold: TimeInterval = 3.0
    private let batchSize = 5
    private var lastLoadedKey: String?
    private var isLoadingMore = false
    private let urlCache = NSCache<NSString, NSString>()
    private var prefetchQueue = Set<String>()
    private let prefetchLimit = 2
    private let videoCache = NSCache<NSString, AVPlayerItem>()
    private let prefetchTimeout: TimeInterval = 10.0
    private var scrollDirection: ScrollDirection = .none
    private var isLoadingBatch = false
    private var observers: [NSObjectProtocol] = []

    enum ScrollDirection {
        case forward
        case backward
        case none
    }

    init() {
        urlCache.countLimit = 50  // Cache up to 50 video URLs
    }

    func loadVideos() {
        loadVideosWithRetry()
    }

    private func loadVideosWithRetry(delay: TimeInterval = 1.0) {
        DispatchQueue.main.async {
            self.isLoading = true
        }
        print("📡 Attempt \(retryCount + 1) of \(maxRetries + 1) to load videos...")

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }

            if path.status == .satisfied {
                self.fetchVideos()
            } else if self.retryCount < self.maxRetries {
                self.retryCount += 1
                let nextDelay = delay * 2
                DispatchQueue.main.asyncAfter(deadline: .now() + nextDelay) {
                    self.loadVideosWithRetry(delay: nextDelay)
                }
            } else {
                DispatchQueue.main.async {
                    self.error = "Network connection unavailable"
                }
            }
        }
        monitor.start(queue: DispatchQueue.global())
    }

    private func fetchVideos() {
        DispatchQueue.main.async {
            self.isLoading = true
            self.loadingMessage = "Loading feed..."
        }

        let query = db.child("videos")
            .queryOrdered(byChild: "timestamp")
            .queryLimited(toFirst: UInt(batchSize))

        query.observeSingleEvent(of: .value) { [weak self] snapshot, _ in
            guard let self = self else { return }

            guard let videosDict = snapshot.value as? [String: [String: Any]] else {
                print("❌ No videos found or wrong data format")
                return
            }

            Task {
                let loadedVideos = try await self.processVideos(from: videosDict)

                await MainActor.run {
                    print("📱 Updating UI with \(loadedVideos.count) videos")
                    self.videos = loadedVideos
                    self.isLoading = false
                    self.loadingMessage = nil
                }
            }
        }
    }

    private func processVideos(from dict: [String: [String: Any]]) async throws -> [Video] {
        return try await withThrowingTaskGroup(of: Video?.self) { group -> [Video] in
            var videos: [Video] = []

            for (id, data) in dict {
                if let videoName = data["videoName"] as? String {
                    group.addTask {
                        let storage = Storage.storage().reference()
                        let videoRef = storage.child("videos/\(videoName)")
                        let videoURL = try await videoRef.downloadURL()

                        return Video(
                            id: id,
                            userId: data["userId"] as? String ?? "",
                            videoURL: videoURL,
                            thumbnailURL: videoURL,
                            createdAt: (data["timestamp"] as? Timestamp)?.dateValue() ?? Date()
                        )
                    }
                }
            }

            for try await video in group {
                if let video = video {
                    videos.append(video)
                }
            }
            return videos
        }
    }

    func reset() {
        retryCount = 0
        error = nil
        loadVideos()
    }

    func trackVideoLoadTime(videoId: String, action: String) {
        print("🕒 Tracking video \(videoId): \(action)")

        switch action {
        case "start":
            videoLoadStartTime[videoId] = Date()
            DispatchQueue.main.async {
                self.loadingMessage = "Loading video..."
            }
        case "end":
            videoLoadStartTime.removeValue(forKey: videoId)
        default:
            break
        }
    }

    func loadNextBatch() {
        guard !isLoadingMore, !isLoadingBatch else { return }
        isLoadingBatch = true

        let query = db.child("videos")
            .queryOrderedByKey()
            .queryLimited(toFirst: UInt(batchSize))

        if let lastKey = lastLoadedKey {
            _ = query.queryStarting(afterValue: lastKey)
        }

        query.observeSingleEvent(of: .value) { [weak self] snapshot, _ in
            guard let self = self else { return }
            defer { self.isLoadingBatch = false }

            guard let videosDict = snapshot.value as? [String: [String: Any]], !videosDict.isEmpty else {
                print("📭 No more videos to load")
                self.isLoadingMore = false
                return
            }

            Task {
                let loadedVideos = try await self.processVideos(from: videosDict)

                await MainActor.run {
                    if !loadedVideos.isEmpty {
                        self.videos.append(contentsOf: loadedVideos)
                        self.lastLoadedKey = loadedVideos.last?.id
                    }
                    self.isLoadingMore = false
                }
            }
        }
    }

    func prefetchVideos(after currentId: String) {
        guard let currentIndex = videos.firstIndex(where: { $0.id == currentId }) else { return }

        let endIndex = min(currentIndex + prefetchLimit, videos.count)
        let videosToPreload = videos[currentIndex + 1..<endIndex]

        for video in videosToPreload {
            guard let videoId = video.id,
                  !prefetchQueue.contains(videoId),
                  videoCache.object(forKey: videoId as NSString) == nil else {
                continue
            }

            prefetchQueue.insert(videoId)
            print("🔄 Prefetching video: \(videoId)")

            Task {
                do {
                    let asset = AVURLAsset(url: video.videoURL)
                    let playerItem = AVPlayerItem(asset: asset)

                    if #available(iOS 16.0, *) {
                        let isPlayable = try await playerItem.asset.load(.isPlayable)
                        guard isPlayable else { throw NSError(domain: "VideoError", code: -1) }
                    }

                    videoCache.setObject(playerItem, forKey: videoId as NSString)
                    prefetchQueue.remove(videoId)
                    print("✅ Prefetched video: \(videoId)")
                } catch {
                    print("❌ Failed to prefetch: \(error.localizedDescription)")
                    prefetchQueue.remove(videoId)
                }
            }
        }
    }

    func playerItem(for videoId: String) -> AVPlayerItem? {
        if let cachedItem = videoCache.object(forKey: videoId as NSString) {
            print("🎯 Cache hit for video: \(videoId)")
            return AVPlayerItem(asset: cachedItem.asset)
        }

        guard let video = videos.first(where: { $0.id == videoId }) else { return nil }
        print("💿 Cache miss for video: \(videoId)")
        return AVPlayerItem(url: video.videoURL)
    }

    func updateScrollDirection(from oldId: String, to newId: String) {
        guard let oldIndex = videos.firstIndex(where: { $0.id == oldId }),
              let newIndex = videos.firstIndex(where: { $0.id == newId }) else {
            return
        }

        scrollDirection = newIndex > oldIndex ? .forward : .backward
        print("📜 Scroll direction changed to: \(scrollDirection)")
    }

    func cleanupCache(keeping currentId: String) {
        guard let currentIndex = videos.firstIndex(where: { $0.id == currentId }) else { return }

        let cacheWindow = 2

        if scrollDirection != .none {
            let removalIndex = scrollDirection == .forward ?
                max(0, currentIndex - cacheWindow - 1) :
                min(videos.count - 1, currentIndex + cacheWindow + 1)

            if let videoToRemove = videos[safe: removalIndex],
               let videoId = videoToRemove.id {
                videoCache.removeObject(forKey: videoId as NSString)
                print("🗑️ Removed distant video from cache: \(videoId)")
            }
        }

        let prefetchIndex = scrollDirection == .forward ?
            min(videos.count - 1, currentIndex + cacheWindow + 1) :
            max(0, currentIndex - cacheWindow - 1)

        if let videoPrefetch = videos[safe: prefetchIndex],
           let prefetchId = videoPrefetch.id {
            prefetchVideos(after: prefetchId)
        }
    }

    func cleanup() {
        videoCache.removeAllObjects()
        urlCache.removeAllObjects()
        prefetchQueue.removeAll()
        isLoadingMore = false
        isLoadingBatch = false
        scrollDirection = .none
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    deinit {
        cleanup()
    }
}
