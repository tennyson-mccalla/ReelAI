import SwiftUI

struct VideoManagementView: View {
    let video: Video
    @StateObject private var viewModel: VideoManagementViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirmation = false
    @State private var showingCaptionEditor = false
    @State private var editedCaption: String
    @State private var currentPrivacyLevel: Video.PrivacyLevel

    init(video: Video) {
        self.video = video
        // Create a temporary view model that will be initialized in task
        self._viewModel = StateObject(wrappedValue: VideoManagementViewModel())
        self._editedCaption = State(initialValue: video.caption)
        self._currentPrivacyLevel = State(initialValue: video.privacyLevel)
    }

    var body: some View {
        Group {
            if !viewModel.isInitialized {
                ProgressView("Loading...")
                    .task {
                        await viewModel.initialize()
                    }
            } else {
                mainContent
            }
        }
    }

    private var mainContent: some View {
        List {
            // Thumbnail and basic info
            Section {
                HStack {
                    VideoThumbnailView(video: video)
                        .frame(width: 120, height: 160)
                        .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(video.caption)
                            .lineLimit(2)
                        Text(video.createdAt.formatted())
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
                .padding(.vertical, 4)
            }

            // Privacy settings
            Section("Privacy") {
                Picker("Privacy", selection: $currentPrivacyLevel) {
                    ForEach(Video.PrivacyLevel.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .onChange(of: currentPrivacyLevel) { _, newValue in
                    Task {
                        await viewModel.updatePrivacy(video, to: newValue)
                    }
                }
            }

            // Edit options
            Section("Options") {
                Button("Edit Caption") {
                    showingCaptionEditor = true
                }

                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Text(video.isDeleted ? "Restore Video" : "Delete Video")
                }
            }
        }
        .navigationTitle("Edit Video")
        .disabled(viewModel.isLoading)
        .alert("Delete Video?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button(role: .destructive) {
                Task {
                    await viewModel.softDelete(video)
                    dismiss()
                }
            } label: {
                Text("Delete")
            }
        } message: {
            Text("This video will be hidden but can be restored later.")
        }
        .sheet(isPresented: $showingCaptionEditor) {
            CaptionEditorView(
                caption: $editedCaption,
                onSave: { newCaption in
                    Task {
                        await viewModel.updateCaption(video, to: newCaption)
                        dismiss()
                    }
                }
            )
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
    }
}

// MARK: - Helper Views
private struct CaptionEditorView: View {
    @Binding var caption: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                TextField("Caption", text: $caption, axis: .vertical)
                    .lineLimit(3...6)
            }
            .navigationTitle("Edit Caption")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(caption)
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationView {
        VideoManagementView(video: .mock)
    }
}
