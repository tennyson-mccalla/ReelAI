import SwiftUI
import FirebaseStorage
import FirebaseDatabase

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: EditProfileViewModel
    @State private var showingPhotoPicker = false

    init(profile: UserProfile,
         storage: StorageManager = FirebaseStorageManager(),
         database: DatabaseManager = FirebaseDatabaseManager()) {
        _viewModel = StateObject(wrappedValue: EditProfileViewModel(
            profile: profile,
            storage: storage,
            database: database
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
            HStack {
                AsyncImage(url: photoURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Color.gray.opacity(0.2)
                }
                .frame(width: 60, height: 60)
                .clipShape(Circle())
                .overlay {
                    if isLoading {
                        ProgressView()
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }

                Text("Change Photo")
                    .foregroundColor(.accentColor)
            }
        }
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
