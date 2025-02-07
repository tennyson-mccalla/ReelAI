import SwiftUI
import FirebaseStorage

@MainActor
final class EditProfileViewModel: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    @Published var profile: UserProfile

    private let storage: StorageManager
    private let database: DatabaseManager

    init(profile: UserProfile, storage: StorageManager, database: DatabaseManager) {
        self.profile = profile
        self.storage = storage
        self.database = database
    }

    func updateProfile() async throws {
        isLoading = true
        defer { isLoading = false }

        // Validate data
        guard profile.displayName.count >= 3 else {
            throw ValidationError.displayNameTooShort
        }

        try await database.updateProfile(profile)
    }

    func updateProfilePhoto(_ imageData: Data) async throws {
        isLoading = true
        defer { isLoading = false }

        let url = try await storage.uploadProfilePhoto(imageData, userId: profile.id)
        profile.photoURL = url
    }

    func updateError(_ newError: Error?) {
        error = newError
    }

    enum ValidationError: LocalizedError {
        case displayNameTooShort

        var errorDescription: String? {
            switch self {
            case .displayNameTooShort:
                return "Display name must be at least 3 characters"
            }
        }
    }
}
