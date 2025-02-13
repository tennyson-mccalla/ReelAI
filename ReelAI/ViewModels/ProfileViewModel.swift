import SwiftUI
import FirebaseAuth
import FirebaseStorage
import FirebaseDatabase
import PhotosUI

@MainActor
final class ProfileViewModel: ObservableObject {
    struct ViewState: Equatable {
        var displayName: String = ""
        var username: String = ""
        var bio: String?
        var photoURL: URL?
        var videoThumbnails: [(id: String, url: URL?)] = []
        var isEditing: Bool = false
        var isLoading: Bool = false

        static func == (lhs: ViewState, rhs: ViewState) -> Bool {
            lhs.displayName == rhs.displayName &&
            lhs.username == rhs.username &&
            lhs.bio == rhs.bio &&
            lhs.photoURL == rhs.photoURL &&
            lhs.isEditing == rhs.isEditing &&
            lhs.isLoading == rhs.isLoading &&
            lhs.videoThumbnails.count == rhs.videoThumbnails.count &&
            zip(lhs.videoThumbnails, rhs.videoThumbnails).allSatisfy { lhsTuple, rhsTuple in
                lhsTuple.id == rhsTuple.id && lhsTuple.url == rhsTuple.url
            }
        }
    }

    // Internal state
    private(set) var profile: Profile?
    private var rawVideos: [Video] = []

    // View state
    @Published private(set) var viewState = ViewState()
    @Published var editedDisplayName = ""
    @Published var editedBio = ""
    @Published var editedUsername = ""
    @Published private(set) var alertMessage: String?

    var hasAlert: Bool {
        alertMessage != nil
    }

    var formattedAlertMessage: String {
        alertMessage ?? ""
    }

    var canSave: Bool {
        !viewState.isLoading && !editedDisplayName.isEmpty
    }

    private let storage = Storage.storage().reference()
    private let database = Database.database().reference()
    private let userId: String?

    init(userId: String? = nil) {
        self.userId = userId
    }

    private func updateViewState() {
        viewState = ViewState(
            displayName: profile?.displayName ?? "",
            username: profile?.username ?? "",
            bio: profile?.bio,
            photoURL: profile?.photoURL,
            videoThumbnails: rawVideos.map { (id: $0.id, url: $0.thumbnailURL) },
            isEditing: viewState.isEditing,
            isLoading: viewState.isLoading
        )
    }

    func loadProfile() {
        Task {
            await fetchProfile()
        }
    }

    func startEditing() {
        editedDisplayName = viewState.displayName
        editedUsername = viewState.username
        editedBio = viewState.bio ?? ""
        viewState.isEditing = true
    }

    func cancelEditing() {
        viewState.isEditing = false
        loadProfile()
    }

    func saveChanges() {
        Task {
            await updateProfile(
                displayName: editedDisplayName,
                username: editedUsername.isEmpty ? nil : editedUsername,
                bio: editedBio.isEmpty ? nil : editedBio
            )
            viewState.isEditing = false
        }
    }

    func updatePhoto(_ item: PhotosPickerItem) {
        Task {
            await updateProfilePhoto(item)
        }
    }

    func dismissAlert() {
        alertMessage = nil
    }

    private func fetchProfile() async {
        guard !viewState.isLoading else { return }
        viewState.isLoading = true
        defer { viewState.isLoading = false }

        do {
            self.profile = try await loadUserProfile()
            updateViewState()
            await fetchVideos()
            self.alertMessage = nil
        } catch {
            self.alertMessage = error.localizedDescription
        }
    }

    private func loadUserProfile() async throws -> Profile {
        let targetUserId = userId ?? Auth.auth().currentUser?.uid
        guard let userId = targetUserId else {
            throw ProfileError.notAuthenticated
        }

        let snapshot = try await database.child("users").child(userId).getData()
        guard let data = snapshot.value as? [String: Any] else {
            throw ProfileError.invalidData
        }

        return Profile(userId: userId, data: data)
    }

    private func fetchVideos() async {
        guard let userId = profile?.id else { return }

        do {
            let snapshot = try await database.child("videos")
                .queryOrdered(byChild: "userId")
                .queryEqual(toValue: userId)
                .getData()

            guard let dict = snapshot.value as? [String: [String: Any]] else {
                rawVideos = []
                updateViewState()
                return
            }

            rawVideos = dict.compactMap { key, value in
                var data = value
                data["id"] = key
                return try? Video(dictionary: data)
            }
            .sorted { $0.createdAt > $1.createdAt }

            updateViewState()

        } catch {
            self.alertMessage = "Could not fetch videos: \(error.localizedDescription)"
            rawVideos = []
            updateViewState()
        }
    }

    private func updateProfile(displayName: String, username: String?, bio: String?) async {
        guard !viewState.isLoading else { return }
        guard let userId = profile?.id else { return }

        viewState.isLoading = true
        defer { viewState.isLoading = false }

        do {
            let updates: [String: Any] = [
                "displayName": displayName,
                "username": username as Any,
                "bio": bio as Any
            ]

            try await database.child("users").child(userId).updateChildValues(updates)
            await fetchProfile()

        } catch {
            self.alertMessage = error.localizedDescription
        }
    }

    private func updateProfilePhoto(_ item: PhotosPickerItem) async {
        guard !viewState.isLoading else { return }
        guard let userId = profile?.id else { return }

        viewState.isLoading = true
        defer { viewState.isLoading = false }

        do {
            guard let imageData = try await item.loadTransferable(type: Data.self) else {
                throw ProfileError.invalidData
            }

            let photoRef = storage.child("profile_photos").child(userId).child("profile.jpg")
            _ = try await photoRef.putDataAsync(imageData)
            let downloadURL = try await photoRef.downloadURL()

            try await database.child("users").child(userId).child("photoURL").setValue(downloadURL.absoluteString)
            await fetchProfile()

        } catch {
            self.alertMessage = error.localizedDescription
        }
    }
}
