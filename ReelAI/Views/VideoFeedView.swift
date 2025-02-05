import SwiftUI
import FirebaseStorage
import Network
import FirebaseAuth
import FirebaseDatabase

struct VideoFeedView: View {
    @StateObject private var feedViewModel = VideoFeedViewModel()

    private func debugPrint(_ message: String) {
        print(message)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                TabView {
                    ForEach(feedViewModel.videos) { video in
                        VideoPlayerView(videoURL: video.url)
                            .rotationEffect(.degrees(90))
                            .frame(
                                width: geometry.size.width,
                                height: geometry.size.height
                            )
                            .onAppear {
                                debugPrint("Rendering video: \(video.id)")
                            }
                    }
                }
                .frame(
                    width: geometry.size.height,
                    height: geometry.size.width
                )
                .rotationEffect(.degrees(-90))
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.height
                )
                .tabViewStyle(.page(indexDisplayMode: .never))
                .background(Color.black)
                .onAppear {
                    debugPrint("""
                        VideoFeedView body called
                        GeometryReader size: \(geometry.size)
                        """)
                }

                if let error = feedViewModel.error {
                    VStack {
                        Text(error)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(10)

                        Button("Retry") {
                            feedViewModel.reset()
                        }
                        .foregroundColor(.white)
                        .padding()
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            // For testing, let's add a sample video
            feedViewModel.loadVideos()
        }
    }
}

struct Video: Identifiable {
    let id: String
    let url: URL
    // Add more metadata as needed
}

class VideoFeedViewModel: ObservableObject {
    @Published var videos: [Video] = []
    @Published var error: String?
    private let db = Database.database().reference()
    private var retryCount = 0
    private let maxRetries = 3

    func loadVideos() {
        loadVideosWithRetry()
    }

    private func loadVideosWithRetry(delay: TimeInterval = 1.0) {
        print("📡 Attempt \(retryCount + 1) of \(maxRetries + 1) to load videos...")

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            print("🌐 Network status: \(path.status)")
            print("🌐 Network available: \(path.status == .satisfied)")

            if path.status == .satisfied {
                self.fetchVideos()
            } else if self.retryCount < self.maxRetries {
                self.retryCount += 1
                let nextDelay = delay * 2 // Exponential backoff
                print("⏳ Retrying in \(nextDelay) seconds...")
                DispatchQueue.main.asyncAfter(deadline: .now() + nextDelay) {
                    self.loadVideosWithRetry(delay: nextDelay)
                }
            } else {
                print("❌ Failed to connect after \(self.maxRetries + 1) attempts")
                DispatchQueue.main.async {
                    self.error = "Network connection unavailable"
                }
            }
        }
        monitor.start(queue: DispatchQueue.global())
    }

    private func fetchVideos() {
        print("📡 Fetching videos using Firebase Realtime DB")
        db.child("videos")
            .queryOrdered(byChild: "timestamp")
            .observe(.value) { [weak self] snapshot in
                guard let self = self else { return }

                guard let videosDict = snapshot.value as? [String: [String: Any]] else {
                    print("❌ No videos found or wrong data format")
                    return
                }

                print("📄 Got videos: \(videosDict.count)")

                Task {
                    let loadedVideos: [Video] = try await withThrowingTaskGroup(of: Video?.self) { group -> [Video] in
                        var videos: [Video] = []

                        for (id, data) in videosDict {
                            if let videoName = data["videoName"] as? String {
                                group.addTask {
                                    print("🔄 Fetching URL for video: \(videoName)")
                                    let storage = Storage.storage().reference()
                                    let videoRef = storage.child("videos/\(videoName)")
                                    if let url = try? await videoRef.downloadURL() {
                                        print("✅ Got URL for video: \(videoName)")
                                        return Video(id: id, url: url)
                                    }
                                    print("❌ Failed to get URL for video: \(videoName)")
                                    return nil
                                }
                            }
                        }

                        for try await video in group {
                            if let video = video {
                                videos.append(video)
                                print("➕ Added video to list: \(video.id)")
                            }
                        }
                        return videos
                    }

                    await MainActor.run {
                        print("📱 Updating UI with \(loadedVideos.count) videos")
                        self.videos = loadedVideos.shuffled()
                    }
                }
            }
    }

    func reset() {
        retryCount = 0
        error = nil
        loadVideos()
    }
}
