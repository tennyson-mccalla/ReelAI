import SwiftUI
import FirebaseAuth

struct ProfileView: View {
    @StateObject private var viewModel: ProfileViewModel
    @Environment(\.refresh) private var refresh
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var isEditingProfile = false

    init(viewModel: ProfileViewModel? = nil) {
        let wrappedValue = viewModel ?? ProfileViewModel(
            authService: FirebaseAuthService(),
            initialProfile: UserProfile.mock
        )
        _viewModel = StateObject(wrappedValue: wrappedValue)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Sign Out Button
                HStack {
                    Spacer()
                    Button("Sign Out") {
                        authViewModel.signOut()
                    }
                    .foregroundColor(.red)
                    .padding()
                }

                // User Info
                if let email = viewModel.authService.currentUser?.email {
                    Text(email)
                        .font(.headline)
                }

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
            await viewModel.loadVideos()
        }
        .task {
            await viewModel.loadVideos()
        }
        .onChange(of: authViewModel.isAuthenticated) { _, _ in
            Task { await viewModel.loadVideos() }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") {
                    isEditingProfile = true
                }
            }
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

#if DEBUG
struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView()
    }
}
#endif
