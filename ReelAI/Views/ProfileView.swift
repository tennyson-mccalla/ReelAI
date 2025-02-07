import SwiftUI
import os
import FirebaseAuth
import FirebaseStorage
import FirebaseDatabase

struct ProfileView: View {
    @StateObject private var viewModel: ProfileViewModel
<<<<<<< HEAD
    @EnvironmentObject private var authViewModel: AuthViewModel
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReelAI", category: "ProfileView")
=======
    @Environment(\.refresh) private var refresh
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var isEditingProfile = false
    @State private var selectedVideoForEdit: Video?
>>>>>>> be20c0f (Add video management functionality)

    init(viewModel: ProfileViewModel? = nil) {
        let wrappedValue = viewModel ?? ProfileViewModel(
            authService: FirebaseAuthService()
        )
        _viewModel = StateObject(wrappedValue: wrappedValue)
    }

    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    gridContent
                    if viewModel.isLoading && !viewModel.videos.isEmpty {
                        Text("Loading more videos...")
                            .foregroundColor(.secondary)
                            .padding()
                    }

                    if let error = viewModel.error {
                        Text("Error: \(error.localizedDescription)")
                            .foregroundColor(.red)
                            .padding()
                    }
                }

<<<<<<< HEAD
                VStack {
                    Spacer()
                    CacheDebugButtons(viewModel: viewModel)
                        .padding()
=======
                // Sign Out Button
                Button("Sign Out") {
                    authViewModel.signOut()
                }
                .foregroundColor(.red)
                .padding()

                // Video Grid
                if !viewModel.videos.isEmpty {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 2) {
                        ForEach(viewModel.videos) { video in
                            VideoThumbnailView(video: video)
                                .aspectRatio(9/16, contentMode: .fill)
                                .clipped()
                                .contextMenu {
                                    Button {
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
                    .padding(.horizontal, 2)
>>>>>>> be20c0f (Add video management functionality)
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    signOutButton
                }
            }
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
    }

    private var gridContent: some View {
        LazyVGrid(columns: columns, spacing: 1) {
            ForEach(gridItems.indices, id: \.self) { index in
                gridItems[index]
            }
        }
        .padding(1)
    }

    private var gridItems: [ProfileGridItem] {
        if viewModel.videos.isEmpty && viewModel.isLoading {
            return (0..<12).map { _ in
                ProfileGridItem(placeholder: true)
            }
        } else {
            return viewModel.videos.map { video in
                ProfileGridItem(video: video)
            }
        }
    }

    private var signOutButton: some View {
        Button {
            Task {
                authViewModel.signOut()
            }
        } label: {
            Image(systemName: "rectangle.portrait.and.arrow.right")
        }
    }
}

struct CacheDebugButtons: View {
    @ObservedObject var viewModel: ProfileViewModel
    
    var body: some View {
        HStack {
            Button(action: {
                Task {
                    await VideoCacheManager.shared.logCacheStatus()
                }
            }) {
                Label("Cache Status", systemImage: "info.circle")
                    .padding(8)
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }

            Button(action: {
                Task {
                    try? await VideoCacheManager.shared.clearCache()
                    // Reload is faster because videos are already in memory,
                    // we just need to reload thumbnails from network
                    await viewModel.loadVideos()
                }
            }) {
                Label("Clear Cache", systemImage: "trash")
                    .padding(8)
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
    }
}

// MARK: - Helper Types
private extension ProfileView {
    struct ProfileGridItem: View {
        let video: Video?
        let isPlaceholder: Bool

        init(video: Video) {
            self.video = video
            self.isPlaceholder = false
        }

        init(placeholder: Bool) {
            self.video = nil
            self.isPlaceholder = placeholder
        }

        var body: some View {
            if isPlaceholder {
                Color.gray.opacity(0.3)
                    .aspectRatio(9/16, contentMode: .fill)
            } else if let video = video {
                NavigationLink {
                    VideoDetailsView(video: video)
                } label: {
                    VideoThumbnailView(video: video)
                        .aspectRatio(9/16, contentMode: .fill)
                        .clipped()
                }
            }
        }
    }

    struct VideoDetailsView: View {
        let video: Video

        var body: some View {
            ScrollView {
                VStack(spacing: 16) {
                    VideoThumbnailView(video: video)
                        .aspectRatio(9/16, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipped()

                    VStack(alignment: .leading, spacing: 8) {
                        Text(video.caption)
                            .font(.headline)

                        Text("Created: \(video.createdAt.formatted())")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            Image(systemName: "heart")
                            Text("\(video.likes)")

                            Image(systemName: "message")
                            Text("\(video.comments)")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .padding()
                }
            }
            .navigationTitle("Video Details")
        }
        .navigationDestination(item: $selectedVideoForEdit) { video in
            VideoManagementView(video: video)
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
