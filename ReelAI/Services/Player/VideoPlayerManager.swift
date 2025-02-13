import Foundation
import AVFoundation
import Combine
import os
import SwiftUI

@MainActor
final class VideoPlayerManager: ObservableObject {
    // MARK: - Singleton
    static let shared = VideoPlayerManager()

    // MARK: - Published State
    @Published private(set) var state = PlayerState()

    // MARK: - Private Properties
    private let player = AVPlayer()
    private var preloadedVideos: [String: PreloadedVideo] = [:]
    private var observers: [NSKeyValueObservation] = []
    private var timeObserver: Any?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReelAI", category: "VideoPlayerManager")

    // MARK: - Configuration
    private let preloadWindow = 1 // Videos to preload before/after current
    private let maxPreloadedVideos = 3 // Maximum videos to keep in memory
    private let bufferDuration: TimeInterval = 2.0 // Seconds to buffer ahead

    // MARK: - Initialization
    private init() {
        setupPlayer()
    }

    // MARK: - Scene Phase Handling
    func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .background:
            handleBackgroundTransition()
        case .active:
            handleForegroundTransition()
        case .inactive:
            // Optionally handle inactive state
            break
        @unknown default:
            break
        }
    }

    // MARK: - Public Interface

    /// Prepares and starts playing a video
    func play(video: Video) async {
        guard video.id != state.currentVideoID else {
            resumePlayback()
            return
        }

        do {
            // 1. Prepare the player item
            let item = try await preparePlayerItem(for: video)

            // 2. Update preloaded videos
            updatePreloadedVideos(with: video.id, item: item)

            // 3. Start playback
            player.replaceCurrentItem(with: item)
            resumePlayback()

            // 4. Update state
            state.currentVideoID = video.id
            state.error = nil

            logger.debug("▶️ Playing video: \(video.id)")
        } catch {
            state.error = .failedToLoad(video.id)
            logger.error("❌ Failed to load video: \(video.id), error: \(error.localizedDescription)")
        }
    }

    /// Preloads videos for smooth playback
    func preload(videos: [Video]) async {
        guard let currentIndex = videos.firstIndex(where: { $0.id == state.currentVideoID }) else { return }

        // Calculate preload range
        let startIndex = max(0, currentIndex - preloadWindow)
        let endIndex = min(videos.count - 1, currentIndex + preloadWindow)

        // Preload videos in range
        for index in startIndex...endIndex where index != currentIndex {
            let video = videos[index]
            let position: PreloadedVideo.Position = index < currentIndex ? .previous : .next

            // Skip if already preloaded
            guard !state.preloadedVideoIDs.contains(video.id) else { continue }

            do {
                let item = try await preparePlayerItem(for: video)
                updatePreloadedVideos(with: video.id, item: item, position: position)
                logger.debug("🔄 Preloaded video: \(video.id)")
            } catch {
                logger.error("❌ Failed to preload video: \(video.id), error: \(error.localizedDescription)")
            }
        }

        // Cleanup old preloaded videos
        cleanupOutOfRangeVideos(currentIndex: currentIndex, videos: videos)
    }

    /// Toggles playback state
    func togglePlayback() {
        if state.isPlaying {
            player.pause()
        } else {
            player.play()
        }
    }

    /// Toggles mute state
    func toggleMute() {
        state.isMuted.toggle()
        player.isMuted = state.isMuted
    }

    // MARK: - Private Methods

    private func setupPlayer() {
        // Configure player
        player.automaticallyWaitsToMinimizeStalling = true
        player.allowsExternalPlayback = false
        player.preventsDisplaySleepDuringVideoPlayback = true

        // Add periodic time observer
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.state.currentTime = time.seconds
            }
        }

        // Observe player rate for play/pause state
        observers.append(
            player.observe(\.rate) { [weak self] player, _ in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.state.isPlaying = player.rate > 0
                }
            }
        )
    }

    private func preparePlayerItem(for video: Video) async throws -> AVPlayerItem {
        // Create asset and player item
        let asset = AVURLAsset(url: video.videoURL)
        let item = AVPlayerItem(asset: asset)

        // Configure item
        item.preferredForwardBufferDuration = bufferDuration
        item.automaticallyPreservesTimeOffsetFromLive = false

        // Wait for item to be ready
        _ = try await item.asset.load(.isPlayable)
        return item
    }

    private func updatePreloadedVideos(with videoID: String, item: AVPlayerItem, position: PreloadedVideo.Position = .current) {
        let preloadedVideo = PreloadedVideo(id: videoID, item: item, position: position)
        preloadedVideos[videoID] = preloadedVideo
        state.preloadedVideoIDs.insert(videoID)

        // Cleanup if we exceed max preloaded videos
        if preloadedVideos.count > maxPreloadedVideos {
            cleanupOldestPreloadedVideo()
        }
    }

    private func cleanupOutOfRangeVideos(currentIndex: Int, videos: [Video]) {
        let validRange = (currentIndex - preloadWindow)...(currentIndex + preloadWindow)
        let validIDs = Set(validRange.compactMap { videos[safe: $0]?.id })

        preloadedVideos = preloadedVideos.filter { validIDs.contains($0.key) }
        state.preloadedVideoIDs = state.preloadedVideoIDs.intersection(validIDs)
    }

    private func cleanupOldestPreloadedVideo() {
        guard let oldest = preloadedVideos.values.min(by: { $0.loadDate < $1.loadDate }),
              oldest.id != state.currentVideoID else { return }

        preloadedVideos.removeValue(forKey: oldest.id)
        state.preloadedVideoIDs.remove(oldest.id)
    }

    private func resumePlayback() {
        player.play()
        state.isPlaying = true
    }

    private func handleBackgroundTransition() {
        player.pause()
        state.isPlaying = false
        logger.debug("⏸️ Paused playback due to background transition")
    }

    private func handleForegroundTransition() {
        if let currentVideo = preloadedVideos[state.currentVideoID ?? ""] {
            player.replaceCurrentItem(with: currentVideo.item)
            // Only resume if it was playing before
            if state.isPlaying {
                player.play()
                logger.debug("▶️ Resumed playback after foreground transition")
            }
            logger.debug("🔄 Restored video state after foreground transition")
        }
    }

    deinit {
        // Remove observers
        observers.forEach { $0.invalidate() }
        if let timeObserver = timeObserver {
            player.removeTimeObserver(timeObserver)
        }
    }
}
