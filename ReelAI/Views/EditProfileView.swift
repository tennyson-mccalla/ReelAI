import SwiftUI
import FirebaseStorage
import FirebaseDatabase
import FirebaseAuth
import Photos
import PhotosUI
import os

/// @deprecated Use `ProfileActorView` instead. This view will be removed in a future update.
@available(*, deprecated, message: "Use ProfileActorView instead")
struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: EditProfileViewModel
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReelAI", category: "EditProfileView")

    init(profile: UserProfile,
         storage: StorageManager,
         databaseManager: DatabaseManager,
         authService: FirebaseAuthService) {
        logger.debug("📱 Initializing EditProfileView")
        _viewModel = StateObject(wrappedValue: EditProfileViewModel(
            profile: profile,
            storage: storage,
            database: databaseManager,
            authService: authService,
            databaseManager: databaseManager
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Photo picker button
                    ProfilePhotoView(
                        photoManager: ProfilePhotoManager(
                            storage: viewModel.storage,
                            database: viewModel.databaseManager,
                            userId: viewModel.profile.id
                        ),
                        photoURL: viewModel.profile.photoURL,
                        size: 120
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

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
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            do {
                                try await viewModel.updateProfile()
                                dismiss()
                            } catch {
                                viewModel.updateError(error)
                            }
                        }
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .task {
                logger.debug("🔐 Checking photo library authorization")
                let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
                logger.debug("📸 Photo library status: \(status.rawValue)")
            }
            .alert(
                viewModel.error?.localizedDescription ?? "Error",
                isPresented: Binding(
                    get: { viewModel.error != nil },
                    set: { if !$0 { viewModel.updateError(nil) } }
                ),
                actions: {
                    Button("OK") {
                        viewModel.updateError(nil)
                    }
                },
                message: {
                    if let error = viewModel.error as? LocalizedError {
                        Text(error.recoverySuggestion ?? "")
                    }
                }
            )
            .disabled(viewModel.isLoading)
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

// MARK: - Equatable Conformance
extension UserProfile: Equatable {
    static func == (lhs: UserProfile, rhs: UserProfile) -> Bool {
        lhs.id == rhs.id &&
        lhs.displayName == rhs.displayName &&
        lhs.bio == rhs.bio &&
        lhs.photoURL == rhs.photoURL &&
        lhs.socialLinks == rhs.socialLinks
    }
}

extension UserProfile.SocialLink: Equatable {
    static func == (lhs: UserProfile.SocialLink, rhs: UserProfile.SocialLink) -> Bool {
        lhs.platform == rhs.platform &&
        lhs.url == rhs.url
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
