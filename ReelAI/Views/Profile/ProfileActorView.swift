import SwiftUI
import PhotosUI
import os

/// A SwiftUI view that uses the actor-based ProfileActorViewModel.
/// This view will eventually replace the current ProfileView.
struct ProfileActorView: View {
    @StateObject private var viewModel: ProfileActorViewModel
    @State private var isEditingProfile = false
    @State private var photoSelection: PhotosPickerItem?
    @State private var signOutError: Error?

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ReelAI",
        category: "ProfileActorView"
    )

    init() {
        // Initialize viewModel using async/await
        let viewModel = Task {
            await ProfileActorViewModel()
        }
        _viewModel = StateObject(wrappedValue: viewModel.result ?? ProfileActorViewModel(authService: FirebaseAuthService.shared))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    profileHeader
                    profileInfo
                }
                .padding()
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Edit") {
                        isEditingProfile = true
                    }
                }
            }
            .sheet(isPresented: $isEditingProfile) {
                editProfileView
            }
            .refreshable {
                await viewModel.loadProfile()
            }
            .alert("Error", isPresented: .constant(viewModel.error != nil)) {
                Button("OK") {
                    viewModel.error = nil
                }
            } message: {
                if let error = viewModel.error {
                    Text(error.localizedDescription)
                }
            }
        }
        .onChange(of: photoSelection) { newValue in
            if let newValue {
                Task {
                    await viewModel.updateProfilePhoto(newValue)
                    photoSelection = nil
                }
            }
        }
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        VStack(spacing: 15) {
            PhotosPicker(selection: $photoSelection, matching: .images) {
                profilePhoto
            }
            .disabled(viewModel.photoUpdateInProgress)

            Text(viewModel.profile.displayName)
                .font(.title2)
                .bold()
        }
    }

    // MARK: - Profile Photo

    private var profilePhoto: some View {
        Group {
            if let photoURL = viewModel.profile.photoURL {
                AsyncImage(url: photoURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    ProgressView()
                }
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .foregroundColor(.gray)
            }
        }
        .frame(width: 120, height: 120)
        .clipShape(Circle())
        .overlay {
            if viewModel.photoUpdateInProgress {
                ProgressView()
                    .frame(width: 120, height: 120)
                    .background(.black.opacity(0.4))
                    .clipShape(Circle())
            }
        }
    }

    // MARK: - Profile Info

    private var profileInfo: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !viewModel.profile.bio.isEmpty {
                Text(viewModel.profile.bio)
                    .font(.body)
            }

            if !viewModel.profile.socialLinks.isEmpty {
                socialLinksView
            }
        }
    }

    private var socialLinksView: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Social Links")
                .font(.headline)

            ForEach(viewModel.profile.socialLinks) { link in
                HStack {
                    Text(link.platform)
                        .fontWeight(.medium)
                    Spacer()
                    Link(link.url, destination: URL(string: link.url)!)
                        .foregroundColor(.blue)
                }
            }
        }
    }

    // MARK: - Edit Profile Sheet

    private var editProfileView: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Display Name", text: $viewModel.profile.displayName)
                    TextField("Bio", text: $viewModel.profile.bio, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Social Links") {
                    ForEach($viewModel.profile.socialLinks) { $link in
                        socialLinkRow(link: $link)
                    }

                    Button {
                        addSocialLink()
                    } label: {
                        Label("Add Social Link", systemImage: "plus.circle.fill")
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isEditingProfile = false
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            await viewModel.updateProfile()
                            isEditingProfile = false
                        }
                    }
                    .disabled(viewModel.isLoading)
                }
            }
        }
    }

    private func socialLinkRow(link: Binding<UserProfile.SocialLink>) -> some View {
        HStack {
            Menu {
                ForEach(UserProfile.SocialLink.supportedPlatforms, id: \.self) { platform in
                    Button(platform) {
                        link.wrappedValue = UserProfile.SocialLink(
                            platform: platform,
                            url: link.wrappedValue.url
                        )
                    }
                }
            } label: {
                Text(link.wrappedValue.platform)
                    .foregroundColor(.primary)
            }

            TextField("URL", text: link.url)
                .textContentType(.URL)
                .keyboardType(.URL)
        }
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
