import SwiftUI
import FirebaseAuth

struct ProfileView: View {
    @StateObject private var viewModel: ProfileViewModel
    @Environment(\.refresh) private var refresh
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var isEditingProfile = false

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
                if !viewModel.videos.isEmpty {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 2) {
                        ForEach(viewModel.videos) { video in
                            VideoThumbnailView(video: video)
                                .aspectRatio(9/16, contentMode: .fill)
                                .clipped()
                        }
                    }
                    .padding(.horizontal, 2)
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
