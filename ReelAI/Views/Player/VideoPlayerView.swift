import SwiftUI
import AVKit
import os

class PlayerObserver: ObservableObject {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReelAI", category: "PlayerObserver")
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var loadedRangesObserver: NSKeyValueObservation?
    private var player: AVPlayer?
    
    @Published var isReady = false
    @Published var isPreloaded = false
    @Published var bufferingProgress: Double = 0
    
    init(player: AVPlayer, videoId: String) {
        self.player = player
        setupObservers(for: player, videoId: videoId)
    }
    
    private func setupObservers(for player: AVPlayer, videoId: String) {
        statusObserver = player.currentItem?.observe(\.status) { [weak self] item, _ in
            DispatchQueue.main.async {
                if item.status == .readyToPlay {
                    self?.isReady = true
                }
            }
        }
        
        loadedRangesObserver = player.currentItem?.observe(\.loadedTimeRanges) { [weak self] item, _ in
            let duration = item.duration.seconds
            guard duration.isFinite,
                  duration > 0,
                  !duration.isNaN else { return }
            
            let loadedDuration = item.loadedTimeRanges.reduce(0.0) { total, range in
                let timeRange = range.timeRangeValue
                return total + timeRange.duration.seconds
            }
            DispatchQueue.main.async {
                self?.bufferingProgress = loadedDuration / duration
                self?.isPreloaded = loadedDuration / duration >= 0.95
            }
        }
        
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                             object: player.currentItem,
                                             queue: .main) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }
    }
    
    deinit {
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        statusObserver?.invalidate()
        loadedRangesObserver?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}

struct VideoPlayerView: View {
    let video: Video
    let isMuted: Bool
    let isPreloading: Bool
    @StateObject private var observer: PlayerObserver
    private let player: AVPlayer
    
    init(video: Video, isMuted: Bool = false, isPreloading: Bool = false) {
        self.video = video
        self.isMuted = isMuted
        self.isPreloading = isPreloading
        
        let player = AVPlayer(url: video.videoURL)
        player.isMuted = isMuted
        player.actionAtItemEnd = .none
        player.automaticallyWaitsToMinimizeStalling = false
        
        // Preload video if specified
        if isPreloading {
            let item = player.currentItem
            item?.preferredForwardBufferDuration = 10
            player.preroll(atRate: 1) { _ in }
        }
        
        _observer = StateObject(wrappedValue: PlayerObserver(player: player, videoId: video.id))
        self.player = player
    }
    
    var body: some View {
        VideoPlayer(player: player)
            .opacity(observer.isReady ? 1 : 0)
            .overlay {
                if !observer.isReady {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                }
            }
            .onAppear {
                if !isPreloading {
                    player.play()
                }
            }
            .onDisappear {
                player.pause()
                if !isPreloading {
                    player.replaceCurrentItem(with: nil)
                }
            }
            .animation(.easeInOut, value: observer.isReady)
    }
}
