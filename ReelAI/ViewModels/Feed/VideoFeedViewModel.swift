import Foundation
import FirebaseDatabase
import os
import SwiftUI
import Network

@MainActor
class VideoFeedViewModel: ObservableObject {
    @Published private(set) var currentVideo: Video?
    @Published private(set) var previousVideo: Video?
    @Published private(set) var nextVideo: Video?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var networkStatus: NetworkMonitor.NetworkStatus = .unknown
    @Published var transitionProgress: Double = 0

    private var videos: [Video] = []
    private var currentIndex = 0
    private let paginator: FeedPaginator
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReelAI", category: "VideoFeedViewModel")
    private var isPreloadingMore = false
    private let networkMonitor = NetworkMonitor.shared
    private var retryCount = 0
    private let maxRetries = 3

    init(paginator: FeedPaginator? = nil) {
        self.paginator = paginator ?? FeedPaginator()
        setupNetworkMonitoring()
    }

    private func setupNetworkMonitoring() {
        networkMonitor.startMonitoring { [weak self] status in
            guard let self = self else { return }

            Task { @MainActor in
                // Update status and check if we need to load videos
                self.networkStatus = status

                // Only start loading if we have no videos
                let shouldLoad = status == .satisfied && self.videos.isEmpty
                if shouldLoad {
                    await self.loadVideos()
                }
            }
        }
    }

    func loadVideos() async {
        guard networkStatus == .satisfied else {
            error = "No network connection"
            return
        }

        isLoading = true
        error = nil

        do {
            videos = try await fetchVideosWithRetry()
            if !videos.isEmpty {
                currentIndex = 0
                updateVideoViews()
                preloadNextBatchIfNeeded()
            } else {
                error = "No videos found"
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

                // Only retry for network-related errors
                guard error.isRetryableNetworkError else {
                    throw error
                }

                // Exponential backoff
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
                // Retry action
                Task { await self?.loadVideos() }
            },
            fallbackAction: { [weak self] in
                // Fallback action
                self?.error = networkError.localizedDescription
                self?.logger.error("❌ Failed to load videos: \(networkError.localizedDescription)")
            }
        )
    }

    func moveToNext() {
        guard currentIndex < videos.count - 1 else { return }
        currentIndex += 1
        updateVideoViews()
        preloadNextBatchIfNeeded()
    }

    func moveToPrevious() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
        updateVideoViews()
    }

    private func updateVideoViews() {
        currentVideo = videos[currentIndex]
        previousVideo = videos[safe: currentIndex - 1]
        nextVideo = videos[safe: currentIndex + 1]
    }

    private func preloadNextBatchIfNeeded() {
        guard !isPreloadingMore,
              currentIndex >= videos.count - 3,
              !videos.isEmpty,
              networkStatus == .satisfied else { return }

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

    deinit {
        // Avoid capturing self in the deinit Task
        let monitor = networkMonitor
        Task {
            await monitor.stopMonitoring()
        }
    }
}
