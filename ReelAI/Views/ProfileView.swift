import SwiftUI
import PhotosUI

struct ProfileView: View {
    @StateObject private var viewModel = ProfileViewModel()
    @State private var photoPickerItem: PhotosPickerItem?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                profileHeader
                profileInfo
                videoGrid
            }
            .padding()
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if viewModel.viewState.isEditing {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        viewModel.cancelEditing()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        viewModel.saveChanges()
                    }
                    .disabled(!viewModel.canSave)
                }
            } else {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Edit") {
                        viewModel.startEditing()
                    }
                    .disabled(viewModel.viewState.isLoading)
                }
            }
        }
        .onChange(of: photoPickerItem) { _, item in
            if let item {
                viewModel.updatePhoto(item)
                photoPickerItem = nil
            }
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.hasAlert },
            set: { if !$0 { viewModel.dismissAlert() } }
        )) {
            Button("OK") {
                viewModel.dismissAlert()
            }
        } message: {
            Text(viewModel.formattedAlertMessage)
        }
        .task {
            viewModel.loadProfile()
        }
    }

    private var profileHeader: some View {
        let state = viewModel.viewState
        return VStack(spacing: 15) {
            PhotosPicker(selection: $photoPickerItem, matching: .images) {
                ProfilePhotoView(url: state.photoURL)
                    .frame(width: 120, height: 120)
            }
            .disabled(state.isLoading)

            if state.isEditing {
                TextField("Display Name", text: $viewModel.editedDisplayName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                    .multilineTextAlignment(.center)
            } else {
                Text(state.displayName)
                    .font(.title2)
                    .bold()
            }
        }
    }

    private var profileInfo: some View {
        let state = viewModel.viewState
        return Group {
            if state.isEditing {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Username", text: $viewModel.editedUsername)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)

                    TextField("Bio", text: $viewModel.editedBio, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                }
                .padding(.horizontal)
            } else if let bio = state.bio, !bio.isEmpty {
                Text(bio)
                    .font(.body)
            }
        }
    }

    private var videoGrid: some View {
        let state = viewModel.viewState
        return LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 2) {
            ForEach(state.videoThumbnails, id: \.id) { thumbnail in
                AsyncImage(url: thumbnail.url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                }
                .aspectRatio(3/4, contentMode: .fill)
                .clipped()
            }
        }
    }
}

#Preview {
    NavigationStack {
        ProfileView()
    }
}
