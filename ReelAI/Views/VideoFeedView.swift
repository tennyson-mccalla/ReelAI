import SwiftUI

struct VideoFeedView: View {
    @StateObject private var feedViewModel = VideoFeedViewModel()

    var body: some View {
        GeometryReader { geometry in
            TabView {
                ForEach(feedViewModel.videos) { video in
                    VideoPlayerView(videoURL: video.url)
                        // Rotate each video view individually
                        .rotationEffect(.degrees(90))
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height
                        )
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
        .ignoresSafeArea()
        .onAppear {
            // For testing, let's add a sample video
            feedViewModel.loadTestVideo()
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

    func loadTestVideo() {
        let videoURLs = [
            "https://firebasestorage.googleapis.com/v0/b/reelai-a3565.firebasestorage.app/o/videos%2F26E6C92C-7491-4F83-BD47-FCCE49528143.mp4?alt=media",
            "https://firebasestorage.googleapis.com/v0/b/reelai-a3565.firebasestorage.app/o/videos%2F6A1FF63B-1C01-4BA2-A304-F47DD69A3491.mp4?alt=media"
        ]

        videos = videoURLs.enumerated().compactMap { index, urlString in
            guard let url = URL(string: urlString) else { return nil }
            return Video(id: "\(index + 1)", url: url)
        }
    }
}
