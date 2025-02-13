import Foundation
import FirebaseDatabase
import os
import SwiftUI

@MainActor
class VideoFeedViewModel: ObservableObject {
    @Published private(set) var currentVideo: Video?
    @Published private(set) var previousVideo: Video?
    @Published private(set) var nextVideo: Video?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published var transitionProgress: Double = 0

    private var videos: [Video] = []
    private var currentIndex = 0
    private let paginator: FeedPaginator
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReelAI", category: "VideoFeedViewModel")
    private var isPreloadingMore = false
    private var retryCount = 0
    private let maxRetries = 3
    private let initialVideo: Video?

    init(paginator: FeedPaginator? = nil, initialVideo: Video? = nil) {
        self.paginator = paginator ?? FeedPaginator()
        self.initialVideo = initialVideo
        Task {
            await loadVideos()
        }
    }

    func loadVideos() async {
        guard !isLoading else { return }

        isLoading = true
        error = nil

        do {
            videos = try await fetchVideosWithRetry()

            if let initialVideo = initialVideo {
                if let index = videos.firstIndex(where: { $0.id == initialVideo.id }) {
                    currentIndex = index
                } else {
                    videos.insert(initialVideo, at: 0)
                    currentIndex = 0
                }
            } else if !videos.isEmpty {
                currentIndex = 0
            }

            updateVideoViews()
            preloadNextBatchIfNeeded()

            if videos.isEmpty {
                error = "No videos available"
            }
        } catch {
            handleLoadError(error)
        }

        isLoading = false
    }

    private func fetchVideosWithRetry() async throws -> [Video] {
        var lastError: Error?

        for attempt in 0..<maxRetries {
            do {
                return try await paginator.fetchNextBatch()
            } catch {
                lastError = error
                guard error.isRetryableNetworkError else {
                    throw error
                }
                try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt)) * 1_000_000_000))
            }
        }

        throw lastError ?? NSError(domain: "VideoFeedError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch videos"])
    }

    private func handleLoadError(_ error: Error) {
        let networkError = error as NSError
        NetworkErrorHandler.handle(
            error,
            retryAction: { [weak self] in
                Task { await self?.loadVideos() }
            },
            fallbackAction: { [weak self] in
                self?.error = networkError.localizedDescription
                self?.logger.error("❌ Failed to load videos: \(networkError.localizedDescription)")
            }
        )
    }

    private func updateVideoViews() {
        guard !videos.isEmpty else { return }
        currentIndex = max(0, min(currentIndex, videos.count - 1))
        currentVideo = videos[currentIndex]
        previousVideo = currentIndex > 0 ? videos[currentIndex - 1] : nil
        nextVideo = currentIndex < videos.count - 1 ? videos[currentIndex + 1] : nil

        if let next = nextVideo {
            preloadVideo(next)
        }
    }

    func moveToNextVideo() {
        guard currentIndex < videos.count - 1 else { return }
        currentIndex += 1
        updateVideoViews()
    }

    func moveToPreviousVideo() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
        updateVideoViews()
    }

    private func preloadNextBatchIfNeeded() {
        guard !isPreloadingMore,
              currentIndex >= videos.count - 3,
              !videos.isEmpty else { return }

        Task {
            isPreloadingMore = true
            do {
                let newVideos = try await fetchVideosWithRetry()
                if !newVideos.isEmpty {
                    videos.append(contentsOf: newVideos)
                    updateVideoViews()
                }
            } catch {
                logger.error("❌ Failed to preload next batch: \(error.localizedDescription)")
            }
            isPreloadingMore = false
        }
    }

    private func preloadVideo(_ video: Video) {
        // Implementation of preloadVideo method
    }
}
