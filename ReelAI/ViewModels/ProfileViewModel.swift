import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseDatabase
import FirebaseStorage
import os

/// Manages profile data and video content for a user
/// @deprecated Use `ProfileActorViewModel` instead. This class will be removed in a future update.
@MainActor
@available(*, deprecated, message: "Use ProfileActorViewModel instead")
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
    let databaseManager: ReelDB.Manager

    // MARK: - Initialization
    init(
        authService: AuthServiceProtocol,
        storage: StorageManager,
        database: ReelDB.Manager
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
        // Compare URLs including tokens to detect new versions
        let hasPhotoChanged = {
            guard let oldURL = self.profile.photoURL,
                  let newURL = loadedProfile.photoURL else {
                return self.profile.photoURL?.absoluteString != loadedProfile.photoURL?.absoluteString
            }
            return oldURL.absoluteString != newURL.absoluteString
        }()

        self.profile = loadedProfile
        objectWillChange.send()

        // Only post notification if the photo URL actually changed
        if hasPhotoChanged {
            logger.debug("🖼️ Profile photo URL updated, triggering refresh")
            NotificationCenter.default.post(
                name: Notification.Name("ProfilePhotoUpdated"),
                object: loadedProfile.photoURL
            )
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

            // Only create default photo if we haven't just uploaded one
            if updatedProfile.photoURL == nil && !isPhotoBeingProcessed {
                logger.debug("⚠️ No photo URL found and no upload in progress")
                    return
            }

            await updateProfile(with: updatedProfile)
        } catch {
            logger.error("❌ Failed to refresh profile photo: \(error.localizedDescription)")
        }
    }

    // Track photo processing state
    private var isPhotoBeingProcessed = false

    // Helper method to update profile photo
    private func updateProfilePhoto(_ imageData: Data) async throws {
        isPhotoBeingProcessed = true
        defer { isPhotoBeingProcessed = false }

        guard let userId = authService.currentUser?.uid else { return }

        let url = try await storageManager.uploadProfilePhoto(imageData, userId: userId)
        var updatedProfile = profile
        updatedProfile.photoURL = url
        try await databaseManager.updateProfile(updatedProfile)

        await updateProfile(with: updatedProfile)
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
    static func create() async -> ProfileViewModel {
        let database = await FirebaseDatabaseManager.shared
        return ProfileViewModel(
            authService: FirebaseAuthService.shared,
            storage: FirebaseStorageManager(),
            database: database
        )
    }

    convenience init(authService: AuthServiceProtocol) async {
        let database = await FirebaseDatabaseManager.shared
        self.init(
            authService: authService,
            storage: FirebaseStorageManager(),
            database: database
        )
    }
}

// MARK: - Profile Manager
private actor ProfileManager {
    private let database: ReelDB.Manager
    private let auth: AuthServiceProtocol

    init(database: ReelDB.Manager, auth: AuthServiceProtocol) {
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
    private let database: ReelDB.Manager
    private let logger: Logger

    init(database: ReelDB.Manager, logger: Logger) {
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
