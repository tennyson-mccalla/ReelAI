import Foundation
import SwiftUI
import FirebaseAuth
import os
import PhotosUI

/// @deprecated Use `ProfileActorViewModel` instead. This class will be removed in a future update.
@MainActor
@available(*, deprecated, message: "Use ProfileActorViewModel instead")
final class EditProfileViewModel: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    @Published var profile: UserProfile

    let storage: StorageManager
    let databaseManager: DatabaseManager
    private let database: DatabaseManager
    private let authService: FirebaseAuthService
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "EditProfileViewModel")

    init(profile: UserProfile,
         storage: StorageManager,
         database: DatabaseManager,
         authService: FirebaseAuthService,
         databaseManager: DatabaseManager) {
        self.profile = profile
        self.storage = storage
        self.database = database
        self.authService = authService
        self.databaseManager = databaseManager
    }

    func updateProfile() async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            // Validate data
            guard profile.displayName.count >= 3 else {
                throw ValidationError.displayNameTooShort
            }

            // Update profile in database
            try await databaseManager.updateProfile(profile)

            // Force a sync to ensure we have latest data
            try await forceSyncProfile()
        } catch {
            self.error = error
            throw error
        }
    }

    private func forceSyncProfile() async throws {
        guard let userId = authService.currentUser?.uid else { return }
        let freshProfile = try await databaseManager.fetchProfile(userId: userId)
        await MainActor.run {
            self.profile = freshProfile
        }
    }

    func updateError(_ newError: Error?) {
        error = newError
    }

    enum ValidationError: LocalizedError {
        case displayNameTooShort
        case invalidImageData

        var errorDescription: String? {
            switch self {
            case .displayNameTooShort:
                return "Display name must be at least 3 characters"
            case .invalidImageData:
                return "Invalid image data. Image must be less than 5MB"
            }
        }
    }

    enum ProfileError: Error {
        case notAuthenticated
        case updateFailed
    }
}
