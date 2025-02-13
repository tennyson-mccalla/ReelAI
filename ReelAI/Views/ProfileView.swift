import SwiftUI
import os  // For logging
import FirebaseAuth  // For auth types
import FirebaseStorage  // For Firebase Storage

/// @deprecated Use `ProfileActorView` instead. This view will be removed in a future update.
@available(*, deprecated, message: "Use ProfileActorView instead")
struct ProfileView: View {
    @StateObject private var viewModel: ProfileViewModel
    @State private var isEditingProfile = false
    @State private var selectedVideoForEdit: Video?
    @State private var isSignedOut = false
    @State private var signOutError: Error?
    @State private var photoUpdateTimestamp = Date()
    @State private var photoLoadRetryCount = 0
    private let maxPhotoLoadRetries = 3

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReelAI", category: "ProfileView")

    init() {
        let dbManager: ReelDB.Manager = FirebaseDatabaseManager.shared
        _viewModel = StateObject(wrappedValue: ProfileViewModel(
            authService: FirebaseAuthService.shared,
            storage: FirebaseStorageManager(),
            database: dbManager
        ))
    }

    var body: some View {
        Group {
            if isSignedOut {
                signedOutView
            } else {
                mainProfileContent
                    .navigationDestination(item: $selectedVideoForEdit) { video in
                        VideoManagementView(video: video)
                    }
                    .refreshable {
                        logger.debug("♻️ Manual refresh triggered")
                        await viewModel.forceRefreshVideos()
                        await viewModel.forceRefreshProfilePhoto()
                    }
                    .task {
                        await viewModel.loadVideos()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ProfilePhotoUpdated"))) { notification in
                        // Only refresh if we got a new URL
                        guard let newURL = notification.object as? URL else {
                            logger.debug("⚠️ Received notification without URL")
                            return
                        }

                        logger.debug("📱 Received profile photo update notification")
                        logger.debug("🔄 Old URL: \(String(describing: viewModel.profile.photoURL))")
                        logger.debug("🆕 New URL: \(String(describing: newURL))")

                        // Always update on photo change
                        photoUpdateTimestamp = Date()
                        logger.debug("⏰ Updated timestamp to force refresh: \(photoUpdateTimestamp)")

                        Task {
                            logger.debug("🔄 Initiating profile photo refresh")
                            await viewModel.forceRefreshProfilePhoto()
                        }
                    }
                    .sheet(isPresented: $isEditingProfile, onDismiss: {
                        logger.debug("📱 EditProfile sheet dismissed")
                        Task {
                            // Reset retry count on sheet dismiss
                            photoLoadRetryCount = 0
                            await viewModel.forceRefreshProfilePhoto()
                        }
                    }) {
                        EditProfileView(
                            profile: viewModel.profile,
                            storage: viewModel.storageManager,
                            databaseManager: viewModel.databaseManager,
                            authService: FirebaseAuthService.shared
                        )
                    }
                    .alert(isPresented: Binding<Bool>(
                        get: { signOutError != nil },
                        set: { _ in signOutError = nil }
                    )) {
                        Alert(
                            title: Text("Sign Out Error"),
                            message: Text(signOutError?.localizedDescription ?? "Unable to sign out"),
                            dismissButton: .default(Text("OK"))
                        )
                    }
            }
        }
    }

    private var signedOutView: some View {
        Text("Signed Out")
            .transition(.opacity)
    }

    private var mainProfileContent: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    profileHeaderSection
                    videosGridSection
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    profileOptionsMenu
                }
            }
            .navigationDestination(item: $selectedVideoForEdit) { video in
                VideoFeedView(initialVideo: video)
            }
        }
    }

    private var profileOptionsMenu: some View {
        Menu {
            Button(role: .destructive) {
                do {
                    try viewModel.authService.signOut()
                    isSignedOut = true
                } catch {
                    signOutError = error
                }
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.title3)
        }
    }

    private var profileHeaderSection: some View {
        VStack(spacing: 15) {
            // Profile Photo
            ProfilePhotoView(photoURL: viewModel.profile.photoURL, timestamp: photoUpdateTimestamp)
                .frame(width: 120, height: 120)
                .clipShape(Circle())
                .overlay(
                    Circle().stroke(Color.white, lineWidth: 4)
                        .shadow(radius: 7)
                )

            profileNameAndEditButton
        }
        .padding(.top)
    }

    private var profileNameAndEditButton: some View {
        HStack {
            Text(viewModel.profile.displayName)
                .font(.title2)
                .bold()

            Button {
                isEditingProfile = true
            } label: {
                Image(systemName: "pencil.circle")
                    .font(.title2)
            }
        }
    }

    private var videosGridSection: some View {
        Group {
            if viewModel.isLoading && viewModel.videos.isEmpty {
                loadingPlaceholder
            } else {
                videoGridContent
            }
        }
    }

    private var loadingPlaceholder: some View {
        LazyVGrid(columns: columns, spacing: 1) {
            ForEach(0..<12, id: \.self) { _ in
                Color.gray.opacity(0.3)
                    .aspectRatio(9/16, contentMode: .fill)
            }
        }
        .padding(1)
    }

    private var videoGridContent: some View {
        LazyVGrid(columns: columns, spacing: 1) {
            ForEach(viewModel.videos) { video in
                ProfileGridItem(
                    video: video,
                    selectedVideoForEdit: $selectedVideoForEdit,
                    viewModel: viewModel,
                    onVideoTap: { video in
                        selectedVideoForEdit = video
                    }
                )
                .id("\(video.id)-\(video.isDeleted)-\(video.lastEditedAt?.timeIntervalSince1970 ?? 0)")
            }
        }
        .padding(1)
    }
}

// MARK: - Helper Types
private extension ProfileView {
    struct ProfileGridItem: View {
        let video: Video
        @Binding var selectedVideoForEdit: Video?
        @ObservedObject var viewModel: ProfileViewModel
        let onVideoTap: (Video) -> Void
        private let logger: Logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReelAI", category: "ProfileGridItem")

        var body: some View {
            VideoThumbnailView(video: video)
                .aspectRatio(9/16, contentMode: .fill)
                .clipped()
                .overlay {
                    if video.isDeleted {
                        ZStack {
                            Color.black.opacity(0.5)
                            VStack {
                                Image(systemName: "trash.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 30))
                                Text("Deleted")
                                    .foregroundColor(.white)
                                    .font(.caption)
                            }
                        }
                    }
                }
                .onTapGesture {
                    guard !video.isDeleted else { return }
                    onVideoTap(video)
                }
                .contextMenu {
                    Button {
                        logger.debug("🎬 Selected video for edit: \(video.id)")
                        selectedVideoForEdit = video
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }

                    if video.isDeleted {
                        Button {
                            Task {
                                await viewModel.restore(video)
                            }
                        } label: {
                            Label("Restore", systemImage: "arrow.counterclockwise")
                        }
                    } else {
                        Button(role: .destructive) {
                            logger.debug("🔴 ProfileGridItem: Delete button tapped for video \(video.id)")
                            Task {
                                await viewModel.softDelete(video)
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
        }
    }

    private struct ProfilePhotoView: View {
        let photoURL: URL?
        let timestamp: Date
        @State private var image: UIImage?
        @State private var isLoading = true
        private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReelAI", category: "ProfilePhotoView")

        var body: some View {
            ZStack {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .background(Color(.systemBackground))
                } else {
                    fallbackImage
                }

                if isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                }
            }
            .task(id: "\(photoURL?.absoluteString ?? "")-\(timestamp.timeIntervalSince1970)") {
                await loadImage()
            }
            .allowsHitTesting(false)
            .accessibilityLabel("Profile photo")
            .background(Color(.systemBackground))
        }

        private func loadImage() async {
            guard let url = photoURL else {
                isLoading = false
                return
            }

            isLoading = true
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let loadedImage = UIImage(data: data) {
                    await MainActor.run {
                        self.image = loadedImage
                        self.isLoading = false
                    }
                } else {
                    logger.error("Failed to create image from data")
                    isLoading = false
                }
            } catch {
                logger.error("Failed to load profile photo: \(error.localizedDescription)")
                isLoading = false
            }
        }

        private var fallbackImage: some View {
            Image(systemName: "person.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .foregroundColor(.gray)
                .opacity(0.8)
                .background(Color(.systemBackground))
        }
    }
}

#if DEBUG
struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView()
    }
}
#endif
