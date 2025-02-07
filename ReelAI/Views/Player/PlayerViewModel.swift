import AVFoundation
import os

@MainActor
final class PlayerViewModel: NSObject, ObservableObject {
    @Published var player: AVPlayer?
    @Published var isReadyToPlay = false
    @Published var progress: Double = 0
    private var shouldLoop = true
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReelAI", category: "PlayerViewModel")

    private var timeObserver: Any?
    private var readyForDisplayObserver: NSKeyValueObservation?
    private var statusObserver: NSKeyValueObservation?
    private var itemObserver: NSKeyValueObservation?
    private var boundaryObserver: Any?

    private var wasPlayingBeforeBackground = false

    func configurePlayback(shouldLoop: Bool) {
        self.shouldLoop = shouldLoop
    }

    func loadVideo(url: URL) {
        loadVideo(playerItem: AVPlayerItem(url: url))
    }

    func loadVideo(playerItem: AVPlayerItem) {
        let startTime = CFAbsoluteTimeGetCurrent()
        logger.debug("🎬 Starting video load: \(CFAbsoluteTimeGetCurrent())")

        playerItem.preferredForwardBufferDuration = 10
        playerItem.automaticallyPreservesTimeOffsetFromLive = false

        setupInitialState(playerItem)
        setupObservers(playerItem, startTime)
        setupPlaybackBehavior(playerItem)
    }

    private func setupInitialState(_ playerItem: AVPlayerItem) {
        isReadyToPlay = false
        player = AVPlayer(playerItem: playerItem)
    }

    private func setupObservers(_ playerItem: AVPlayerItem, _ startTime: TimeInterval) {
        statusObserver = playerItem.observe(\.status) { [weak self] item, _ in
            Task { @MainActor in
                if item.status == .readyToPlay {
                    self?.handleReadyToPlay()
                }
            }
        }

        readyForDisplayObserver = playerItem.observe(\.isPlaybackLikelyToKeepUp) { [weak self] item, _ in
            Task { @MainActor in
                if item.isPlaybackLikelyToKeepUp {
                    let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                    logger.debug("📺 Video playback ready: \(elapsed) seconds")
                    self?.handleReadyToPlay()
                }
            }
        }

        if let player = player {
            timeObserver = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
                queue: .main
            ) { [weak self] time in
                Task { @MainActor in
                    guard let self = self,
                          let item = player.currentItem else { return }
                    self.updateProgress(time: time, item: item)
                }
            }

            itemObserver = player.observe(\.currentItem?.status) { [weak self] player, _ in
                Task { @MainActor in
                    switch player.currentItem?.status {
                    case .readyToPlay:
                        self?.handleReadyToPlay()
                    case .failed:
                        self?.handlePlaybackError()
                    default:
                        break
                    }
                }
            }
        }

        // Loop behavior
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.logger.debug("📼 Video playback ended")
                self?.handlePlaybackEnd()
            }
        }
    }

    private func updateProgress(time: CMTime, item: AVPlayerItem) {
        let duration = item.duration
        if duration.isValid && duration != .zero {
            let durationSeconds = CMTimeGetSeconds(duration)
            if durationSeconds.isFinite && durationSeconds > 0 {
                self.progress = time.seconds / durationSeconds
            }
        }
    }

    private func setupPlaybackBehavior(_ playerItem: AVPlayerItem) {
        if #available(iOS 16.0, *) {
            setupModernPlaybackBehavior(playerItem)
        } else {
            setupLegacyPlaybackBehavior(playerItem)
        }
    }

    private func handlePlaybackEnd() {
        guard shouldLoop else { return }
        player?.seek(to: .zero)
        player?.play()
        progress = 0
    }

    private func handlePlaybackError() {
        logger.error("❌ Playback failed")
    }

    @available(iOS 16.0, *)
    private func setupModernPlaybackBehavior(_ playerItem: AVPlayerItem) {
        Task {
            do {
                let isPlayable = try await playerItem.asset.load(.isPlayable)
                if isPlayable {
                    await MainActor.run {
                        if playerItem.status == .readyToPlay {
                            self.handleReadyToPlay()
                        }
                    }
                }
            } catch {
                logger.error("❌ Failed to load asset: \(error.localizedDescription)")
            }
        }
    }

    private func setupLegacyPlaybackBehavior(_ playerItem: AVPlayerItem) {
        Task {
            if try await playerItem.asset.load(.isPlayable) {
                await MainActor.run {
                    if playerItem.status == .readyToPlay {
                        handleReadyToPlay()
                    }
                }
            }
        }
    }

    private func handleReadyToPlay() {
        guard !isReadyToPlay else { return }
        isReadyToPlay = true
        player?.play()
    }

    func cleanup() {
        statusObserver?.invalidate()
        readyForDisplayObserver?.invalidate()
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        player?.pause()
        player = nil
        isReadyToPlay = false
    }

    func handleBackground() {
        wasPlayingBeforeBackground = isReadyToPlay
        player?.pause()
    }

    func handleForeground() {
        if wasPlayingBeforeBackground {
            player?.play()
        }
    }
}
