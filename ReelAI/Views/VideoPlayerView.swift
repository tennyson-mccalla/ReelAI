import SwiftUI
import AVKit

struct VideoPlayerView: View {
    let videoURL: URL
    @StateObject private var playerViewModel = VideoPlayerViewModel()
    @State private var isMuted = false
    @State private var isPlaying = true

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
            playerViewModel.loadVideo(url: videoURL)
        }
        .onDisappear {
            playerViewModel.cleanup()
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

            // Force layout and check positioning
            playerLayer.layoutIfNeeded()
            let videoRect = playerLayer.videoRect
            print("📐 Video positioning - Frame: \(playerLayer.frame), Video rect: \(videoRect)")
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

        // Add progress tracking
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let duration = self?.player?.currentItem?.duration.seconds,
                  !duration.isNaN,
                  duration > 0
            else { return }

            self?.progress = time.seconds / duration
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
