import SwiftUI

struct VideoThumbnailView: View {
    let video: Video

    var body: some View {
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
