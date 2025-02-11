import SwiftUI
import FirebaseStorage
import FirebaseDatabase
import FirebaseAuth

@MainActor
struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: EditProfileViewModel
    @State private var showingPhotoPicker = false

    @MainActor
    init(profile: UserProfile,
         storage: StorageManager,
         databaseManager: DatabaseManager,
         authService: FirebaseAuthService) {
        _viewModel = StateObject(wrappedValue: EditProfileViewModel(
            profile: profile,
            storage: storage,
            database: databaseManager,
            authService: authService,
            databaseManager: databaseManager
        ))
    }

    var body: some View {
        NavigationView { formContent }
    }

    private var formContent: some View {
        Form {
            Section {
                PhotoSelectorButton(
                    photoURL: viewModel.profile.photoURL,
                    isLoading: viewModel.isLoading
                ) { showingPhotoPicker = true }

                TextField("Display Name", text: $viewModel.profile.displayName)
                    .textContentType(.name)

                TextField("Bio", text: $viewModel.profile.bio, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section("Social Links") {
                ForEach($viewModel.profile.socialLinks) { $link in
                    SocialLinkRow(link: $link)
                }

                Button(action: addSocialLink) {
                    Label("Add Social Link", systemImage: "plus.circle.fill")
                }
            }
        }
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task { try await viewModel.updateProfile(); dismiss() }
                }
                .disabled(viewModel.isLoading)
            }
        }
        .sheet(isPresented: $showingPhotoPicker) {
            PhotoPicker { result in
                switch result {
                case .success(let imageData):
                    Task { try await viewModel.updateProfilePhoto(imageData) }
                case .failure(let error):
                    viewModel.updateError(error)
                }
            }
        }
        .alert("Error", isPresented: Binding<Bool>(
            get: { viewModel.error != nil },
            set: { newValue in if !newValue { viewModel.updateError(nil) } }
        )) {
            Button("OK", role: .cancel) { viewModel.updateError(nil) }
        } message: {
            Text(viewModel.error?.localizedDescription ?? "Unknown error")
        }
        .disabled(viewModel.isLoading)
    }

    private func addSocialLink() {
        viewModel.profile.socialLinks.append(
            UserProfile.SocialLink(
                platform: UserProfile.SocialLink.supportedPlatforms[0],
                url: ""
            )
        )
    }
}

private struct PhotoSelectorButton: View {
    let photoURL: URL?
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                // Use AsyncImage with cache-busting technique
                AsyncImage(url: photoWithTimestamp) { image in
                    image.resizable()
                         .aspectRatio(contentMode: .fill)
                         .frame(width: 120, height: 120)
                         .clipShape(Circle())
                } placeholder: {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 120, height: 120)
                        .foregroundColor(.gray)
                }

                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .frame(width: 30, height: 30)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                        .offset(x: -10, y: -10)
                } else {
                    Image(systemName: "pencil.circle.fill")
                        .resizable()
                        .frame(width: 30, height: 30)
                        .background(Color.white)
                        .clipShape(Circle())
                        .offset(x: -10, y: -10)
                }
            }
        }
    }

    // Add a timestamp to force image refresh
    private var photoWithTimestamp: URL? {
        guard let photoURL = photoURL,
              var urlComponents = URLComponents(url: photoURL, resolvingAgainstBaseURL: false) else {
            return photoURL
        }

        // Add a timestamp query parameter to force refresh
        let timestampQuery = URLQueryItem(name: "timestamp", value: "\(Date().timeIntervalSince1970)")
        urlComponents.queryItems = (urlComponents.queryItems ?? []) + [timestampQuery]

        return urlComponents.url
    }
}

private struct SocialLinkRow: View {
    @Binding var link: UserProfile.SocialLink

    var body: some View {
        HStack {
            Menu {
                ForEach(UserProfile.SocialLink.supportedPlatforms, id: \.self) { platform in
                    Button(platform) {
                        link = UserProfile.SocialLink(
                            platform: platform,
                            url: link.url
                        )
                    }
                }
            } label: {
                Text(link.platform)
                    .foregroundColor(.primary)
            }

            TextField("URL", text: $link.url)
                .textContentType(.URL)
                .keyboardType(.URL)
        }
    }
}
