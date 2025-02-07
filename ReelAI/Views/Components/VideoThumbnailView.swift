import SwiftUI

struct VideoThumbnailView: View {
    let video: Video
    @State private var cachedImage: UIImage?
    
    var body: some View {
        Group {
            if let cached = cachedImage {
                Image(uiImage: cached)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                AsyncImage(url: video.thumbnailURL) { phase in
                    switch phase {
                    case .empty:
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .overlay {
                                ProgressView()
                            }
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .onAppear {
                                // Cache the thumbnail
                                Task {
                                    if let uiImage = image.asUIImage() {
                                        try? await VideoCacheManager.shared.cacheThumbnail(uiImage, withIdentifier: video.id)
                                    }
                                }
                            }
                    case .failure:
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .overlay {
                                Image(systemName: "video.fill")
                                    .foregroundColor(.gray)
                            }
                    @unknown default:
                        EmptyView()
                    }
                }
            }
        }
        .task {
            // Try to load from cache first
            if let cached = VideoCacheManager.shared.getCachedThumbnail(withIdentifier: video.id) {
                cachedImage = cached
            }
        }
    }
}

// Helper extension to convert SwiftUI Image to UIImage
extension Image {
    func asUIImage() -> UIImage? {
        let controller = UIHostingController(rootView: self.resizable().aspectRatio(contentMode: .fill))
        let view = controller.view
        
        let targetSize = CGSize(width: 300, height: 533) // 9:16 aspect ratio at reasonable size
        view?.bounds = CGRect(origin: .zero, size: targetSize)
        view?.backgroundColor = .clear
        
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            view?.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
    }
}
