// Core feed management and state
// ~100 lines

import FirebaseDatabase
import AVFoundation

@MainActor
final class VideoFeedViewModel: ObservableObject {
    struct FeedState {
        var isLoading = false
        var videos: [Video] = []
        var error: String?
        var loadingMessage: String?
    }

    @Published private(set) var state = FeedState()
    @Published var currentlyPlayingId: String?

    var isLoading: Bool { state.isLoading }
    var videos: [Video] { state.videos }
    var error: String? { state.error }
    var loadingMessage: String? { state.loadingMessage }

    let preloader: VideoPreloader
    private let paginator: FeedPaginator
    private let database: DatabaseReference

    private var lastPlayingId: String?  // Store last playing video

    init(database: DatabaseReference = Database.database().reference(),
         paginator: FeedPaginator = .init(),
         preloader: VideoPreloader = .init()) {
        self.database = database
        self.paginator = paginator
        self.preloader = preloader
    }

    func loadVideos() {
        Task {
            await loadVideosWithRetry()
        }
    }

    private func loadVideosWithRetry(delay: TimeInterval = 1.0) async {
        state.isLoading = true
        print("📡 Loading videos...")

        do {
            print("📡 Fetching next batch...")
            let videos = try await paginator.fetchNextBatch(from: database)
            print("📡 Got \(videos.count) videos")
            await MainActor.run {
                // Shuffle once and store the order
                if state.videos.isEmpty {
                    state.videos = videos.shuffled()
                } else {
                    state.videos = videos
                }
                state.isLoading = false
                state.loadingMessage = nil
                print("📡 Updated state with videos")
            }
            preloader.prefetchVideos(after: videos.first?.id)
        } catch {
            print("❌ Load error: \(error)")
            await handleLoadError(error, delay: delay)
        }
    }

    private func handleLoadError(_ error: Error, delay: TimeInterval) async {
        print("❌ Failed to load videos: \(error.localizedDescription)")
        await MainActor.run {
            state.error = error.localizedDescription
            state.isLoading = false
            print("❌ Updated state with error")
        }
    }

    func playerItem(for videoId: String) -> AVPlayerItem? {
        preloader.playerItem(for: videoId)
    }

    func updateScrollDirection(from oldId: String, to newId: String) {
        preloader.updateScrollDirection(from: oldId, to: newId)
    }

    func cleanupCache(keeping currentId: String) {
        preloader.cleanupCache(keeping: currentId)
    }

    func cleanup() {
        preloader.cleanup()
        paginator.cleanup()
    }

    // Add these methods for controlled state modification
    func setLoading(_ isLoading: Bool) {
        state.isLoading = isLoading
    }

    func setError(_ message: String?) {
        state.error = message
    }

    func trackVideoLoadTime(videoId: String, action: String) {
        // Implementation
    }

    func reset() {
        state = FeedState()
        loadVideos()
    }

    func prefetchVideos(after videoId: String?) {
        preloader.prefetchVideos(after: videoId)
    }

    func setVideos(_ newVideos: [Video]) {
        state.videos = newVideos
    }

    func loadNextBatch() {
        Task {
            await loadVideosWithRetry()
        }
    }

    func handleBackground() {
        if let currentId = currentlyPlayingId {
            lastPlayingId = currentId  // Remember which video was playing
            currentlyPlayingId = nil
        }
    }

    func handleForeground() {
        if let lastId = lastPlayingId {
            print("🔄 Resuming video: \(lastId)")
            Task { @MainActor in
                currentlyPlayingId = lastId
                lastPlayingId = nil
            }
        }
    }
}
