import SwiftUI
import os  // For logging
import FirebaseAuth  // For auth types

struct ProfileView: View {
    @StateObject private var viewModel: ProfileViewModel
    @EnvironmentObject private var authViewModel: AuthViewModel
    @State private var isEditingProfile = false
    @State private var selectedVideoForEdit: Video?

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReelAI", category: "ProfileView")

    init(viewModel: ProfileViewModel? = nil) {
        let wrappedValue = viewModel ?? ProfileViewModel(
            authService: FirebaseAuthService()
        )
        _viewModel = StateObject(wrappedValue: wrappedValue)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Profile Header
                    VStack(spacing: 16) {
                        // Profile Image
                        if let photoURL = viewModel.profile.photoURL {
                            AsyncImage(url: photoURL) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                Image(systemName: "person.circle.fill")
                                    .resizable()
                            }
                            .frame(width: 80, height: 80)
                            .clipShape(Circle())
                        } else {
                            Image(systemName: "person.circle.fill")
                                .resizable()
                                .frame(width: 80, height: 80)
                                .foregroundColor(.gray)
                        }

                        // Name and Edit Button
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
                    .padding(.top)

                    // Videos Grid
                    if viewModel.isLoading && viewModel.videos.isEmpty {
                        LazyVGrid(columns: columns, spacing: 1) {
                            ForEach(0..<12, id: \.self) { _ in
                                Color.gray.opacity(0.3)
                                    .aspectRatio(9/16, contentMode: .fill)
                            }
                        }
                        .padding(1)
                    } else {
                        LazyVGrid(columns: columns, spacing: 1) {
                            ForEach(viewModel.videos) { video in
                                ProfileGridItem(
                                    video: video,
                                    selectedVideoForEdit: $selectedVideoForEdit,
                                    viewModel: viewModel
                                )
                                .id("\(video.id)-\(video.isDeleted)-\(video.lastEditedAt?.timeIntervalSince1970 ?? 0)")
                            }
                        }
                        .padding(1)
                    }
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            Task {
                                authViewModel.signOut()
                            }
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.title3)
                    }
                }
            }
        }
        .navigationDestination(item: $selectedVideoForEdit) { video in
            VideoManagementView(video: video)
        }
        .refreshable {
            await viewModel.forceRefreshVideos()
        }
        .task {
            await viewModel.loadVideos()
        }
        .onChange(of: authViewModel.isAuthenticated) { _, _ in
            Task {
                await viewModel.forceRefreshVideos()
            }
        }
        .onChange(of: selectedVideoForEdit) { _, video in
            if let video = video {
                logger.debug("📝 Navigation triggered for video: \(video.id)")
            }
        }
        .onChange(of: viewModel.videos) { _, _ in
            logger.debug("📱 Videos updated in view, count: \(viewModel.videos.count)")
        }
        .sheet(isPresented: $isEditingProfile) {
            EditProfileView(
                profile: viewModel.profile,
                storage: viewModel.storageManager,
                database: viewModel.databaseManager
            )
        }
    }
}

// MARK: - Helper Types
private extension ProfileView {
    struct ProfileGridItem: View {
        let video: Video
        @Binding var selectedVideoForEdit: Video?
        @ObservedObject var viewModel: ProfileViewModel
        private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReelAI", category: "ProfileGridItem")

        var body: some View {
            _ = video.isDeleted ? logger.debug("🎭 Showing deleted overlay for video: \(video.id)") : nil

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
                .contextMenu {
                    _ = logger.debug("📋 Context menu for video: \(video.id), isDeleted: \(video.isDeleted)")

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
}

#if DEBUG
struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView()
    }
}
#endif
