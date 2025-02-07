import SwiftUI
import FirebaseAuth
import os

struct ProfileView: View {
    @StateObject private var viewModel: ProfileViewModel
    @Environment(\.refresh) private var refresh
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var isEditingProfile = false
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 1), count: 3)
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReelAI", category: "ProfileView")
    
    init(viewModel: ProfileViewModel? = nil) {
        let wrappedValue = viewModel ?? ProfileViewModel(
            authService: FirebaseAuthService()
        )
        _viewModel = StateObject(wrappedValue: wrappedValue)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Profile Header
                VStack(spacing: 12) {
                    // Profile Photo
                    AsyncImage(url: viewModel.profile.photoURL) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .foregroundColor(.gray)
                    }
                    .frame(width: 100, height: 100)
                    .clipShape(Circle())

                    // Display Name
                    Text(viewModel.profile.displayName)
                        .font(.title2)
                        .bold()

                    // Bio if available
                    if !viewModel.profile.bio.isEmpty {
                        Text(viewModel.profile.bio)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    // Email
                    if let email = viewModel.authService.currentUser?.email {
                        Text(email)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top)

                // Sign Out Button
                Button("Sign Out") {
                    authViewModel.signOut()
                }
                .foregroundColor(.red)
                .padding()

                // Video Grid
                LazyVGrid(columns: columns, spacing: 1) {
                    if !viewModel.videos.isEmpty {
                        ForEach(viewModel.videos) { video in
                            VideoThumbnailView(video: video)
                                .aspectRatio(9/16, contentMode: .fill)
                                .clipped()
                        }
                    } else if viewModel.isLoading {
                        // Show placeholder grid items while loading
                        ForEach(0..<12, id: \.self) { _ in
                            Color.gray.opacity(0.3)
                                .aspectRatio(9/16, contentMode: .fill)
                                .overlay {
                                    ProgressView()
                                }
                        }
                    }
                }
                .padding(1)
                
                if viewModel.isLoading && !viewModel.videos.isEmpty {
                    ProgressView()
                        .padding()
                }
                
                if let error = viewModel.error {
                    Text("Error: \(error.localizedDescription)")
                        .foregroundColor(.red)
                        .padding()
                }
            }
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
        .refreshable {
            // Force refresh when user explicitly pulls to refresh
            await viewModel.forceRefreshVideos()
        }
        .task {
            // Initial load only
            await viewModel.loadVideos()
        }
        .onChange(of: authViewModel.isAuthenticated) { _, _ in
            // Reload when auth state changes
            Task { 
                await viewModel.forceRefreshVideos()
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") {
                    isEditingProfile = true
                }
            }
        }
        .sheet(isPresented: $isEditingProfile) {
            // Refresh profile after dismissing edit sheet
            Task {
                await viewModel.loadProfile()
                await viewModel.loadVideos()
            }
        } content: {
            EditProfileView(
                profile: viewModel.profile,
                storage: viewModel.storageManager,
                database: viewModel.databaseManager
            )
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
