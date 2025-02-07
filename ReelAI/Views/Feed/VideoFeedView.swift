import SwiftUI

struct VideoFeedView: View {
    @StateObject private var viewModel: VideoFeedViewModel
    @State private var lastVideoId: String?
    @Environment(\.scenePhase) private var scenePhase

    init(viewModel: VideoFeedViewModel? = nil) {
        let vm = viewModel ?? VideoFeedViewModel()
        _viewModel = StateObject(wrappedValue: vm)
    }

    private func debugPrint(_ message: String) {
        print(message)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.isLoading && viewModel.videos.isEmpty {
                VStack(spacing: 0) {
                    ForEach(0..<3) { _ in
                        ShimmerView()
                            .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                    }
                }
            } else {
                SnapScrollView(currentIndex: .init(get: {
                    viewModel.videos.firstIndex(where: { $0.id == viewModel.currentlyPlayingId }) ?? 0
                }, set: { newIndex in
                    Task { @MainActor in
                        viewModel.currentlyPlayingId = viewModel.videos[newIndex].id
                    }
                })) {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.videos) { video in
                            VideoPlayerView(
                                videoURL: video.videoURL,
                                videoId: video.id,
                                feedViewModel: viewModel
                            )
                            .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                        }
                    }
                } onSnap: { index in
                    let video = viewModel.videos[index]
                    viewModel.preloader.preloadNextVideo(after: video.id, videos: viewModel.videos)
                }
            }
        }
        .edgesIgnoringSafeArea(.all)
        .onAppear {
            viewModel.loadVideos()
        }
        .onDisappear {
            viewModel.cleanup()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                viewModel.handleBackground()
            case .active:
                viewModel.handleForeground()
            default:
                break
            }
        }
    }

    @ViewBuilder
    private func errorView(_ error: String) -> some View {
        VStack {
            Text(error)
                .foregroundColor(.white)
                .padding()
                .background(Color.black.opacity(0.7))
                .cornerRadius(10)

            Button("Retry") {
                viewModel.reset()
            }
            .foregroundColor(.white)
            .padding()
        }
    }
}

// MARK: - Previews
#Preview("Default") {
    VideoFeedView()
}

#Preview("Loading") {
    VideoFeedView(viewModel: {
        let vm = VideoFeedViewModel()
        vm.setLoading(true)
        return vm
    }())
}

#Preview("Error") {
    VideoFeedView(viewModel: {
        let vm = VideoFeedViewModel()
        vm.setError("Network connection unavailable")
        return vm
    }())
}

// MARK: - Preview Helpers
#if DEBUG
extension VideoFeedViewModel {
    static var mock: VideoFeedViewModel {
        let model = VideoFeedViewModel()
        if let url = URL(string: "https://example.com/1.mp4"),
           let thumbUrl = URL(string: "https://example.com/1.jpg") {
            model.setVideos([
                Video(
                    id: "1",
                    userId: "user1",
                    videoURL: url,
                    thumbnailURL: thumbUrl,
                    createdAt: Date(),
                    caption: "Test video",
                    likes: 0,
                    comments: 0
                )
            ])
        }
        return model
    }
}
#endif
