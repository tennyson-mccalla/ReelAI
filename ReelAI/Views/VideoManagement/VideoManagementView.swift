import SwiftUI

struct VideoManagementView: View {
    @StateObject private var viewModel = VideoManagementViewModel()
    @State private var showingDeleteConfirmation = false
    @State private var selectedVideoId: String?

    var body: some View {
        Group {
            if viewModel.videos.isEmpty {
                ContentUnavailableStateView(state: .empty)
            } else {
                List {
                    ForEach(viewModel.videos) { video in
                        HStack {
                            VideoThumbnailView(video: video)
                                .frame(width: 80, height: 120)
                                .cornerRadius(8)

                            VStack(alignment: .leading, spacing: 8) {
                                Text(video.caption)
                                    .lineLimit(2)
                                Text(video.createdAt.formatted())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Menu {
                                if video.isDeleted {
                                    Button {
                                        Task {
                                            await viewModel.restore(video.id)
                                        }
                                    } label: {
                                        Label("Restore", systemImage: "arrow.counterclockwise")
                                    }
                                } else {
                                    Button(role: .destructive) {
                                        selectedVideoId = video.id
                                        showingDeleteConfirmation = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }

                                    Button {
                                        Task {
                                            await viewModel.updatePrivacy(video.id, isPrivate: video.privacyLevel != .private)
                                        }
                                    } label: {
                                        Label(
                                            video.privacyLevel == .private ? "Make Public" : "Make Private",
                                            systemImage: video.privacyLevel == .private ? "lock.open" : "lock"
                                        )
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    await viewModel.fetchVideos()
                }
            }
        }
        .alert("Delete Video", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let videoId = selectedVideoId {
                    Task {
                        await viewModel.softDelete(videoId)
                    }
                }
            }
        } message: {
            Text("Are you sure you want to delete this video? This action can be undone later.")
        }
    }
}

#Preview {
    NavigationStack {
        VideoManagementView()
    }
}
