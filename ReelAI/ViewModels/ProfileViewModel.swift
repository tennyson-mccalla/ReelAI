import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseDatabase
import FirebaseStorage

@MainActor
class ProfileViewModel: ObservableObject {
    @Published private(set) var videos: [Video] = []
    @Published private(set) var error: Error?
    @Published private(set) var isLoading = false

    let authService: AuthServiceProtocol
    private let db = Database.database().reference()
    private let storage = Storage.storage().reference()

    private var thumbnailCache: [TimeInterval: StorageReference]?

    init(authService: AuthServiceProtocol = FirebaseAuthService()) {
        self.authService = authService
    }

    static func createDefault() async -> ProfileViewModel {
        return ProfileViewModel(
            authService: FirebaseAuthService()
        )
    }

    func loadVideos() async {
        guard let userId = authService.currentUser?.uid else { return }

        isLoading = true
        error = nil

        do {
            let snapshot = try await db.child("videos")
                .queryOrdered(byChild: "timestamp")
                .queryLimited(toLast: 50)
                .getData()

            print("📄 Got \(snapshot.childrenCount) videos")

            var loadedVideos: [Video] = []
            for child in snapshot.children {
                guard let snapshot = child as? DataSnapshot,
                      let data = snapshot.value as? [String: Any],
                      let videoName = data["videoName"] as? String,
                      let timestamp = data["timestamp"] as? TimeInterval else {
                    continue
                }

                do {
                    let videoRef = storage.child("videos/\(videoName)")
                    let videoURL = try await videoRef.downloadURL()
                    let videoMetadata = try await videoRef.getMetadata()

                    // Try to get thumbnail but don't fail if not found
                    let thumbnailURL: URL? = try? await getThumbnailURL(
                        for: videoName,
                        timestamp: videoMetadata.timeCreated?.timeIntervalSince1970 ?? timestamp
                    )

                    let video = Video(
                        id: snapshot.key,
                        userId: data["userId"] as? String ?? userId,
                        videoURL: videoURL,
                        thumbnailURL: thumbnailURL,
                        createdAt: Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0)
                    )
                    loadedVideos.append(video)
                } catch {
                    print("❌ Failed to load video: \(videoName)")
                    continue
                }
            }

            videos = loadedVideos.sorted { $0.createdAt > $1.createdAt }

        } catch {
            print("❌ Error loading videos: \(error)")
            self.error = error
        }

        isLoading = false
    }

    func setVideos(_ newVideos: [Video]) {
        videos = newVideos
    }

    func setLoading(_ loading: Bool) {
        isLoading = loading
    }

    func setError(_ newError: Error?) {
        error = newError
    }

    private func loadThumbnailCache() async throws {
        guard thumbnailCache == nil else { return }

        let thumbnails = try await storage.child("thumbnails").listAll()
        var cache: [TimeInterval: StorageReference] = [:]

        for item in thumbnails.items where (try? await item.getMetadata())?.timeCreated != nil {
            let metadata = try await item.getMetadata()
            if let created = metadata.timeCreated {
                cache[created.timeIntervalSince1970] = item
            }
        }

        thumbnailCache = cache
    }

    private func getThumbnailURL(for videoName: String, timestamp: TimeInterval) async throws -> URL {
        // Try exact UUID match first
        let baseVideoName = videoName.replacingOccurrences(of: ".mp4", with: "")
        let newPatternRef = storage.child("thumbnails/\(baseVideoName).jpg")

        do {
            return try await newPatternRef.downloadURL()
        } catch {
            // Fall back to timestamp matching
            try await loadThumbnailCache()
            guard let cache = thumbnailCache else { throw error }

            // Find thumbnail within 2 seconds of video timestamp
            for (thumbTimestamp, thumbnailRef) in cache where abs(thumbTimestamp - timestamp) < 2.0 {
                return try await thumbnailRef.downloadURL()
            }

            throw error
        }
    }
}
