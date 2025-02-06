import SwiftUI
import AVKit

struct VideoPlayerView: View {
    let videoURL: URL
    let videoId: String
    @ObservedObject var feedViewModel: VideoFeedViewModel
    @StateObject private var playerViewModel: VideoPlayerViewModel
    @State private var isMuted = false
    @State private var isPlaying = true
    @State private var simulateOffline = false
    let onLoadingStateChanged: (Bool) -> Void  // Add callback
    @State private var loadError: Error?

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
        _playerViewModel = StateObject(wrappedValue: VideoPlayerViewModel())
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let error = loadError {
                    VStack {
                        Text("Failed to load video")
                            .foregroundColor(.white)
                        Text(error.localizedDescription)
                            .foregroundColor(.gray)
                            .font(.caption)
                        Button("Retry") {
                            Task {
                                await loadVideo(from: videoURL)
                            }
                        }
                        .foregroundColor(.white)
                        .padding()
                    }
                } else {
                    // Replace VideoPlayer with custom player view
                    CustomVideoPlayer(player: playerViewModel.player) {
                        isPlaying.toggle()
                        if isPlaying {
                            playerViewModel.player?.play()
                        } else {
                            playerViewModel.player?.pause()
                        }
                    }
                        .ignoresSafeArea(.all)
                        .frame(width: geometry.size.width, height: geometry.size.height)

                    // Overlay controls
                    VStack {
                        // Top mute button
                        HStack {
                            Spacer()
                            Button(action: {
                                isMuted.toggle()
                                playerViewModel.player?.isMuted = isMuted
                            }) {
                                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 20))
                                    .padding(12)
                            }
                        }
                        .padding(.top, 48)

                        Spacer()

                        // Add debug button
                        Button("Test Cache") {
                            Task {
                                await VideoCacheManager.shared.debugPrintCache()
                            }
                        }
                        .padding()
                        .background(Color.black.opacity(0.5))
                        .foregroundColor(.white)
                        .cornerRadius(8)

                        // Add this button near the existing Test Cache button
                        Button(simulateOffline ? "Online Mode" : "Offline Mode") {
                            simulateOffline.toggle()
                        }
                        .padding()
                        .background(Color.red.opacity(0.5))
                        .foregroundColor(.white)
                        .cornerRadius(8)

                        // Add this button near the other test buttons
                        Button("Clear Cache") {
                            Task {
                                await VideoCacheManager.shared.clearCache()
                                await VideoCacheManager.shared.debugPrintCache()
                            }
                        }
                        .padding()
                        .background(Color.orange.opacity(0.5))
                        .foregroundColor(.white)
                        .cornerRadius(8)

                        // Progress bar above tab bar
                        Rectangle()
                            .fill(Color.white.opacity(0.2))
                            .frame(height: 1.5)
                            .overlay(
                                Rectangle()
                                    .fill(Color.white.opacity(0.8))
                                    .frame(width: UIScreen.main.bounds.width * playerViewModel.progress)
                                    .frame(height: 1.5),
                                alignment: .leading
                            )
                            .padding(.horizontal, 8)
                            .padding(.bottom, 40) // Increased from 24 to 40 to clear the house icon
                    }
                    .padding(.bottom, tabBarHeight) // Reserve space for tab bar
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
        .onChange(of: playerViewModel.player?.status) { _, _ in
            if newValue == .readyToPlay {
                onLoadingStateChanged(false)
            }
        }
        .onChange(of: isPlaying) { _ in
            // ...
        }
        .onDisappear {
            playerViewModel.cleanup()
        }
    }

    private func loadVideo(from url: URL) async {
        onLoadingStateChanged(true)

        if let prefetchedItem = tryLoadPrefetchedItem() {
            return
        }

        await loadFromCacheOrNetwork(url: url)
    }

    private func tryLoadPrefetchedItem() -> Bool {
        if let prefetchedItem = feedViewModel.playerItem(for: videoId) {
            print("🎯 Using prefetched video: \(videoId)")
            playerViewModel.loadVideo(playerItem: prefetchedItem)
            onLoadingStateChanged(false)
            return true
        }
        return false
    }

    private func loadFromCacheOrNetwork(url: URL) async {
        let startTime = CFAbsoluteTimeGetCurrent()
        do {
            if simulateOffline {
                // Only try to load from cache
                let cachedURL = try await VideoCacheManager.shared.cacheVideo(
                    from: url,
                    withIdentifier: url.lastPathComponent
                )
                if FileManager.default.fileExists(atPath: cachedURL.path) {
                    playerViewModel.loadVideo(url: cachedURL)
                } else {
                    print("No cached version available in offline mode")
                }
                return
            }

            let cachedURL = try await VideoCacheManager.shared.cacheVideo(
                from: url,
                withIdentifier: url.lastPathComponent
            )
            playerViewModel.loadVideo(url: cachedURL)
            print("Video load time: \(CFAbsoluteTimeGetCurrent() - startTime) seconds")
        } catch {
            loadError = error
            onLoadingStateChanged(false)
        }
    }
}

// Custom video player with precise layout control
struct CustomVideoPlayer: UIViewRepresentable {
    let player: AVPlayer?
    var onTap: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let playerLayer = AVPlayerLayer()
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        view.layer.addSublayer(playerLayer)

        // Add tap gesture
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        view.addGestureRecognizer(tapGesture)

        return view
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let playerLayer = uiView.layer.sublayers?.first as? AVPlayerLayer {
            playerLayer.player = player
            playerLayer.frame = uiView.bounds
            playerLayer.videoGravity = .resizeAspect
        }
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

class VideoPlayerViewModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isReadyToPlay = false
    @Published var progress: Double = 0
    private var timeObserver: Any?
    private var readyForDisplayObserver: NSKeyValueObservation?
    private var statusObserver: NSKeyValueObservation?

    func loadVideo(url: URL) {
        loadVideo(playerItem: AVPlayerItem(url: url))
    }

    func loadVideo(playerItem: AVPlayerItem) {
        let startTime = CFAbsoluteTimeGetCurrent()
        print("🎬 Starting video load: \(CFAbsoluteTimeGetCurrent())")

        setupInitialState(playerItem)
        setupObservers(playerItem, startTime)
        setupPlaybackBehavior(playerItem)
    }

    private func setupInitialState(_ playerItem: AVPlayerItem) {
        isReadyToPlay = false
        player = AVPlayer(playerItem: playerItem)
    }

    private func setupObservers(_ playerItem: AVPlayerItem, _ startTime: CFAbsoluteTimeTimeVal) {
        // Status observer
        statusObserver = playerItem.observe(\.status) { [weak self] item, _ in
            if item.status == .readyToPlay {
                self?.handleReadyToPlay()
            }
        }

        // Display readiness observer
        readyForDisplayObserver = playerItem.observe(\.isPlaybackLikelyToKeepUp) { [weak self] item, _ in
            if item.isPlaybackLikelyToKeepUp {
                let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                print("📺 Video playback ready: \(elapsed) seconds")
                self?.handleReadyToPlay()
            }
        }

        // Progress observer
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            self?.updateProgress(time: time, item: playerItem)
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

        // Loop behavior
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            self?.handlePlaybackEnd()
        }
    }

    private func handlePlaybackEnd() {
        player?.seek(to: .zero)
        player?.play()
        progress = 0
    }

    @available(iOS 16.0, *)
    private func setupModernPlaybackBehavior(_ playerItem: AVPlayerItem) {
        Task {
            do {
                _ = try await playerItem.asset.load(.isPlayable)
                await MainActor.run {
                    if playerItem.status == .readyToPlay {
                        self.handleReadyToPlay()
                    }
                }
            } catch {
                print("❌ Failed to load asset: \(error.localizedDescription)")
            }
        }
    }

    private func setupLegacyPlaybackBehavior(_ playerItem: AVPlayerItem) {
        playerItem.asset.loadValuesAsynchronously(forKeys: ["playable"]) { [weak self] in
            DispatchQueue.main.async {
                if playerItem.status == .readyToPlay {
                    self?.handleReadyToPlay()
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
}
