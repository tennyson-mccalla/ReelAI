#Preview {
    VideoFeedView()
}

#Preview("Loading State") {
    let viewModel = VideoFeedViewModel()
    viewModel.isLoading = true
    return VideoFeedView(viewModel: viewModel)
}

#Preview("Error State") {
    let viewModel = VideoFeedViewModel()
    viewModel.error = "Network connection unavailable"
    return VideoFeedView(viewModel: viewModel)
}

#if DEBUG
extension VideoFeedViewModel {
    static var mock: VideoFeedViewModel {
        let model = VideoFeedViewModel()
        if let url = URL(string: "https://example.com/1.mp4"),
           let thumbUrl = URL(string: "https://example.com/1.jpg") {
            model.videos = [
                Video(
                    id: "1",
                    userId: "user1",
                    videoURL: url,
                    thumbnailURL: thumbUrl,
                    createdAt: Date()
                )
            ]
        }
        return model
    }
}
#endif
