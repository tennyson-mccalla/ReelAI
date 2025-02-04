import SwiftUI
import AVKit

struct VideoPlayerView: View {
    let videoURL: URL
    @StateObject private var playerViewModel = VideoPlayerViewModel()
    
    var body: some View {
        ZStack {
            VideoPlayer(player: playerViewModel.player)
                .edgesIgnoringSafeArea(.all)
                .onAppear {
                    playerViewModel.loadVideo(url: videoURL)
                }
                .onDisappear {
                    playerViewModel.cleanup()
                }
            
            // Overlay controls can be added here later
        }
    }
}

class VideoPlayerViewModel: ObservableObject {
    @Published var player: AVPlayer?
    
    func loadVideo(url: URL) {
        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        player?.play()
        
        // Loop video
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            self?.player?.seek(to: .zero)
            self?.player?.play()
        }
    }
    
    func cleanup() {
        player?.pause()
        player = nil
    }
} 