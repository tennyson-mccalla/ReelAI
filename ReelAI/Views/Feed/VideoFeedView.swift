import SwiftUI
import AVKit
import os

@MainActor
struct VideoFeedView: View {
    @StateObject private var viewModel: VideoFeedViewModel
    @State private var isMuted = true
    @GestureState private var dragOffset: CGFloat = 0
    @State private var activeOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var isTransitioning = false
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReelAI", category: "VideoFeedView")

    // Constants for performance tuning
    private let preloadDistance: CGFloat = UIScreen.main.bounds.height * 0.5
    private let velocityThreshold: CGFloat = 200
    private let minimumDragDistance: CGFloat = 40
    private let transitionDuration: TimeInterval = 0.4

    init(initialVideo: Video? = nil) {
        _viewModel = StateObject(wrappedValue: VideoFeedViewModel(initialVideo: initialVideo))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)

                // Previous Video Layer
                if let previousVideo = viewModel.previousVideo,
                   (dragOffset + activeOffset > -preloadDistance || isTransitioning) {
                    VideoPlayerView(video: previousVideo, isMuted: isMuted, isPreloading: true)
                        .frame(height: geometry.size.height)
                        .offset(y: -geometry.size.height + dragOffset + activeOffset)
                        .id("prev_\(previousVideo.id)")  // Unique ID to prevent reuse
                }

                // Current Video Layer
                if let currentVideo = viewModel.currentVideo {
                    VideoPlayerView(video: currentVideo, isMuted: isMuted)
                        .frame(height: geometry.size.height)
                        .offset(y: dragOffset + activeOffset)
                        .id("current_\(currentVideo.id)")  // Unique ID to prevent reuse
                }

                // Next Video Layer
                if let nextVideo = viewModel.nextVideo,
                   (dragOffset + activeOffset < preloadDistance || isTransitioning) {
                    VideoPlayerView(video: nextVideo, isMuted: isMuted, isPreloading: true)
                        .frame(height: geometry.size.height)
                        .offset(y: geometry.size.height + dragOffset + activeOffset)
                        .id("next_\(nextVideo.id)")  // Unique ID to prevent reuse
                }

                // UI Overlay
                VStack {
                    HStack {
                        Button(action: { isMuted.toggle() }) {
                            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .foregroundColor(.white)
                                .padding()
                        }
                        Spacer()
                    }
                    Spacer()
                }
            }
            .gesture(
                DragGesture(minimumDistance: minimumDragDistance)
                    .updating($dragOffset) { value, state, _ in
                        guard !isTransitioning else { return }
                        state = value.translation.height
                        if !isDragging {
                            isDragging = true
                            logger.debug("🔄 Started dragging")
                        }
                    }
                    .onEnded { value in
                        guard !isTransitioning else { return }
                        isDragging = false
                        let height = geometry.size.height
                        let threshold = height * 0.2
                        let velocity = value.predictedEndLocation.y - value.location.y

                        if abs(value.translation.height) > threshold || abs(velocity) > velocityThreshold {
                            isTransitioning = true

                            if value.translation.height > 0 && viewModel.previousVideo != nil {
                                withAnimation(.spring(response: transitionDuration, dampingFraction: 0.95)) {
                                    activeOffset += height
                                }
                                logger.debug("⬆️ Moving to previous video")
                                Task {
                                    // Ensure animation starts before state change
                                    try? await Task.sleep(nanoseconds: UInt64(transitionDuration * 0.5 * 1_000_000_000))
                                    // Move to previous video and wait for completion
                                    await withTaskGroup(of: Void.self) { group in
                                        group.addTask { await viewModel.moveToPreviousVideo() }
                                        for await _ in group {}
                                    }
                                    // Wait for animation to complete
                                    try? await Task.sleep(nanoseconds: UInt64(transitionDuration * 0.5 * 1_000_000_000))
                                    isTransitioning = false
                                }
                            } else if value.translation.height < 0 && viewModel.nextVideo != nil {
                                withAnimation(.spring(response: transitionDuration, dampingFraction: 0.95)) {
                                    activeOffset -= height
                                }
                                logger.debug("⬇️ Moving to next video")
                                Task {
                                    // Ensure animation starts before state change
                                    try? await Task.sleep(nanoseconds: UInt64(transitionDuration * 0.5 * 1_000_000_000))
                                    // Move to next video and wait for completion
                                    await withTaskGroup(of: Void.self) { group in
                                        group.addTask { await viewModel.moveToNextVideo() }
                                        for await _ in group {}
                                    }
                                    // Wait for animation to complete
                                    try? await Task.sleep(nanoseconds: UInt64(transitionDuration * 0.5 * 1_000_000_000))
                                    isTransitioning = false
                                }
                            } else {
                                withAnimation(.spring(response: transitionDuration, dampingFraction: 0.95)) {
                                    activeOffset = 0
                                }
                                logger.debug("↕️ Bouncing back - no video available")
                                Task {
                                    try? await Task.sleep(nanoseconds: UInt64(transitionDuration * 1_000_000_000))
                                    isTransitioning = false
                                }
                            }
                        } else {
                            withAnimation(.spring(response: transitionDuration, dampingFraction: 0.95)) {
                                activeOffset = 0
                            }
                            logger.debug("↕️ Resetting position - threshold not met")
                        }
                    }
            )
        }
        .task {
            await viewModel.loadVideos()
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
            }
        }
    }
}

#if DEBUG
struct VideoFeedView_Previews: PreviewProvider {
    static var previews: some View {
        VideoFeedView()
    }
}
#endif
