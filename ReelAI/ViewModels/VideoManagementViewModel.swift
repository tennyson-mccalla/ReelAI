import SwiftUI
import os
import Firebase

@MainActor
final class VideoManagementViewModel: ObservableObject {
    @Published private(set) var videos: [Video] = []
    @Published private(set) var isLoading = false
    @Published var error: String?

    private let database = Database.database().reference()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ReelAI",
        category: "VideoManagement"
    )

    init() {
        Task {
            await fetchVideos()
        }
    }

    func fetchVideos() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let snapshot = try await database.child("videos").getData()
            guard let dict = snapshot.value as? [String: [String: Any]] else {
                videos = []
                return
            }

            videos = dict.compactMap { key, value in
                var data = value
                data["id"] = key
                return try? Video(dictionary: data)
            }
            .sorted { $0.createdAt > $1.createdAt }
        } catch {
            self.error = error.localizedDescription
            videos = []
        }
    }

    func softDelete(_ videoId: String) async {
        await updateVideo(videoId: videoId, path: "isDeleted", value: true)
    }

    func restore(_ videoId: String) async {
        await updateVideo(videoId: videoId, path: "isDeleted", value: false)
    }

    func updatePrivacy(_ videoId: String, isPrivate: Bool) async {
        await updateVideo(videoId: videoId, path: "privacyLevel", value: isPrivate ? "private" : "public")
    }

    func updateCaption(_ videoId: String, caption: String) async {
        await updateVideo(videoId: videoId, path: "caption", value: caption)
    }

    private func updateVideo(videoId: String, path: String, value: Any) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            try await database.child("videos").child(videoId).child(path).setValue(value)
            await fetchVideos()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
