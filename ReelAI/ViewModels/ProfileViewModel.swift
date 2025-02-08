import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseDatabase
import FirebaseStorage
import os

@MainActor
class ProfileViewModel: ObservableObject {
    @Published private(set) var videos: [Video] = []
    @Published private(set) var error: Error?
    @Published private(set) var isLoading = false
    @Published private(set) var profile: UserProfile
    private var hasLoadedVideos = false
    private var cachedVideos: [Video]?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReelAI", category: "ProfileViewModel")

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

        // Set up notification observer for cache clearing
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCacheCleared),
            name: .videoCacheCleared,
            object: nil
        )

        // Load the real profile
        Task {
            await loadProfile()
        }
    }

    @objc private func handleCacheCleared() {
        Task {
            // Force reload videos from Firebase when cache is cleared
            cachedVideos = nil
            await loadVideos()
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
        guard !isLoading else { return }
        guard let userId = authService.currentUser?.uid else { return }

        isLoading = true
        logger.info("🎬 Starting to load videos")

        do {
            // Clear cached data
            cachedVideos = nil

            // Disable persistence for this query
            db.child("videos").keepSynced(false)

            let snapshot = try await db.child("videos")
                .queryOrdered(byChild: "timestamp")
                .queryLimited(toLast: 50)
                .getData()

            print("📄 Got \(snapshot.childrenCount) videos from database")

            // Log raw data for debugging
            if let rawData = snapshot.value as? [String: [String: Any]] {
                for (id, data) in rawData {
                    logger.debug("🔍 Raw video data - ID: \(id), isDeleted: \(data["isDeleted"] as? Bool ?? false)")
                }
            }

            let loadedVideos = try await loadVideosFromSnapshot(snapshot, userId: userId)

            await MainActor.run {
                self.videos = loadedVideos.sorted { $0.createdAt > $1.createdAt }
                self.cachedVideos = loadedVideos.sorted { $0.createdAt > $1.createdAt }
                logger.info("📄 Got \(loadedVideos.count) videos from database")
                logger.debug("""
📼 Loaded videos:
\(self.videos.map { video in
    "id: \(video.id.prefix(6)), privacy: \(video.privacyLevel), deleted: \(video.isDeleted), caption: \(video.caption.prefix(20))..."
}.joined(separator: "\n"))
""")
                isLoading = false
                hasLoadedVideos = true
            }
        } catch {
            await MainActor.run {
                self.error = error
                logger.error("❌ Failed to load videos: \(error.localizedDescription)")
                isLoading = false
            }
        }
    }

    func forceRefreshVideos() async {
        logger.debug("🔄 Force refreshing videos")
        hasLoadedVideos = false
        cachedVideos = nil
        await loadVideos()
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

                let video = Video(
                    id: snapshot.key,
                    userId: data["userId"] as? String ?? userId,
                    videoURL: videoURL,
                    thumbnailURL: thumbnailURL,
                    createdAt: Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0),
                    caption: data["caption"] as? String ?? "",
                    likes: data["likes"] as? Int ?? 0,
                    comments: data["comments"] as? Int ?? 0,
                    isDeleted: data["isDeleted"] as? Bool ?? false,
                    privacyLevel: Video.PrivacyLevel(rawValue: data["privacyLevel"] as? String ?? "public") ?? .public
                )
                loadedVideos.append(video)

                logger.debug("""
📼 Video loaded:
ID: \(snapshot.key)
Deleted: \(data["isDeleted"] as? Bool ?? false)
Privacy: \(data["privacyLevel"] as? String ?? "public")
Caption: \(data["caption"] as? String ?? "")
""")
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

    func softDelete(_ video: Video) async {
        logger.debug("🔴 ProfileViewModel: Starting soft delete for video \(video.id)")
        isLoading = true
        do {
            // Optimistically update UI
            await MainActor.run {
                if let index = videos.firstIndex(where: { $0.id == video.id }) {
                    var updatedVideo = video
                    updatedVideo.isDeleted = true
                    videos[index] = updatedVideo
                }
            }
            
            // Then update database
            try await databaseManager.softDeleteVideo(video.id)
            // Still refresh to ensure consistency
            await forceRefreshVideos()
        } catch {
            // Revert on error
            await forceRefreshVideos()
            logger.error("❌ ProfileViewModel: Failed to delete: \(error.localizedDescription)")
            self.error = error
        }
        isLoading = false
    }

    func restore(_ video: Video) async {
        isLoading = true
        do {
            // Optimistically update UI
            await MainActor.run {
                if let index = videos.firstIndex(where: { $0.id == video.id }) {
                    var updatedVideo = video
                    updatedVideo.isDeleted = false
                    videos[index] = updatedVideo
                }
            }
            
            // Then update database
            try await databaseManager.restoreVideo(video.id)
            // Still refresh to ensure consistency
            await forceRefreshVideos()
        } catch {
            // Revert on error
            await forceRefreshVideos()
            self.error = error
        }
        isLoading = false
    }
}
