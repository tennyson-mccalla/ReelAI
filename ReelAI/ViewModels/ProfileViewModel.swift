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
    @Published private(set) var profile: UserProfile

    let authService: AuthServiceProtocol
    private let db = Database.database().reference()
    private let storage = Storage.storage().reference()
    let storageManager: StorageManager
    let databaseManager: DatabaseManager

    private var thumbnailCache: [TimeInterval: StorageReference]?

    init(
        authService: AuthServiceProtocol,
        storage: StorageManager = FirebaseStorageManager(),
        database: DatabaseManager = FirebaseDatabaseManager()
    ) {
        self.authService = authService
        self.storageManager = storage
        self.databaseManager = database

        // Initialize with a temporary profile that will be replaced
        if let userId = authService.currentUser?.uid {
            self.profile = UserProfile(
                id: userId,
                displayName: authService.currentUser?.displayName ?? "New User",
                bio: "",
                photoURL: authService.currentUser?.photoURL,
                socialLinks: []
            )
        } else {
            self.profile = UserProfile.mock // Temporary fallback
        }

        // Load the real profile
        Task {
            await loadProfile()
        }
    }

    func loadProfile() async {
        guard let userId = authService.currentUser?.uid else { return }

        do {
            let loadedProfile = try await databaseManager.fetchProfile(userId: userId)
            await MainActor.run {
                self.profile = loadedProfile
            }
        } catch {
            print("❌ Failed to load profile: \(error)")
            // Create new profile if none exists
            let newProfile = UserProfile(
                id: userId,
                displayName: authService.currentUser?.displayName ?? "New User",
                bio: "",
                photoURL: authService.currentUser?.photoURL,
                socialLinks: [] // Explicitly set empty array
            )

            do {
                try await databaseManager.updateProfile(newProfile)
                await MainActor.run {
                    self.profile = newProfile
                }
            } catch {
                print("❌ Failed to create new profile: \(error)")
            }
        }
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
            print("🎬 Starting to load videos")
            let snapshot = try await db.child("videos")
                .queryOrdered(byChild: "timestamp")
                .queryLimited(toLast: 50)
                .getData()

            print("📄 Got \(snapshot.childrenCount) videos from database")
            let loadedVideos = try await loadVideosFromSnapshot(snapshot, userId: userId)
            
            // Set videos immediately after loading basic info
            await MainActor.run {
                videos = loadedVideos.sorted { $0.createdAt > $1.createdAt }
                isLoading = false // Stop showing loading spinner after basic data is loaded
            }

            // Start preloading thumbnails after basic data is shown
            print("🖼️ Starting thumbnail preload")
            await preloadThumbnails(for: loadedVideos)
            print("✅ Finished preloading thumbnails")

        } catch {
            print("❌ Error loading videos: \(error)")
            self.error = error
            isLoading = false
        }
    }

    private func preloadThumbnails(for videos: [Video]) async {
        await withTaskGroup(of: Void.self) { group in
            for video in videos {
                group.addTask {
                    if let thumbnailURL = video.thumbnailURL {
                        do {
                            let (data, _) = try await URLSession.shared.data(from: thumbnailURL)
                            if let image = UIImage(data: data) {
                                do {
                                    _ = try await VideoCacheManager.shared.cacheThumbnail(image, withIdentifier: video.id)
                                } catch {
                                    print("Failed to cache thumbnail for video \(video.id): \(error)")
                                }
                            }
                        } catch {
                            print("Failed to preload thumbnail for video \(video.id): \(error)")
                        }
                    }
                }
            }
        }
    }

    private func loadVideosFromSnapshot(_ snapshot: DataSnapshot, userId: String) async throws -> [Video] {
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

                // If we have a thumbnail URL, try to preload it into our cache
                if let thumbnailURL = thumbnailURL {
                    Task {
                        do {
                            let (data, _) = try await URLSession.shared.data(from: thumbnailURL)
                            if let image = UIImage(data: data) {
                                do {
                                    _ = try await VideoCacheManager.shared.cacheThumbnail(image, withIdentifier: snapshot.key)
                                } catch {
                                    print("Failed to cache thumbnail for video \(snapshot.key): \(error)")
                                }
                            }
                        } catch {
                            print("Failed to preload thumbnail for video \(snapshot.key): \(error)")
                        }
                    }
                }

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
        
        return loadedVideos
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
}
