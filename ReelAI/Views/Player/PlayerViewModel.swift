import AVFoundation
import os

@MainActor
final class PlayerViewModel: NSObject, ObservableObject {
    @Published var player: AVPlayer?
    @Published var isReadyToPlay = false
    @Published var progress: Double = 0
    @Published var isLoading = true
    @Published var hasError = false

    private var shouldLoop = true
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReelAI", category: "PlayerViewModel")

    private var timeObserver: Any?
    private var readyForDisplayObserver: NSKeyValueObservation?
    private var statusObserver: NSKeyValueObservation?
    private var itemObserver: NSKeyValueObservation?
    private var boundaryObserver: Any?

    private var wasPlayingBeforeBackground = false
    private var currentVideoURL: URL?

    // Preloading configuration
    private let preloadBuffer: TimeInterval = 10.0  // 10 seconds ahead
    private var preloadTask: Task<Void, Never>?

    func configurePlayback(shouldLoop: Bool = true, preloadAhead: Bool = true) {
        self.shouldLoop = shouldLoop
        if preloadAhead {
            setupPreloading()
        }
    }

    private func setupPreloading() {
        // Removed setupPreloading function
    }

    private func preloadVideo(asset: AVURLAsset) async {
        do {
            // Get duration
            let duration = try await asset.load(.duration)

            // Preload next buffer
            let preloadTime = min(duration.seconds, preloadBuffer)

            // Check media selection options (if needed)
            if #available(iOS 16.0, *) {
                if let audibleGroup = try? await asset.loadMediaSelectionGroup(for: .audible) {
                    logger.debug("Audible media options: \(audibleGroup.options)")
                }
            } else {
                let characteristics = try await asset.load(.availableMediaCharacteristicsWithMediaSelectionOptions)
                if characteristics.contains(.audible),
                   let audibleGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .audible) {
                    logger.debug("Audible media options: \(audibleGroup.options)")
                }
            }

            logger.debug(" Preloaded \(preloadTime) seconds of video")
        } catch {
            logger.error(" Preloading failed: \(error.localizedDescription)")
        }
    }

    func loadVideo(url: URL) {
        // Cancel any existing preload task
        preloadTask?.cancel()
        currentVideoURL = url

        let playerItem = AVPlayerItem(url: url)
        loadVideo(playerItem: playerItem)

        // Start preloading asynchronously
        let asset = AVURLAsset(url: url)
        preloadTask = Task {
            await preloadVideo(asset: asset)
        }
    }

    func loadVideo(playerItem: AVPlayerItem) {
        let startTime = CFAbsoluteTimeGetCurrent()
        logger.debug(" Starting video load: \(startTime)")

        // Enhanced buffering
        playerItem.preferredForwardBufferDuration = 10
        playerItem.automaticallyPreservesTimeOffsetFromLive = false

        setupInitialState(playerItem)
        setupObservers(playerItem, startTime)
        setupPlaybackBehavior(playerItem)
    }

    private func setupInitialState(_ playerItem: AVPlayerItem) {
        isReadyToPlay = false
        isLoading = true
        hasError = false
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
                    self?.logger.debug(" Video playback ready: \(elapsed) seconds")
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
                self?.logger.debug(" Video playback ended")
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

        // More robust looping
        Task { @MainActor in
            self.player?.seek(to: .zero)
            self.player?.play()
            self.progress = 0
            self.logger.debug(" Video looped")
        }
    }

    private func handlePlaybackError() {
        logger.error(" Playback failed")
        hasError = true
        isLoading = false
        isReadyToPlay = false
    }

    private func handleReadyToPlay() {
        guard !isReadyToPlay else { return }

        isReadyToPlay = true
        isLoading = false
        player?.play()

        logger.debug(" Video ready to play")
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
                self.logger.error(" Failed to load asset: \(error.localizedDescription)")
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
