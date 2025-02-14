import SwiftUI
import AVKit
import os

@MainActor
final class PlayerObserver: ObservableObject {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReelAI", category: "PlayerObserver")
    private var statusObserver: NSKeyValueObservation?
    private var loadedRangesObserver: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?
    private var player: AVPlayer?
    private let isPreloading: Bool
    private var hasStartedPlaying = false
    private let videoId: String
    private var notificationObserver: NSObjectProtocol?

    @Published var isReady = false
    @Published var isPreloaded = false
    @Published var bufferingProgress = 0.0
    @Published var isActive = false
    @Published var isPlaying = false

    // Capture struct for thread-safe state passing
    private struct PlaybackState {
        let isActive: Bool
        let isReady: Bool
        let videoId: String
    }

    init(player: AVPlayer, videoId: String, isPreloading: Bool) {
        self.player = player
        self.videoId = videoId
        self.isPreloading = isPreloading

        // Configure player for better stall handling
        player.automaticallyWaitsToMinimizeStalling = true
        player.actionAtItemEnd = .none

        if let playerItem = player.currentItem {
            playerItem.preferredForwardBufferDuration = 5
            playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true

            // Handle stall notification on main actor
            notificationObserver = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.playbackStalledNotification,
                object: playerItem,
                queue: .main
            ) { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor in
                    await self.handleStall()
                }
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

    // MARK: - Stall Handling
    private func handleStall() async {
        guard let currentPlayer = player,
              !isPreloading,
              isActive else { return }

        // Capture current state
        let state = PlaybackState(
            isActive: isActive,
            isReady: isReady,
            videoId: self.videoId
        )

        // Perform stall recovery
        await handleStallRecovery(currentPlayer, state: state)
    }

    private nonisolated func handleStallRecovery(_ player: AVPlayer, state: PlaybackState) async {
        let currentTime = player.currentTime()
        player.pause()

        let completed = await withCheckedContinuation { continuation in
            player.seek(to: currentTime) { completed in
                continuation.resume(returning: completed)
            }
        }

        if completed {
            await resumePlayback(player, state: state)
        }
    }

    @MainActor
    private func resumePlayback(_ player: AVPlayer, state: PlaybackState) async {
        guard isActive, isReady else { return }
        player.play()
        logger.debug("⚠️ Recovered from stall for: \(self.videoId)")
    }

    private func setupObservers(for player: AVPlayer, videoId: String) {
        // Observe playback rate
        rateObserver = player.observe(\.rate) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let wasPlaying = self.isPlaying
                self.isPlaying = player.rate > 0
                if wasPlaying != self.isPlaying {
                    self.logger.debug("\(self.isPlaying ? "▶️" : "⏸️") Playback \(self.isPlaying ? "started" : "paused") for: \(self.videoId)")
                }
            }
        }

        // Observe playback buffer
        loadedRangesObserver = player.currentItem?.observe(\.loadedTimeRanges) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let duration = item.duration.seconds
                guard duration.isFinite, duration > 0, !duration.isNaN else { return }

                let loadedDuration = item.loadedTimeRanges.reduce(0.0) { total, range in
                    let timeRange = range.timeRangeValue
                    return total + timeRange.duration.seconds
                }

                self.bufferingProgress = loadedDuration / duration
                self.isPreloaded = loadedDuration / duration >= 0.3

                if self.isPreloaded && !self.hasStartedPlaying && !self.isPreloading && self.isActive {
                    self.hasStartedPlaying = true
                    player.seek(to: .zero)
                    player.play()
                }
            }
        }

        // Observe player status
        statusObserver = player.currentItem?.observe(\.status) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
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

        // Handle end of video
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self,
                      !self.isPreloading,
                      self.isActive,
                      let player = self.player else { return }
                player.seek(to: .zero)
                player.play()
            }
        }
    }

    // MARK: - Lifecycle
    deinit {
        // Log before cleanup
        logger.debug("🗑️ Starting cleanup for observer: \(self.videoId)")

        // Cleanup player
        if !isPreloading {
            player?.pause()
            player?.replaceCurrentItem(with: nil)
        }

        // Remove notification observer first
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
            notificationObserver = nil
        }

        // Cleanup KVO observers
        statusObserver?.invalidate()
        loadedRangesObserver?.invalidate()
        rateObserver?.invalidate()

        // Clear references
        statusObserver = nil
        loadedRangesObserver = nil
        rateObserver = nil
        player = nil

        // Final cleanup log
        logger.debug("✅ Completed cleanup for observer: \(self.videoId)")
    }

    func togglePlayback() {
        if isPlaying {
            player?.pause()
            logger.debug("⏸️ Paused playback")
        } else {
            player?.play()
            logger.debug("▶️ Started playback")
        }
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

        // Simple synchronous initialization
        let asset = AVURLAsset(url: video.videoURL, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: true
        ])
        asset.resourceLoader.preloadsEligibleContentKeys = true
        let playerItem = AVPlayerItem(asset: asset)
        playerItem.preferredForwardBufferDuration = 5
        let player = AVPlayer(playerItem: playerItem)
        player.isMuted = isMuted
        player.allowsExternalPlayback = false
        player.preventsDisplaySleepDuringVideoPlayback = true

        self.player = player
        _observer = StateObject(wrappedValue: PlayerObserver(player: player, videoId: video.id, isPreloading: isPreloading))
    }

    var body: some View {
        ZStack {
            Color.black
                .edgesIgnoringSafeArea(.all)

            VideoPlayerControllerRepresentable(player: player, observer: observer)
                .opacity(observer.isReady ? 1 : 0)
                .overlay {
                    if !observer.isReady {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                    }
                }
        }
        .onChange(of: observer.isActive, initial: true) { _, isActive in
            if isActive {
                observer.activate()
            } else {
                observer.deactivate()
            }
        }
        .task {
            do {
                // Configure audio session synchronously - no await needed
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            } catch {
                logger.error("Failed to configure audio session: \(error.localizedDescription)")
            }
        }
    }
}

struct VideoPlayerControllerRepresentable: UIViewControllerRepresentable {
    let player: AVPlayer
    let observer: PlayerObserver

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill
        controller.view.backgroundColor = .black

        if let playerLayer = controller.view.layer as? AVPlayerLayer {
            playerLayer.videoGravity = .resizeAspectFill
        }

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        controller.view.addGestureRecognizer(tapGesture)

        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(observer: observer)
    }

    class Coordinator: NSObject {
        let observer: PlayerObserver

        init(observer: PlayerObserver) {
            self.observer = observer
        }

        @objc func handleTap() {
            Task { @MainActor in
                observer.togglePlayback()
            }
        }
    }
}
