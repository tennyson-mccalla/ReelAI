import SwiftUI
import os

@MainActor
final class VideoManagementViewModel: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?

    private let databaseManager: DatabaseManager
    private let logger: Logger

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
        self.logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "ReelAI",
            category: "VideoManagement"
        )
    }

    // Convenience initializer that handles actor isolation
    @MainActor
    static func create() -> VideoManagementViewModel {
        return VideoManagementViewModel(databaseManager: FirebaseDatabaseManager.shared)
    }

    func softDelete(_ video: Video) async {
        isLoading = true
        error = nil

        do {
            try await databaseManager.softDeleteVideo(video.id)
        } catch {
            self.error = error
        }

        isLoading = false
    }

    func restore(_ video: Video) async {
        isLoading = true
        error = nil

        do {
            try await databaseManager.restoreVideo(video.id)
        } catch {
            self.error = error
        }

        isLoading = false
    }

    func updatePrivacy(_ video: Video, to privacyLevel: Video.PrivacyLevel) async {
        isLoading = true
        logger.debug("🔒 Updating privacy for video \(video.id) to \(String(describing: privacyLevel))")

        do {
            try await databaseManager.updateVideoPrivacy(video.id, privacyLevel: privacyLevel)
            logger.debug("✅ Privacy updated successfully")
        } catch {
            self.error = error
            logger.error("❌ Failed to update privacy: \(error.localizedDescription)")
        }

        isLoading = false
    }

    func updateCaption(_ video: Video, to caption: String) async {
        isLoading = true
        logger.debug("📝 Updating caption for video \(video.id)")

        do {
            try await databaseManager.updateVideoMetadata(video.id, caption: caption)
            logger.debug("✅ Caption updated successfully")
        } catch {
            self.error = error
            logger.error("❌ Failed to update caption: \(error.localizedDescription)")
        }

        isLoading = false
    }
}
