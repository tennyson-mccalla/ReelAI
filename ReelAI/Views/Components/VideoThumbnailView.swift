import SwiftUI
import os

struct VideoThumbnailView: View {
    let video: Video
    @State private var thumbnailImage: UIImage?
    @State private var isLoading = true
    @State private var loadAttempt = 0
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReelAI", category: "VideoThumbnailView")

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image = thumbnailImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(9/16, contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .aspectRatio(9/16, contentMode: .fill)
                }

                if isLoading {
                    ProgressView()
                }
            }
        }
        .aspectRatio(9/16, contentMode: .fit)
        .task(id: loadAttempt) {
            await loadThumbnail()
        }
        .onReceive(NotificationCenter.default.publisher(for: .videoCacheCleared)) { _ in
            thumbnailImage = nil
            isLoading = true
            loadAttempt += 1
        }
    }

    private func loadThumbnail() async {
        guard thumbnailImage == nil else { return }
        isLoading = true

        // Try cache first
        if let cached = await VideoCacheManager.shared.getCachedThumbnail(withIdentifier: video.id) {
            await MainActor.run {
                withAnimation {
                    thumbnailImage = cached
                    isLoading = false
                }
            }
            return
        }

        // Load from URL if not cached
        guard let thumbnailURL = video.thumbnailURL else {
            logger.error("No thumbnail URL available")
            await MainActor.run { isLoading = false }
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: thumbnailURL)
            guard let image = UIImage(data: data) else {
                logger.error("Invalid image data received")
                await MainActor.run { isLoading = false }
                return
            }

            // Cache the thumbnail
            _ = try await VideoCacheManager.shared.cacheThumbnail(image, withIdentifier: video.id)

            await MainActor.run {
                withAnimation {
                    thumbnailImage = image
                    isLoading = false
                }
            }
        } catch {
            logger.error("Failed to load thumbnail: \(error.localizedDescription)")
            await MainActor.run { isLoading = false }
        }
    }
}
