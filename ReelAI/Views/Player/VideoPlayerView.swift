import SwiftUI
import AVKit
import os

class PlayerObserver: ObservableObject {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReelAI", category: "PlayerObserver")
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var loadedRangesObserver: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?
    private var player: AVPlayer?
    private let isPreloading: Bool
    private var hasStartedPlaying = false
    private let videoId: String

    @Published var isReady = false
    @Published var isPreloaded = false
    @Published var bufferingProgress = 0.0
    @Published var isActive = false
    @Published var isPlaying = false

    init(player: AVPlayer, videoId: String, isPreloading: Bool) {
        self.player = player
        self.videoId = videoId
        self.isPreloading = isPreloading

        // Configure player for better stall handling
        player.automaticallyWaitsToMinimizeStalling = true
        player.actionAtItemEnd = .none

        // Configure AVPlayerItem
        if let playerItem = player.currentItem {
            playerItem.preferredForwardBufferDuration = 5
            playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true

            // Add stall handling
            NotificationCenter.default.addObserver(
                forName: AVPlayerItem.playbackStalledNotification,
                object: playerItem,
                queue: .main
            ) { [weak self] _ in
                guard let self = self else { return }
                self.logger.debug("⚠️ Playback stalled, attempting recovery")
                self.handleStall()
            }
        }

        setupObservers(for: player, videoId: videoId)
        logger.debug("🎬 Initializing PlayerObserver for video: \(videoId)")
    }

    func activate() {
        guard !isActive else { return }
        isActive = true
        logger.debug("🎯 Activating player for video: \(self.videoId)")
        if isReady && !isPreloading {
            player?.seek(to: .zero)
            player?.play()
            logger.debug("▶️ Play command sent for: \(self.videoId)")
        }
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        logger.debug("⏸️ Deactivating player for video: \(self.videoId)")
        player?.pause()
        if !isPreloading {
            player?.replaceCurrentItem(with: nil)
        }
    }

    private func handleStall() {
        guard let player = self.player,
              !isPreloading,
              isActive else { return }

        // Try to recover from stall
        let currentTime = player.currentTime()
        player.pause()
        player.seek(to: currentTime) { [weak self] completed in
            guard let self = self,
                  self.isActive,
                  self.isReady,
                  completed else { return }
            player.play()
            self.logger.debug("⚠️ Recovered from stall for: \(self.videoId)")
        }
    }

    private func setupObservers(for player: AVPlayer, videoId: String) {
        // Observe playback rate
        rateObserver = player.observe(\.rate) { [weak self] player, _ in
            guard let self = self else { return }
            Task { @MainActor in
                let wasPlaying = self.isPlaying
                self.isPlaying = player.rate > 0
                // Only log when state actually changes
                if wasPlaying != self.isPlaying {
                    self.logger.debug("\(self.isPlaying ? "▶️" : "⏸️") Playback \(self.isPlaying ? "started" : "paused") for: \(self.videoId)")
                }
            }
        }

        // Observe playback buffer
        loadedRangesObserver = player.currentItem?.observe(\.loadedTimeRanges) { [weak self] item, _ in
            guard let self = self else { return }
            let duration = item.duration.seconds
            guard duration.isFinite, duration > 0, !duration.isNaN else { return }

            let loadedDuration = item.loadedTimeRanges.reduce(0.0) { total, range in
                let timeRange = range.timeRangeValue
                return total + timeRange.duration.seconds
            }

            Task { @MainActor in
                self.bufferingProgress = loadedDuration / duration
                self.isPreloaded = loadedDuration / duration >= 0.3

                // Start playback when enough is buffered
                if self.isPreloaded && !self.hasStartedPlaying && !self.isPreloading && self.isActive {
                    self.hasStartedPlaying = true
                    player.seek(to: .zero)
                    player.play()
                }
            }
        }

        // Observe player status
        statusObserver = player.currentItem?.observe(\.status) { [weak self] item, _ in
            guard let self = self else { return }
            Task { @MainActor in
                switch item.status {
                case .readyToPlay:
                    self.isReady = true
                    if !self.isPreloading && !self.hasStartedPlaying && self.isActive {
                        player.play()
                    }
                case .failed:
                    self.logger.error("❌ Player failed for \(self.videoId): \(String(describing: item.error))")
                default:
                    break
                }
            }
        }

        // Add periodic time observer - only for stall detection
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            // Keep observer for stall detection but remove logging
        }

        // Handle end of video
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, !self.isPreloading, self.isActive else { return }
            player.seek(to: .zero)
            player.play()
        }
    }

    deinit {
        deactivate()
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        statusObserver?.invalidate()
        loadedRangesObserver?.invalidate()
        rateObserver?.invalidate()
        NotificationCenter.default.removeObserver(self)
        logger.debug("🗑️ Observer deallocated for: \(self.videoId)")
    }
}

struct VideoPlayerView: View {
    let video: Video
    let isMuted: Bool
    let isPreloading: Bool
    @StateObject private var observer: PlayerObserver
    private let player: AVPlayer
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReelAI", category: "VideoPlayerView")

    init(video: Video, isMuted: Bool = false, isPreloading: Bool = false) {
        self.video = video
        self.isMuted = isMuted
        self.isPreloading = isPreloading

        // Create and configure player
        let player = AVPlayer(url: video.videoURL)
        player.isMuted = isMuted

        // Set explicit playback parameters
        player.allowsExternalPlayback = false
        player.preventsDisplaySleepDuringVideoPlayback = true

        // Enable background audio
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)

        self.player = player
        _observer = StateObject(wrappedValue: PlayerObserver(player: player, videoId: video.id, isPreloading: isPreloading))
    }

    var body: some View {
        ZStack {
            Color.black
                .edgesIgnoringSafeArea(.all)

            VideoPlayerControllerRepresentable(player: player, onTap: {
                logger.debug("👆 Tap detected, isPlaying: \(observer.isPlaying)")
                if observer.isPlaying {
                    logger.debug("⏸️ Attempting to pause")
                    player.pause()
                } else {
                    logger.debug("▶️ Attempting to play")
                    player.play()
                }
            })
            .opacity(observer.isReady ? 1 : 0)
            .overlay {
                if !observer.isReady {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                }
            }
        }
        .onAppear {
            observer.activate()
        }
        .onDisappear {
            observer.deactivate()
        }
    }
}

struct VideoPlayerControllerRepresentable: UIViewControllerRepresentable {
    let player: AVPlayer
    let onTap: () -> Void

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill
        controller.view.backgroundColor = .black

        // Ensure video layer is properly configured
        if let playerLayer = controller.view.layer as? AVPlayerLayer {
            playerLayer.videoGravity = .resizeAspectFill
        }

        // Add tap gesture recognizer
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        controller.view.addGestureRecognizer(tapGesture)

        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // Update if needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    class Coordinator: NSObject {
        let onTap: () -> Void

        init(onTap: @escaping () -> Void) {
            self.onTap = onTap
        }

        @objc func handleTap() {
            onTap()
        }
    }
}
