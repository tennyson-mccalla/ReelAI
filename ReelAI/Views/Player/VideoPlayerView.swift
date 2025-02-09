import SwiftUI
import AVKit

struct VideoPlayerView: View {
    let videoURL: URL
    let videoId: String
    let feedViewModel: VideoFeedViewModel
    let isPlaying: Bool
    
    @State private var player: AVPlayer?
    @State private var isLoaded = false
    @State private var playerState = PlayerState()
    @State private var observation: NSKeyValueObservation?
    
    var body: some View {
        GeometryReader { _ in
            ZStack {
                if let player = player, isLoaded {
                    VideoPlayer(player: player)
                        .edgesIgnoringSafeArea(.all)
                        .disabled(true)
                } else {
                    Color.black
                }
                
                // Loading indicator
                if !isLoaded {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                }
            }
            .onAppear {
                print("🎥 VideoPlayerView appeared for \(videoId)")
                if player == nil {
                    setupPlayer()
                }
            }
            .onDisappear {
                print("🎥 VideoPlayerView disappeared for \(videoId)")
                cleanupPlayer()
            }
            .onChange(of: isPlaying) { _, playing in
                handlePlaybackChange(playing)
            }
        }
        .edgesIgnoringSafeArea(.all)
        .background(Color.black)
    }
    
    private func handlePlaybackChange(_ playing: Bool) {
        guard let player = player, isLoaded else {
            print("🎥 Player not ready for playback change on \(videoId)")
            return
        }
        
        if playing {
            print("🎥 Starting playback for \(videoId)")
            player.seek(to: .zero)
            player.play()
            playerState.isPlaying = true
        } else {
            print("🎥 Pausing playback for \(videoId)")
            player.pause()
            playerState.isPlaying = false
        }
    }
    
    private func setupPlayer() {
        print("🎥 Setting up player for \(videoId)")
        
        // Create player and item
        let player = AVPlayer(url: videoURL)
        player.automaticallyWaitsToMinimizeStalling = false
        
        // Store the player first
        self.player = player
        
        // Add observer for loading status
        observation = player.currentItem?.observe(\.status) { item, _ in
            Task { @MainActor in
                switch item.status {
                case .readyToPlay:
                    print("🎥 Player ready for \(videoId)")
                    isLoaded = true
                    if isPlaying {
                        player.play()
                        playerState.isPlaying = true
                    }
                case .failed:
                    print("❌ Player failed for \(videoId): \(String(describing: item.error))")
                default:
                    break
                }
            }
        }
        
        // Enable audio session
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("❌ Failed to set audio session: \(error)")
        }
    }
    
    private func cleanupPlayer() {
        print("🎥 Cleaning up player for \(videoId)")
        player?.pause()
        observation?.invalidate()
        observation = nil
        player = nil
        isLoaded = false
        playerState.isPlaying = false
    }
}
