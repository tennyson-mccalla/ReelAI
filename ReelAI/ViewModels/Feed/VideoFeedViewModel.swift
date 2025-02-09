import FirebaseDatabase
import AVFoundation

@MainActor
class VideoFeedViewModel: NSObject, ObservableObject {
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

    private let paginator: FeedPaginator
    private let database: DatabaseReference
    private var preloadedVideos: Set<String> = []

    override init() {
        self.database = Database.database().reference()
        self.paginator = FeedPaginator()
        super.init()
    }

    init(database: DatabaseReference = Database.database().reference(),
         paginator: FeedPaginator = .init()) {
        self.database = database
        self.paginator = paginator
        super.init()
    }

    func loadVideos() {
        Task {
            await loadVideosWithRetry()
        }
    }

    private func loadVideosWithRetry(delay: TimeInterval = 1.0) async {
        state.isLoading = true
        state.loadingMessage = "Loading videos..."
        print("📡 Loading videos...")

        do {
            print("📡 Fetching next batch...")
            let videos = try await paginator.fetchNextBatch(from: database)
            print("📡 Got \(videos.count) videos")
            
            guard !videos.isEmpty else {
                state.error = "No videos available"
                state.isLoading = false
                state.loadingMessage = nil
                return
            }
            
            // Shuffle once and store the order
            if state.videos.isEmpty {
                state.videos = videos.shuffled()
                // Set initial playing video
                if currentlyPlayingId == nil {
                    currentlyPlayingId = state.videos.first?.id
                    print("📱 Set initial playing video: \(currentlyPlayingId ?? "none")")
                }
            } else {
                state.videos = videos
            }
            
            state.isLoading = false
            state.loadingMessage = nil
            print("📡 Updated state with videos: \(videos.count) videos available")
            
        } catch {
            print("❌ Load error: \(error)")
            await handleLoadError(error, delay: delay)
        }
    }

    private func handleLoadError(_ error: Error, delay: TimeInterval) async {
        print("❌ Failed to load videos: \(error.localizedDescription)")
        state.error = error.localizedDescription
        state.isLoading = false
        print("❌ Updated state with error")
    }

    func preloadVideo(_ video: Video) async {
        guard !preloadedVideos.contains(video.id) else { return }
        preloadedVideos.insert(video.id)
        print("🎥 Preloading video: \(video.id)")
    }
    
    func cancelPreload(_ videoId: String) {
        preloadedVideos.remove(videoId)
        print("🎥 Cancelled preload for: \(videoId)")
    }

    func cleanup() {
        preloadedVideos.removeAll()
        paginator.cleanup()
    }

    func setLoading(_ isLoading: Bool) {
        state.isLoading = isLoading
    }

    func setError(_ message: String?) {
        state.error = message
    }

    func reset() {
        state = FeedState()
        preloadedVideos.removeAll()
        loadVideos()
    }

    func handleBackground() async {
        print("📱 App entered background")
        // Pause current video if needed
    }

    func handleForeground() async {
        print("📱 App entered foreground")
        // Resume current video if needed
    }
    
    // For previews only
    #if DEBUG
    func setVideos(_ videos: [Video]) {
        state.videos = videos
    }
    #endif
}
