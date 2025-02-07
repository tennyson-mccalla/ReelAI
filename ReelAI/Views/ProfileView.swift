import SwiftUI
import os
import FirebaseAuth
import FirebaseStorage
import FirebaseDatabase

struct ProfileView: View {
    @StateObject private var viewModel: ProfileViewModel
    @EnvironmentObject private var authViewModel: AuthViewModel
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 1), count: 3)
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReelAI", category: "ProfileView")
    
    init(viewModel: ProfileViewModel? = nil) {
        let wrappedValue = viewModel ?? ProfileViewModel(
            authService: FirebaseAuthService(),
            storageManager: FirebaseStorageManager(),
            databaseManager: FirebaseDatabaseManager()
        )
        _viewModel = StateObject(wrappedValue: wrappedValue)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 1) {
                    ForEach(viewModel.videos.isEmpty && viewModel.isLoading ? (0..<12) : viewModel.videos.indices, id: \.self) { index in
                        if index < viewModel.videos.count {
                            NavigationLink {
                                VideoDetailView(video: viewModel.videos[index])
                            } label: {
                                VideoThumbnailView(video: viewModel.videos[index])
                                    .aspectRatio(9/16, contentMode: .fill)
                                    .clipped()
                            }
                        } else {
                            // Placeholder for initial loading
                            Color.gray.opacity(0.3)
                                .aspectRatio(9/16, contentMode: .fill)
                        }
                    }
                }
                .padding(1)
                
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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task {
                        try await authViewModel.signOut()
                    }
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
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
