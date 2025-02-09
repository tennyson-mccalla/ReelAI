import SwiftUI
import AVKit
import UIKit

@MainActor
struct VideoFeedView: View {
    @StateObject private var viewModel: VideoFeedViewModel
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    @Environment(\.scenePhase) private var scenePhase

    init(viewModel: VideoFeedViewModel? = nil) {
        let vm = viewModel ?? VideoFeedViewModel()
        _viewModel = StateObject(wrappedValue: vm)
    }

    var body: some View {
        GeometryReader { _ in
            ZStack {
                Color.black.ignoresSafeArea()
                
                if viewModel.isLoading && viewModel.videos.isEmpty {
                    loadingView
                } else if !viewModel.videos.isEmpty {
                    videoFeedContent(in: GeometryProxy())
                } else if let error = viewModel.error {
                    errorView(error)
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                Task { @MainActor in
                    await handleScenePhaseChange(newPhase)
                }
            }
            .task {
                if viewModel.videos.isEmpty {
                    await viewModel.loadVideos()
                }
            }
            .navigationBarHidden(true)
        }
    }
    
    @ViewBuilder
    private func videoFeedContent(in geometry: GeometryProxy) -> some View {
        GeometryReader { _ in
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.videos) { video in
                            videoCell(for: video, in: geometry)
                                .id(video.id)
                        }
                    }
                }
                .scrollDisabled(true)
                .highPriorityGesture(createDragGesture(proxy: proxy))
                .onAppear {
                    if viewModel.currentlyPlayingId == nil {
                        viewModel.currentlyPlayingId = viewModel.videos.first?.id
                    }
                }
            }
        }
    }
    
    private func videoCell(for video: Video, in geometry: GeometryProxy) -> some View {
        let isCurrentVideo = viewModel.currentlyPlayingId == video.id
        return VideoPlayerView(
            videoURL: video.videoURL,
            videoId: video.id,
            feedViewModel: viewModel,
            isPlaying: isCurrentVideo
        )
        .frame(width: geometry.size.width, height: geometry.size.height)
        .offset(y: calculateOffset(for: video, dragOffset: dragOffset, in: geometry))
        .opacity(isCurrentVideo ? 1 : 0)
    }
    
    private func createDragGesture(proxy: ScrollViewProxy) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                handleDragChange(value)
            }
            .onEnded { value in
                handleDragEnd(value, proxy: proxy)
            }
    }
    
    private func handleDragChange(_ value: DragGesture.Value) {
        guard let currentIndex = viewModel.videos.firstIndex(where: { $0.id == viewModel.currentlyPlayingId }) else {
            return
        }
        
        isDragging = true
        let translation = value.translation.height
        let screenHeight = UIScreen.main.bounds.height
        
        // Update drag offset with resistance
        let threshold = screenHeight * 0.3
        if abs(translation) > threshold {
            let excess = abs(translation) - threshold
            let damping = 0.2
            let dampedExcess = excess * damping
            dragOffset = (translation < 0 ? -1 : 1) * (threshold + dampedExcess)
        } else {
            dragOffset = translation
        }
    }
    
    private func handleDragEnd(_ value: DragGesture.Value, proxy: ScrollViewProxy) {
        guard let currentIndex = viewModel.videos.firstIndex(where: { $0.id == viewModel.currentlyPlayingId }) else {
            return
        }
        
        isDragging = false
        let translation = value.translation.height
        let progress = translation / UIScreen.main.bounds.height
        
        if abs(progress) >= 0.2 {
            let nextIndex = progress > 0 ? 
                max(0, currentIndex - 1) : 
                min(viewModel.videos.count - 1, currentIndex + 1)
            
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                dragOffset = 0
                viewModel.currentlyPlayingId = viewModel.videos[nextIndex].id
                proxy.scrollTo(viewModel.videos[nextIndex].id, anchor: .center)
            }
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                dragOffset = 0
                proxy.scrollTo(viewModel.videos[currentIndex].id, anchor: .center)
            }
        }
    }
    
    private func handleScenePhaseChange(_ newPhase: ScenePhase) async {
        switch newPhase {
        case .background:
            await viewModel.handleBackground()
        case .active:
            await viewModel.handleForeground()
        default:
            break
        }
    }
    
    private func calculateOffset(for video: Video, dragOffset: CGFloat, in geometry: GeometryProxy) -> CGFloat {
        guard let currentIndex = viewModel.videos.firstIndex(where: { $0.id == viewModel.currentlyPlayingId }),
              let videoIndex = viewModel.videos.firstIndex(where: { $0.id == video.id }) else {
            return 0
        }
        
        let screenHeight = geometry.size.height
        let indexDiff = CGFloat(videoIndex - currentIndex)
        let baseOffset = indexDiff * screenHeight
        return baseOffset + dragOffset
    }
    
    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.5)
            Text("Loading videos...")
                .foregroundColor(.white)
        }
    }
    
    @ViewBuilder
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Text(error)
                .foregroundColor(.white)
            Button("Retry") {
                Task {
                    await viewModel.loadVideos()
                }
            }
            .foregroundColor(.white)
            .padding()
            .background(Color.gray.opacity(0.3))
            .cornerRadius(8)
        }
    }
}

// MARK: - Previews
#if DEBUG
struct VideoFeedView_Previews: PreviewProvider {
    static var previews: some View {
        VideoFeedView()
    }
}

struct VideoFeedViewLoading_Previews: PreviewProvider {
    static var previews: some View {
        VideoFeedView(viewModel: {
            let vm = VideoFeedViewModel()
            vm.setLoading(true)
            return vm
        }())
    }
}

struct VideoFeedViewError_Previews: PreviewProvider {
    static var previews: some View {
        VideoFeedView(viewModel: {
            let vm = VideoFeedViewModel()
            vm.setError("Network connection unavailable")
            return vm
        }())
    }
}
#endif
