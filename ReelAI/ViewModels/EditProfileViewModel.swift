import Foundation
import SwiftUI
import FirebaseAuth

@MainActor
final class EditProfileViewModel: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    @Published var profile: UserProfile

    private let storage: StorageManager
    private let database: DatabaseManager
    private let authService: FirebaseAuthService
    private let databaseManager: DatabaseManager

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

    func updateProfilePhoto(_ imageData: Data) async throws {
        guard let userId = authService.currentUser?.uid else {
            throw ProfileError.notAuthenticated
        }

        isLoading = true
        defer { isLoading = false }

        do {
            // Delete existing photo first
            if profile.photoURL != nil {
                try? await storage.deleteFile(at: "profile_photos/\(userId)/profile.jpg")
            }

            // Upload new photo
            let url = try await storage.uploadProfilePhoto(imageData, userId: userId)

            // Update profile with new URL
            var updatedProfile = profile
            updatedProfile.photoURL = url
            try await databaseManager.updateProfile(updatedProfile)

            // Update local state
            await MainActor.run {
                self.profile = updatedProfile
            }

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
