import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseDatabase
import FirebaseStorage
import os

/// Manages profile data and video content for a user
@MainActor
class ProfileViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published private(set) var videos: [Video] = []
    @Published private(set) var error: Error?
    @Published private(set) var isLoading = false
    @Published private(set) var profile: UserProfile

    // MARK: - Private Properties
    private var hasLoadedVideos = false
    private var cachedVideos: [Video]?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReelAI", category: "ProfileViewModel")
    private let videoLoader: ProfileVideoLoader
    private let profileManager: ProfileManager

    // MARK: - Dependencies
    let authService: AuthServiceProtocol
    let storageManager: StorageManager
    let databaseManager: DatabaseManager

    // MARK: - Initialization
    init(
        authService: AuthServiceProtocol,
        storage: StorageManager,
        database: DatabaseManager
    ) {
        self.authService = authService
        self.storageManager = storage
        self.databaseManager = database

        // Initialize with temporary profile
        if let userId = authService.currentUser?.uid {
            self.profile = UserProfile(
                id: userId,
                displayName: authService.currentUser?.displayName ?? "New User",
                bio: "",
                photoURL: authService.currentUser?.photoURL,
                socialLinks: []
            )
        } else {
            self.profile = UserProfile.mock
        }

        // Initialize managers
        self.videoLoader = ProfileVideoLoader(database: database, logger: logger)
        self.profileManager = ProfileManager(database: database, auth: authService)

        setupObservers()
        Task { await loadProfile() }
    }

    private func setupObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clearCache),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    @objc private func clearCache() {
        Task {
            cachedVideos = nil
            await loadVideos()
        }
    }

    // MARK: - Profile Management
    func loadProfile() async {
        do {
            let loadedProfile = try await profileManager.loadProfile()
            await updateProfile(with: loadedProfile)
        } catch {
            logger.error("Failed to load profile: \(error.localizedDescription)")
            await createFallbackProfile()
        }
    }

    private func updateProfile(with loadedProfile: UserProfile) async {
        await MainActor.run {
            logger.debug("🔄 Updating profile - Old photo URL: \(String(describing: self.profile.photoURL))")
            logger.debug("🔄 New photo URL: \(String(describing: loadedProfile.photoURL))")

            // Compare URLs including tokens to detect new versions
            let hasPhotoChanged = {
                guard let oldURL = self.profile.photoURL,
                      let newURL = loadedProfile.photoURL else {
                    let changed = self.profile.photoURL?.absoluteString != loadedProfile.photoURL?.absoluteString
                    logger.debug("📊 URL comparison (nil case) - Changed: \(changed)")
                    return changed
                }

                // Compare full URLs including tokens
                let changed = oldURL.absoluteString != newURL.absoluteString
                logger.debug("📊 URL comparison:")
                logger.debug("- Old URL: \(oldURL)")
                logger.debug("- New URL: \(newURL)")
                logger.debug("- Changed: \(changed)")
                return changed
            }()

            self.profile = loadedProfile
            objectWillChange.send()
            logger.debug("📢 Sent objectWillChange")

            // Only post notification if the photo URL actually changed
            if hasPhotoChanged {
                logger.debug("🖼️ Photo URL changed, posting notification")
                NotificationCenter.default.post(
                    name: Notification.Name("ProfilePhotoUpdated"),
                    object: loadedProfile.photoURL
                )
                logger.debug("✅ Posted ProfilePhotoUpdated notification with URL: \(String(describing: loadedProfile.photoURL))")
            } else {
                logger.debug("ℹ️ Photo URL unchanged, skipping notification")
            }
        }
    }

    private func createFallbackProfile() async {
        guard let userId = authService.currentUser?.uid else { return }

        let newProfile = UserProfile(
            id: userId,
            displayName: authService.currentUser?.displayName ?? "New User",
            bio: "",
            photoURL: authService.currentUser?.photoURL,
            socialLinks: []
        )

        do {
            try await databaseManager.updateProfile(newProfile)
            await updateProfile(with: newProfile)
        } catch {
            logger.error("Failed to create fallback profile: \(error.localizedDescription)")
        }
    }

    // MARK: - Profile Photo Management
    func forceRefreshProfilePhoto() async {
        logger.debug("🔄 Force refreshing profile photo")
        do {
            let updatedProfile = try await profileManager.loadProfile()
            logger.debug("✅ Loaded updated profile with photo URL: \(String(describing: updatedProfile.photoURL))")
            await updateProfile(with: updatedProfile)
        } catch {
            logger.error("❌ Failed to refresh profile photo: \(error.localizedDescription)")
        }
    }

    // MARK: - Video Management
    func loadVideos() async {
        guard !isLoading else { return }
        guard let userId = authService.currentUser?.uid else { return }

        isLoading = true

        do {
            let loadedVideos = try await videoLoader.loadVideos(for: userId)
            await updateVideos(with: loadedVideos)
        } catch {
            await handleVideoLoadError(error)
        }
    }

    private func updateVideos(with videos: [Video]) async {
        await MainActor.run {
            self.videos = videos.sorted { $0.createdAt > $1.createdAt }
            self.cachedVideos = self.videos
            isLoading = false
            hasLoadedVideos = true
        }
    }

    private func handleVideoLoadError(_ error: Error) async {
        await MainActor.run {
            self.error = error
            logger.error("Failed to load videos: \(error.localizedDescription)")
            isLoading = false
        }
    }

    func softDelete(_ video: Video) async {
        do {
            try await databaseManager.softDeleteVideo(video.id)
            await forceRefreshVideos()
        } catch {
            logger.error("Failed to soft delete video: \(error.localizedDescription)")
            self.error = error
        }
    }

    func restore(_ video: Video) async {
        do {
            try await databaseManager.restoreVideo(video.id)
            await forceRefreshVideos()
        } catch {
            logger.error("Failed to restore video: \(error.localizedDescription)")
            self.error = error
        }
    }

    func forceRefreshVideos() async {
        logger.debug("Force refreshing videos")
        hasLoadedVideos = false
        cachedVideos = nil
        await loadVideos()
    }

    // MARK: - Convenience Initializer
    convenience init(authService: AuthServiceProtocol) {
        self.init(
            authService: authService,
            storage: FirebaseStorageManager(),
            database: FirebaseDatabaseManager.shared
        )
    }
}

// MARK: - Profile Manager
private actor ProfileManager {
    private let database: DatabaseManager
    private let auth: AuthServiceProtocol

    init(database: DatabaseManager, auth: AuthServiceProtocol) {
        self.database = database
        self.auth = auth
    }

    func loadProfile() async throws -> UserProfile {
        guard let userId = auth.currentUser?.uid else {
            throw NSError(domain: "ProfileError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        return try await database.fetchProfile(userId: userId)
    }
}

// MARK: - Video Loader
private actor ProfileVideoLoader {
    private let database: DatabaseManager
    private let logger: Logger

    init(database: DatabaseManager, logger: Logger) {
        self.database = database
        self.logger = logger
    }

    func loadVideos(for userId: String) async throws -> [Video] {
        logger.info("Starting to load videos")

        let videos = try await database.fetchVideos(limit: 50, after: nil)
        let userVideos = videos.filter { $0.userId == userId }
        logger.info("Loaded \(userVideos.count) videos for user \(userId)")

        return userVideos
    }
}
