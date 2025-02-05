import SwiftUI
import PhotosUI

struct VideoUploadView: View {
    @StateObject private var viewModel = VideoUploadViewModel()
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var showingPhotoPicker = false

    var body: some View {
        NavigationView {
            ZStack {  // Add ZStack to layer views
                VStack(spacing: 20) {
                    SignOutButton(action: authViewModel.signOut)
                    VideoPreviewSection(
                        thumbnail: viewModel.thumbnailImage,
                        onTap: { showingPhotoPicker = true }
                    )
                    CaptionInputField(
                        caption: $viewModel.caption,
                        isEnabled: !viewModel.isUploading
                    )
                    UploadProgressSection(
                        isUploading: viewModel.isUploading,
                        progress: viewModel.uploadProgress,
                        onCancel: viewModel.cancelUpload
                    )
                    .allowsHitTesting(true)  // Allow interaction even when parent is disabled
                    UploadButton(
                        isUploading: viewModel.isUploading,
                        hasVideo: viewModel.selectedVideoURL != nil,
                        action: viewModel.uploadVideo
                    )

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .foregroundColor(error.hasPrefix("✅") ? .green : .red)
                            .padding()
                    }

                    Spacer()
                }
                .navigationTitle("Upload Video")
                .sheet(isPresented: $showingPhotoPicker) {
                    VideoPicker(viewModel: viewModel)
                }
                .disabled(viewModel.isUploading)  // Disable entire view during upload

                // Overlay cancel button when uploading
                if viewModel.isUploading {
                    _ = print("📱 Cancel overlay appeared")  // Print only once
                    VStack {
                        Spacer()
                        Button(action: {
                            print("📱 Cancel button tapped in UI")
                            viewModel.cancelUpload()
                        }) {
                            Text("Cancel Upload")
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.red.opacity(0.8))
                                .cornerRadius(8)
                        }
                        .padding(.bottom, 40)
                    }
                }
            }
        }
    }
}

// MARK: - Subviews

struct SignOutButton: View {
    let action: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Button(action: action) {
                Text("Sign Out")
                    .foregroundColor(.red)
            }
            .padding()
        }
    }
}

struct VideoPreviewSection: View {
    let thumbnail: UIImage?
    let onTap: () -> Void

    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 200)
                    .cornerRadius(12)
            } else {
                VideoPlaceholderView()
                    .onTapGesture(perform: onTap)
            }
        }
    }
}

struct CaptionInputField: View {
    @Binding var caption: String
    let isEnabled: Bool

    var body: some View {
        TextField("Add a caption...", text: $caption)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .padding(.horizontal)
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1.0 : 0.6)
    }
}

struct UploadProgressSection: View {
    let isUploading: Bool
    let progress: Double
    let onCancel: () -> Void

    var body: some View {
        if isUploading {
            VStack {
                ProgressView(value: progress) {
                    HStack {
                        Text("Uploading... \(Int(progress * 100))%")
                        Spacer()
                    }
                }
                .padding()
            }
        }
    }
}

struct UploadButton: View {
    let isUploading: Bool
    let hasVideo: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Upload Video")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .cornerRadius(12)
        }
        .disabled(isUploading || !hasVideo)
        .padding(.horizontal)
    }
}

struct ErrorView: View {
    let message: String

    var body: some View {
        Text(message)
            .foregroundColor(.red)
            .padding()
    }
}

struct VideoPlaceholderView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.2))
                .frame(height: 200)

            VStack(spacing: 8) {
                Image(systemName: "video.fill")
                    .font(.system(size: 40))
                Text("Tap to select video")
                    .font(.caption)
            }
            .foregroundColor(.gray)
        }
        .padding(.horizontal)
    }
}
