import Foundation
import SwiftUI
import os
import FirebaseAuth
import PhotosUI

/// A MainActor-isolated ViewModel that coordinates with ProfileService for all profile operations.
/// This ViewModel will eventually replace ProfileViewModel and EditProfileViewModel.
@MainActor
final class ProfileActorViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    @Published var profile: UserProfile
    @Published private(set) var photoUpdateInProgress = false

    // MARK: - Private Properties

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ReelAI",
        category: "ProfileActorViewModel"
    )

    // MARK: - Dependencies

    private let profileService: ProfileService
    private let authService: AuthServiceProtocol

    // MARK: - Initialization

    init(authService: AuthServiceProtocol = FirebaseAuthService.shared) async {
        self.authService = authService
        self.profileService = await ProfileService.shared

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

        // Setup observers
        setupObservers()

        // Load profile
        Task {
            await loadProfile()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Profile Operations

    /// Loads the user's profile from the service
    func loadProfile() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            guard let userId = authService.currentUser?.uid else {
                throw ProfileError.notAuthenticated
            }

            let loadedProfile = try await profileService.fetchProfile(userId: userId)
            await MainActor.run {
                self.profile = loadedProfile
                self.error = nil
            }

        } catch {
            logger.error("❌ Failed to load profile: \(error.localizedDescription)")
            await MainActor.run {
                self.error = error
            }
        }
    }

    /// Updates the user's profile
    func updateProfile() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            try await profileService.updateProfile(profile)
            await loadProfile() // Reload to ensure we have latest data

        } catch {
            logger.error("❌ Failed to update profile: \(error.localizedDescription)")
            await MainActor.run {
                self.error = error
            }
        }
    }

    /// Updates the user's profile photo
    /// - Parameter imageSelection: The selected image from PhotosPicker
    func updateProfilePhoto(_ imageSelection: PhotosPickerItem?) async {
        guard !photoUpdateInProgress,
              let imageSelection = imageSelection else { return }

        photoUpdateInProgress = true
        defer { photoUpdateInProgress = false }

        do {
            guard let userId = authService.currentUser?.uid else {
                throw ProfileError.notAuthenticated
            }

            // Load and process the image data
            guard let imageData = try await imageSelection.loadTransferable(type: Data.self) else {
                throw ProfileError.invalidData
            }

            // Update the photo through the service
            let photoURL = try await profileService.updateProfilePhoto(imageData, for: userId)

            // Update local profile
            await MainActor.run {
                self.profile.photoURL = photoURL
                self.error = nil
            }

        } catch {
            logger.error("❌ Failed to update profile photo: \(error.localizedDescription)")
            await MainActor.run {
                self.error = error
            }
        }
    }

    // MARK: - Private Methods

    private func setupObservers() {
        // Listen for profile photo updates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleProfilePhotoUpdate),
            name: Notification.Name("ProfilePhotoUpdated"),
            object: nil
        )
    }

    @objc private func handleProfilePhotoUpdate(_ notification: Notification) {
        guard let photoURL = notification.object as? URL else { return }

        Task { @MainActor in
            self.profile.photoURL = photoURL
        }
    }

    // MARK: - Error Types

    enum ProfileError: LocalizedError {
        case notAuthenticated
        case invalidData

        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "You must be signed in to perform this action"
            case .invalidData:
                return "The provided data is invalid"
            }
        }
    }
}
