import SwiftUI
import os

@MainActor
final class VideoManagementViewModel: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    @Published private(set) var isInitialized = false

    private var authService: AuthServiceProtocol
    private var storageManager: StorageManager
    private var databaseManager: ReelDB.Manager?
    private let logger: Logger

    init(
        authService: AuthServiceProtocol = FirebaseAuthService.shared,
        storageManager: StorageManager = FirebaseStorageManager()
    ) {
        self.authService = authService
        self.storageManager = storageManager
        self.logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "ReelAI",
            category: "VideoManagement"
        )
    }

    // Async initialization
    func initialize() async {
        guard !isInitialized else { return }
        do {
            let dbManager = await FirebaseDatabaseManager.shared
            self.databaseManager = dbManager
            self.isInitialized = true
        } catch {
            self.error = error
            logger.error("Failed to initialize VideoManagementViewModel: \(error.localizedDescription)")
        }
    }

    // Helper to ensure database manager is available
    private var db: ReelDB.Manager {
        guard let db = databaseManager else {
            fatalError("VideoManagementViewModel not initialized. Call initialize() first.")
        }
        return db
    }

    // Convenience initializer that handles actor isolation
    static func create() async -> VideoManagementViewModel {
        let viewModel = await MainActor.run {
            VideoManagementViewModel(
                authService: FirebaseAuthService.shared,
                storageManager: FirebaseStorageManager()
            )
        }
        await viewModel.initialize()
        return viewModel
    }

    func softDelete(_ video: Video) async {
        guard isInitialized else { return }
        isLoading = true
        error = nil

        do {
            try await db.softDeleteVideo(video.id)
        } catch {
            self.error = error
        }

        isLoading = false
    }

    func restore(_ video: Video) async {
        guard isInitialized else { return }
        isLoading = true
        error = nil

        do {
            try await db.restoreVideo(video.id)
        } catch {
            self.error = error
        }

        isLoading = false
    }

    func updatePrivacy(_ video: Video, to privacyLevel: Video.PrivacyLevel) async {
        guard isInitialized else { return }
        isLoading = true
        logger.debug("🔒 Updating privacy for video \(video.id) to \(String(describing: privacyLevel))")

        do {
            try await db.updateVideoPrivacy(video.id, privacyLevel: privacyLevel)
            logger.debug("✅ Privacy updated successfully")
        } catch {
            self.error = error
            logger.error("❌ Failed to update privacy: \(error.localizedDescription)")
        }

        isLoading = false
    }

    func updateCaption(_ video: Video, to caption: String) async {
        guard isInitialized else { return }
        isLoading = true
        logger.debug("📝 Updating caption for video \(video.id)")

        do {
            try await db.updateVideoMetadata(video.id, caption: caption)
            logger.debug("✅ Caption updated successfully")
        } catch {
            self.error = error
            logger.error("❌ Failed to update caption: \(error.localizedDescription)")
        }

        isLoading = false
    }
}
