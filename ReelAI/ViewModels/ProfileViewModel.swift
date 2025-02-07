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
    private let _storageManager: StorageManager
    private let _databaseManager: DatabaseManager
    private var currentProfile: UserProfile

    private var thumbnailCache: [TimeInterval: StorageReference]?

    init(
        authService: AuthServiceProtocol,
        storage: StorageManager = FirebaseStorageManager(),
        database: DatabaseManager = FirebaseDatabaseManager(),
        initialProfile: UserProfile
    ) {
        self.authService = authService
        self._storageManager = storage
        self._databaseManager = database
        self.currentProfile = initialProfile
    }

    static func createDefault() async -> ProfileViewModel {
        return ProfileViewModel(
            authService: FirebaseAuthService(),
            initialProfile: UserProfile.mock
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
                        createdAt: Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0),
                        caption: data["caption"] as? String ?? "",
                        likes: data["likes"] as? Int ?? 0,
                        comments: data["comments"] as? Int ?? 0
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

        for item in thumbnails.items {
            if let metadata = try? await item.getMetadata(),
               let created = metadata.timeCreated {
                cache[created.timeIntervalSince1970] = item
            }
        }

        thumbnailCache = cache
    }

    private func getThumbnailURL(for videoName: String, timestamp: TimeInterval) async throws -> URL {
        let baseVideoName = videoName.replacingOccurrences(of: ".mp4", with: "")
        let newPatternRef = storage.child("thumbnails/\(baseVideoName).jpg")

        do {
            return try await newPatternRef.downloadURL()
        } catch let downloadError {
            try await loadThumbnailCache()
            guard let cache = thumbnailCache else { throw downloadError }

            for (thumbTimestamp, thumbnailRef) in cache where abs(thumbTimestamp - timestamp) < 2.0 {
                return try await thumbnailRef.downloadURL()
            }

            throw downloadError
        }
    }

    private func processVideos(from dict: [String: [String: Any]]) async throws -> [Video] {
        var videos: [Video] = []

        for (id, data) in dict {
            if let userId = data["userId"] as? String,
               let videoURLString = data["videoURL"] as? String,
               let videoURL = URL(string: videoURLString),
               let thumbnailURLString = data["thumbnailURL"] as? String,
               let thumbnailURL = URL(string: thumbnailURLString),
               let timestamp = data["timestamp"] as? TimeInterval {

                let video = Video(
                    id: id,
                    userId: userId,
                    videoURL: videoURL,
                    thumbnailURL: thumbnailURL,
                    createdAt: Date(timeIntervalSince1970: timestamp),
                    caption: data["caption"] as? String ?? "",
                    likes: data["likes"] as? Int ?? 0,
                    comments: data["comments"] as? Int ?? 0
                )
                videos.append(video)
            }
        }

        return videos.sorted(by: { $0.createdAt > $1.createdAt })
    }

    public var profile: UserProfile {
        return currentProfile
    }

    public var storageManager: StorageManager {
        return _storageManager
    }

    public var databaseManager: DatabaseManager {
        return _databaseManager
    }
}
