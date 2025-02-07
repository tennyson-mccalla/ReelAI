import SwiftUI
import os

struct VideoThumbnailView: View {
    let video: Video
    @State private var isLoading = true
    @State private var thumbnailImage: UIImage?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReelAI", category: "VideoThumbnailView")
    
    var body: some View {
        Group {
            if let image = thumbnailImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                Color.gray.opacity(0.3)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: thumbnailImage != nil)
        .onAppear {
            Task {
                await loadThumbnail()
            }
        }
    }
    
    private func loadThumbnail() async {
        guard thumbnailImage == nil else { return }
        let start = Date()
        logger.debug("🖼️ Loading thumbnail for video: \(video.id)")
        
        // First try to get from cache
        if let cached = await VideoCacheManager.shared.getCachedThumbnail(withIdentifier: video.id) {
            logger.debug("✅ Loaded cached thumbnail in \(Date().timeIntervalSince(start))s")
            await MainActor.run {
                withAnimation {
                    thumbnailImage = cached
                    isLoading = false
                }
            }
            return
        }
        
        // If not in cache, load from URL
        guard let thumbnailURL = video.thumbnailURL else {
            logger.error("❌ No thumbnail URL for video: \(video.id)")
            await MainActor.run {
                isLoading = false
            }
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: thumbnailURL)
            guard let image = UIImage(data: data) else {
                logger.error("❌ Failed to create image from data")
                await MainActor.run {
                    isLoading = false
                }
                return
            }
            
            // Cache the thumbnail
            _ = try await VideoCacheManager.shared.cacheThumbnail(image, withIdentifier: video.id)
            logger.debug("✅ Loaded and cached thumbnail in \(Date().timeIntervalSince(start))s")
            
            await MainActor.run {
                withAnimation {
                    thumbnailImage = image
                    isLoading = false
                }
            }
        } catch {
            logger.error("❌ Failed to load thumbnail: \(error.localizedDescription)")
            await MainActor.run {
                isLoading = false
            }
        }
    }
}
