import SwiftUI

@MainActor
final class VideoManagementViewModel: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?

    private let databaseManager: DatabaseManager

    init(databaseManager: DatabaseManager = FirebaseDatabaseManager()) {
        self.databaseManager = databaseManager
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
        error = nil

        do {
            try await databaseManager.updateVideoPrivacy(video.id, privacyLevel: privacyLevel)
        } catch {
            self.error = error
        }

        isLoading = false
    }

    func updateCaption(_ video: Video, to caption: String) async {
        isLoading = true
        error = nil

        do {
            try await databaseManager.updateVideoMetadata(video.id, caption: caption)
        } catch {
            self.error = error
        }

        isLoading = false
    }
}
