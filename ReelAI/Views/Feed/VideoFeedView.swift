import SwiftUI
import AVKit
import os

@MainActor
struct VideoFeedView: View {
    @StateObject private var viewModel = VideoFeedViewModel()
    @State private var isMuted = true
    @GestureState private var dragOffset: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                if let currentVideo = viewModel.currentVideo {
                    VideoPlayerView(video: currentVideo, isMuted: isMuted)
                        .offset(y: dragOffset)
                        .animation(.easeInOut(duration: 0.3), value: dragOffset)
                        .gesture(
                            DragGesture()
                                .updating($dragOffset) { value, state, _ in
                                    state = value.translation.height
                                }
                                .onEnded { value in
                                    let height = geometry.size.height
                                    let threshold = height * 0.25
                                    let velocity = value.predictedEndLocation.y - value.location.y
                                    
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        if abs(value.translation.height) > threshold || abs(velocity) > 500 {
                                            if value.translation.height > 0 {
                                                viewModel.moveToPrevious()
                                            } else {
                                                viewModel.moveToNext()
                                            }
                                        }
                                    }
                                }
                        )
                }
                
                // Preload next video
                if let nextVideo = viewModel.nextVideo {
                    VideoPlayerView(video: nextVideo, isMuted: isMuted, isPreloading: true)
                        .opacity(0)
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
                
                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                }
            }
        }
        .task {
            await viewModel.loadVideos()
        }
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Previews
#if DEBUG
struct VideoFeedView_Previews: PreviewProvider {
    static var previews: some View {
        VideoFeedView()
    }
}
#endif
