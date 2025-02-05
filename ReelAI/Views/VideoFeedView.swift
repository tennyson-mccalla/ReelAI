import SwiftUI
import FirebaseFirestore
import FirebaseStorage

struct VideoFeedView: View {
    @StateObject private var feedViewModel = VideoFeedViewModel()

    var body: some View {
        GeometryReader { geometry in
            TabView {
                ForEach(feedViewModel.videos) { video in
                    VideoPlayerView(videoURL: video.url)
                        // Rotate each video view individually
                        .rotationEffect(.degrees(90))
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height
                        )
                }
            }
            .frame(
                width: geometry.size.height,
                height: geometry.size.width
            )
            .rotationEffect(.degrees(-90))
            .frame(
                width: geometry.size.width,
                height: geometry.size.height
            )
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color.black)
        }
        .ignoresSafeArea()
        .onAppear {
            // For testing, let's add a sample video
            feedViewModel.loadVideos()
        }
    }
}

struct Video: Identifiable {
    let id: String
    let url: URL
    // Add more metadata as needed
}

class VideoFeedViewModel: ObservableObject {
    @Published var videos: [Video] = []
    private let db = Firestore.firestore()

    func loadVideos() {
        db.collection("videos")
            .order(by: "timestamp", descending: true)
            .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    print("Error loading videos: \(error.localizedDescription)")
                    return
                }

                guard let documents = snapshot?.documents else { return }

                Task {
                    var loadedVideos: [Video] = []
                    for document in documents {
                        let data = document.data()
                        if let videoName = data["videoName"] as? String {
                            let storage = Storage.storage().reference()
                            let videoRef = storage.child("videos/\(videoName)")
                            if let url = try? await videoRef.downloadURL() {
                                let video = Video(
                                    id: document.documentID,
                                    url: url
                                    // Add more metadata as needed
                                )
                                loadedVideos.append(video)
                            }
                        }
                    }

                    await MainActor.run {
                        self?.videos = loadedVideos.shuffled()
                    }
                }
            }
    }
}
