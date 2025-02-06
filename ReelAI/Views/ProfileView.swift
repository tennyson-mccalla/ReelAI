import SwiftUI
import FirebaseAuth

struct ProfileView: View {
    @StateObject private var viewModel: ProfileViewModel
    @Environment(\.refresh) private var refresh
    @EnvironmentObject var authViewModel: AuthViewModel

    init(viewModel: ProfileViewModel? = nil) {
        let wrappedValue = viewModel ?? ProfileViewModel(
            authService: FirebaseAuthService()
        )
        _viewModel = StateObject(wrappedValue: wrappedValue)
    }

    var body: some View {
        ScrollView {
            VStack {
                HStack {
                    Spacer()
                    Button("Sign Out") {
                        authViewModel.signOut()
                    }
                    .foregroundColor(.red)
                    .padding()
                }

                LazyVStack(spacing: 16) {
                    userInfoSection
                    videoGrid
                }
            }
        }
        .refreshable {
            await viewModel.loadVideos()
        }
        .overlay(overlayView)
        .task {
            await viewModel.loadVideos()
        }
        .onChange(of: authViewModel.isAuthenticated) { _ in
            Task {
                await viewModel.loadVideos()
            }
        }
    }

    private var userInfoSection: some View {
        VStack(spacing: 8) {
            if let email = viewModel.authService.currentUser?.email {
                Text(email)
                    .font(.headline)
            }

            Rectangle()
                .fill(.clear)
                .frame(height: 60)
        }
        .padding()
    }

    private var videoGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 2) {
            ForEach(viewModel.videos) { video in
                VideoThumbnailView(video: video)
                    .aspectRatio(9/16, contentMode: .fill)
                    .clipped()
            }
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private var overlayView: some View {
        if viewModel.isLoading {
            ProgressView()
        } else if let error = viewModel.error {
            ContentUnavailableView(
                "Error Loading Videos",
                systemImage: "exclamationmark.triangle",
                description: Text(error.localizedDescription)
            )
        } else if viewModel.videos.isEmpty {
            ContentUnavailableView(
                "No Videos Yet",
                systemImage: "video.slash",
                description: Text("Videos you upload will appear here")
            )
        }
    }
}

struct VideoThumbnailView: View {
    let video: Video

    var body: some View {
        AsyncImage(url: video.thumbnailURL) { phase in
            switch phase {
            case .empty:
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay {
                        ProgressView()
                    }
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .failure:
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay {
                        Image(systemName: "video.fill")
                            .foregroundColor(.gray)
                    }
            @unknown default:
                EmptyView()
            }
        }
    }
}

// MARK: - Preview Provider
struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ProfileView()
                .previewDisplayName("Default State")

            ProfileView(viewModel: ProfileViewModel(
                authService: MockAuthService()
            ))
            .previewDisplayName("Empty State")
        }
    }
}

// MARK: - Mock Services
struct MockAuthService: AuthServiceProtocol {
    var currentUser: User?
}
