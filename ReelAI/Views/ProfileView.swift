import SwiftUI
import os
import FirebaseAuth
import FirebaseStorage
import FirebaseDatabase

struct ProfileView: View {
    @StateObject private var viewModel: ProfileViewModel
    @EnvironmentObject private var authViewModel: AuthViewModel
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
        NavigationView {
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
    }
}

#if DEBUG
struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView()
    }
}
#endif
