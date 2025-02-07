// Main container view with core player setup
// ~100 lines

import SwiftUI
import AVKit

struct VideoPlayerView: View {
    let videoURL: URL
    let videoId: String
    @ObservedObject var feedViewModel: VideoFeedViewModel
    @StateObject private var playerViewModel: PlayerViewModel
    @State private var playerState = PlayerState()
    let onLoadingStateChanged: (Bool) -> Void

    // Standard tab bar height
    private let tabBarHeight: CGFloat = 49

    init(videoURL: URL,
         videoId: String,
         feedViewModel: VideoFeedViewModel,
         onLoadingStateChanged: @escaping (Bool) -> Void = { _ in }) {
        self.videoURL = videoURL
        self.videoId = videoId
        self.feedViewModel = feedViewModel
        self.onLoadingStateChanged = onLoadingStateChanged
        _playerViewModel = StateObject(wrappedValue: PlayerViewModel())
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let error = playerState.error {
                    PlayerOverlay.ErrorView(
                        error: error,
                        onRetry: { Task { await loadVideo(from: videoURL) }}
                    )
                } else {
                    CustomVideoPlayer(player: playerViewModel.player) {
                        playerState.isPlaying.toggle()
                        if playerState.isPlaying {
                            playerViewModel.player?.play()
                        } else {
                            playerViewModel.player?.pause()
                        }
                    }
                    .ignoresSafeArea(.all)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .onChange(of: feedViewModel.currentlyPlayingId) { _, playingId in
                        if playingId != videoId {
                            playerViewModel.player?.pause()
                            playerViewModel.cleanup()
                        } else {
                            if playerViewModel.player == nil {
                                Task {
                                    await loadVideo(from: videoURL)
                                }
                            } else {
                                playerViewModel.player?.play()
                            }
                        }
                    }

                    PlayerControls(
                        state: $playerState,
                        player: playerViewModel.player
                    )
                    .padding(.bottom, 0)

                    ProgressBar(progress: playerViewModel.progress)
                        .frame(height: 2)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 4)
                }
            }
            .onChange(of: geometry.frame(in: .global).minY) { _, newY in
                let threshold = UIScreen.main.bounds.height * 0.5
                let isFullyVisible = abs(newY) < threshold
                if isFullyVisible && feedViewModel.currentlyPlayingId != videoId {
                    Task { @MainActor in
                        feedViewModel.currentlyPlayingId = videoId
                    }
                }
            }
        }
        .ignoresSafeArea(.all)
        .background(Color.black)
        .onAppear {
            Task {
                await loadVideo(from: videoURL)
            }
        }
        .onChange(of: playerViewModel.player?.status) { _, status in
            if status == .readyToPlay {
                onLoadingStateChanged(false)
            }
        }
        .onDisappear {
            playerViewModel.cleanup()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())  // Make entire area tappable
        .gesture(
            DragGesture(minimumDistance: 20)
                .onChanged { _ in
                    // Optionally pause video during drag
                }
                .onEnded { value in
                    // Handle drag completion if needed
                }
        )
    }

    private func loadVideo(from url: URL) async {
        onLoadingStateChanged(true)

        if tryLoadPrefetchedItem() {
            return
        }

        await loadFromCacheOrNetwork(url: url)
    }

    private func tryLoadPrefetchedItem() -> Bool {
        if let prefetchedItem = feedViewModel.playerItem(for: videoId) {
            print("🎯 Using prefetched video: \(videoId)")
            prefetchedItem.preferredForwardBufferDuration = 10
            prefetchedItem.automaticallyPreservesTimeOffsetFromLive = false
            playerViewModel.loadVideo(playerItem: prefetchedItem)
            playerViewModel.configurePlayback(shouldLoop: true)
            onLoadingStateChanged(false)
            return true
        }
        return false
    }

    private func loadFromCacheOrNetwork(url: URL) async {
        do {
            let cachedURL = try await VideoCacheManager.shared.cacheVideo(
                from: url,
                withIdentifier: url.lastPathComponent
            )
            let asset = AVURLAsset(url: cachedURL)
            let playerItem = AVPlayerItem(asset: asset)
            playerItem.preferredForwardBufferDuration = 10
            playerItem.automaticallyPreservesTimeOffsetFromLive = false
            playerViewModel.loadVideo(playerItem: playerItem)
            playerViewModel.configurePlayback(shouldLoop: true)

            // Load duration after playback starts
            if #available(iOS 16.0, *) {
                Task {
                    let duration = try await asset.load(.duration)
                    print("📏 Loading video duration: \(duration.seconds) seconds")
                }
            }
        } catch {
            print("❌ Video load error: \(error.localizedDescription)")
            playerState.error = error
            onLoadingStateChanged(false)
        }
    }
}
