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
            } else {
                Color.gray
                    .overlay {
                        if isLoading {
                            ProgressView()
                        }
                    }
            }
        }
        .task {
            guard thumbnailImage == nil else { return }
            let start = Date()
            logger.debug("🖼️ Starting to load thumbnail for video: \(video.id)")
            
            // First try to get from cache
            if let cached = await VideoCacheManager.shared.getCachedThumbnail(withIdentifier: video.id) {
                logger.debug("✅ Loaded cached thumbnail for video: \(video.id) in \(Date().timeIntervalSince(start))s")
                thumbnailImage = cached
                isLoading = false
                return
            }
            
            // If not in cache, load from URL
            guard let thumbnailURL = video.thumbnailURL else {
                logger.error("❌ No thumbnail URL for video: \(video.id)")
                isLoading = false
                return
            }
            
            do {
                let (data, _) = try await URLSession.shared.data(from: thumbnailURL)
                guard let image = UIImage(data: data) else {
                    logger.error("❌ Failed to create image from data for video: \(video.id)")
                    isLoading = false
                    return
                }
                
                // Cache the thumbnail
                _ = try await VideoCacheManager.shared.cacheThumbnail(image, withIdentifier: video.id)
                logger.debug("✅ Loaded and cached thumbnail for video: \(video.id) in \(Date().timeIntervalSince(start))s")
                
                thumbnailImage = image
            } catch {
                logger.error("❌ Failed to load thumbnail for video \(video.id): \(error.localizedDescription)")
            }
            
            isLoading = false
        }
    }
}
