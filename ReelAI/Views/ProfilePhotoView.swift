import SwiftUI
import os

struct ProfilePhotoView: View {
    let url: URL?
    var size: CGFloat = 120

    @State private var image: UIImage?
    @State private var isLoading = false

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ReelAI",
        category: "ProfilePhotoView"
    )

    var body: some View {
        ZStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .foregroundColor(.gray)
                    .opacity(0.8)
            }

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black.opacity(0.3))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: url?.absoluteString) {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let url = url else {
            isLoading = false
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                self.image = image
            } else {
                logger.error("Failed to create image from data")
            }
        } catch {
            logger.error("Failed to load profile photo: \(error.localizedDescription)")
        }
    }
}

#Preview("Profile Photo") {
    ProfilePhotoView(url: nil)
        .frame(width: 200, height: 200)
}
