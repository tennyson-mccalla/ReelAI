import SwiftUI

struct VideoFeedView: View {
    @StateObject private var feedViewModel = VideoFeedViewModel()
    
    var body: some View {
        TabView {
            ForEach(feedViewModel.videos) { video in
                VideoPlayerView(videoURL: video.url)
                    .rotationEffect(.degrees(90)) // Portrait mode
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onAppear {
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
    
    func loadVideos() {
        // TODO: Implement Firebase fetch
        // This will be connected to your Firebase backend
        // For now, we can test with local videos
    }
} 