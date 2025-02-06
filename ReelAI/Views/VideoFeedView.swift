import SwiftUI

struct VideoFeedView: View {
    @StateObject private var viewModel: VideoFeedViewModel
    @State private var lastVideoId: String?

    init(viewModel: VideoFeedViewModel = VideoFeedViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    private func debugPrint(_ message: String) {
        print(message)
    }

    var body: some View {
        GeometryReader { geometry in
            mainContent(geometry)
        }
        .ignoresSafeArea()
        .animation(.smooth, value: viewModel.isLoading)
        .onAppear {
            viewModel.loadVideos()
        }
    }

    @ViewBuilder
    private func mainContent(_ geometry: GeometryProxy) -> some View {
        ZStack {
            videoTabView(geometry)

            if viewModel.isLoading {
                VideoLoadingView(message: viewModel.loadingMessage)
                    .transition(.opacity)
            }

            if let error = viewModel.error {
                errorView(error)
            }
        }
    }

    @ViewBuilder
    private func videoTabView(_ geometry: GeometryProxy) -> some View {
        TabView {
            ForEach(viewModel.videos) { video in
                VideoPlayerView(
                    videoURL: video.videoURL,
                    videoId: video.id ?? "",
                    feedViewModel: viewModel
                ) { isLoading in
                    guard let videoId = video.id else { return }
                    viewModel.trackVideoLoadTime(
                        videoId: videoId,
                        action: isLoading ? "start" : "end"
                    )
                }
                .rotationEffect(.degrees(90))
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.height
                )
                .onAppear {
                    guard let videoId = video.id else { return }
                    debugPrint("Rendering video: \(videoId)")
                    viewModel.trackVideoLoadTime(videoId: videoId, action: "start")
                    viewModel.prefetchVideos(after: videoId)

                    if videoId == viewModel.videos[max(0, viewModel.videos.count - 3)].id {
                        viewModel.loadNextBatch()
                    }

                    if let lastId = lastVideoId {
                        viewModel.updateScrollDirection(from: lastId, to: videoId)
                    }
                    lastVideoId = videoId
                }
                .onDisappear {
                    guard let videoId = video.id else { return }
                    viewModel.trackVideoLoadTime(videoId: videoId, action: "end")
                    viewModel.cleanupCache(keeping: videoId)
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

#Preview {
    VideoFeedView()
}

#Preview("Loading State") {
    let viewModel = VideoFeedViewModel()
    viewModel.isLoading = true
    return VideoFeedView(viewModel: viewModel)
}

#Preview("Error State") {
    let viewModel = VideoFeedViewModel()
    viewModel.error = "Network connection unavailable"
    return VideoFeedView(viewModel: viewModel)
}

#if DEBUG
extension VideoFeedViewModel {
    static var mock: VideoFeedViewModel {
        let model = VideoFeedViewModel()
        if let url = URL(string: "https://example.com/1.mp4"),
           let thumbUrl = URL(string: "https://example.com/1.jpg") {
            model.videos = [
                Video(
                    id: "1",
                    userId: "user1",
                    videoURL: url,
                    thumbnailURL: thumbUrl,
                    createdAt: Date()
                )
            ]
        }
        return model
    }
}
#endif

// Helper extension
extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
