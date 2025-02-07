// Video preloading and cache management
// ~80 lines

import AVFoundation
import Foundation  // Add this for Array extension

final class VideoPreloader {
    private let videoCache = NSCache<NSString, AVPlayerItem>()
    private let prefetchLimit = 1  // Only preload next video
    private var prefetchQueue = Set<String>()
    private var scrollDirection: ScrollDirection = .none
    private let prefetchTimeout: TimeInterval = 10.0
    private var videos: [Video] = []

    func playerItem(for videoId: String) -> AVPlayerItem? {
        if let cachedItem = videoCache.object(forKey: videoId as NSString) {
            return AVPlayerItem(asset: cachedItem.asset)
        }
        return nil
    }

    func prefetchVideos(after videoId: String?) {
        guard let videoId = videoId,
              let currentIndex = videos.firstIndex(where: { $0.id == videoId }) else {
            return
        }

        Task {
            await prefetchNextVideos(after: currentIndex)
        }
    }

    private func prefetchNextVideos(after currentIndex: Int) async {
        let endIndex = min(currentIndex + prefetchLimit, videos.count)
        let videosToPreload = videos[currentIndex + 1..<endIndex]

        for video in videosToPreload {
            guard !prefetchQueue.contains(video.id),
                  videoCache.object(forKey: video.id as NSString) == nil else {
                continue
            }

            prefetchQueue.insert(video.id)
            print("🔄 Prefetching video: \(video.id)")

            Task {
                do {
                    let asset = AVURLAsset(url: video.videoURL)
                    if #available(iOS 16.0, *) {
                        let duration = try await asset.load(.duration)
                        print("📏 Video duration: \(duration.seconds) seconds")
                    }
                    let playerItem = AVPlayerItem(asset: asset)
                    playerItem.preferredForwardBufferDuration = 10

                    if #available(iOS 16.0, *) {
                        let isPlayable = try await playerItem.asset.load(.isPlayable)
                        guard isPlayable else { throw NSError(domain: "VideoError", code: -1) }
                    }

                    videoCache.setObject(playerItem, forKey: video.id as NSString)
                    prefetchQueue.remove(video.id)
                    print("✅ Prefetched video: \(video.id)")
                } catch {
                    print("❌ Failed to prefetch: \(error.localizedDescription)")
                    prefetchQueue.remove(video.id)
                }
            }
        }
    }

    func updateScrollDirection(from oldId: String, to newId: String) {
        let oldIndex = videos.firstIndex(where: { $0.id == oldId })
        let newIndex = videos.firstIndex(where: { $0.id == newId })

        guard let oldIndex = oldIndex, let newIndex = newIndex else { return }

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

            if let videoToRemove = videos[safe: removalIndex] {
                videoCache.removeObject(forKey: videoToRemove.id as NSString)
                print("🗑️ Removed distant video from cache: \(videoToRemove.id)")
            }
        }

        let prefetchIndex = scrollDirection == .forward ?
            min(videos.count - 1, currentIndex + cacheWindow + 1) :
            max(0, currentIndex - cacheWindow - 1)

        if let videoPrefetch = videos[safe: prefetchIndex] {
            prefetchVideos(after: videoPrefetch.id)
        }
    }

    func updateVideos(_ newVideos: [Video]) {
        self.videos = newVideos
    }

    func cleanup() {
        videoCache.removeAllObjects()
        prefetchQueue.removeAll()
        scrollDirection = .none
        videos.removeAll()
    }

    func preloadNextVideo(after currentId: String, videos: [Video]) {
        guard let currentIndex = videos.firstIndex(where: { $0.id == currentId }),
              let nextVideo = videos[safe: currentIndex + 1] else {
            return
        }

        Task {
            await prefetchVideo(nextVideo)
        }
    }

    private func prefetchVideo(_ video: Video) async {
        guard !prefetchQueue.contains(video.id) else { return }

        prefetchQueue.insert(video.id)

        do {
            let asset = AVURLAsset(url: video.videoURL)
            let isPlayable = try await asset.load(.isPlayable)  // Store the result
            guard isPlayable else { throw NSError(domain: "VideoError", code: -1) }
            let playerItem = AVPlayerItem(asset: asset)
            videoCache.setObject(playerItem, forKey: video.id as NSString)
            prefetchQueue.remove(video.id)
        } catch {
            prefetchQueue.remove(video.id)
        }
    }
}
