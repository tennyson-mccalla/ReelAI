import SwiftUI
import AVKit

struct VideoPlayerView: View {
    let videoURL: URL
    @StateObject private var playerViewModel = VideoPlayerViewModel()
    @State private var isMuted = false
    @State private var isPlaying = true
    @State private var simulateOffline = false

    // Standard tab bar height
    private let tabBarHeight: CGFloat = 49

    var body: some View {
        GeometryReader { geometry in
            ZStack {
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
        .ignoresSafeArea(.all)
        .background(Color.black)
        .onAppear {
            Task {
                await loadVideo(from: videoURL)
            }
        }
        .onDisappear {
            playerViewModel.cleanup()
        }
    }

    private func loadVideo(from url: URL) async {
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
            print("Error loading video: \(error)")
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
    @Published var progress: Double = 0
    private var timeObserver: Any?

    func loadVideo(url: URL) {
        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        player?.play()

        // This time observer is probably generating lots of logs
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let duration = self?.player?.currentItem?.duration.seconds,
                  duration.isFinite && duration > 0
            else { return }

            DispatchQueue.main.async {
                self?.progress = min(max(time.seconds / duration, 0), 1)
            }
        }

        // Loop video
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            self?.player?.seek(to: .zero)
            self?.player?.play()
            self?.progress = 0
        }
    }

    func cleanup() {
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        player?.pause()
        player = nil
        progress = 0
    }
}
