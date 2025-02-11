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

            print("📝 Updating profile: \(profile)")
            try await database.updateProfile(profile)
            print("✅ Profile update successful")
        } catch {
            print("❌ Profile update failed: \(error)")
            self.error = error
            throw error
        }
    }

    func updateProfilePhoto(_ imageData: Data) async throws {
        guard let userId = authService.currentUser?.uid else {
            print("❌ No user ID")
            throw ProfileError.notAuthenticated
        }

        isLoading = true
        defer { isLoading = false }

        do {
            print("📸 Uploading profile photo")
            print("📊 Image data size: \(imageData.count) bytes")
            
            let url = try await storage.uploadProfilePhoto(imageData, userId: userId)
            
            print("🖼️ Photo uploaded successfully")
            print("📍 Photo URL: \(url)")
            
            // Immediately update the local profile with the new photo URL
            await MainActor.run {
                self.profile.photoURL = url
            }
            
            // Update profile in database
            var updatedProfile = profile
            updatedProfile.photoURL = url
            
            try await databaseManager.updateProfile(updatedProfile)
            
            // Force a reload of the profile
            print("🔄 Forcing profile reload")
            try? await forceSyncProfile()
        } catch {
            print("❌ Profile photo update failed: \(error)")
            print("- Error details: \(error.localizedDescription)")
            self.error = error
            throw error
        }
    }
    
    private func forceSyncProfile() async throws {
        guard let userId = authService.currentUser?.uid else { return }
        
        do {
            let freshProfile = try await databaseManager.fetchProfile(userId: userId)
            
            await MainActor.run {
                print("🔄 Synced Profile:")
                print("- New Photo URL: \(freshProfile.photoURL?.absoluteString ?? "nil")")
                self.profile = freshProfile
            }
        } catch {
            print("❌ Failed to sync profile: \(error)")
            throw error
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
