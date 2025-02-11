import SwiftUI
import PhotosUI

struct VideoUploadView: View {
    @StateObject private var viewModel = VideoUploadViewModel()
    @State private var showingPhotoPicker = false
    @Environment(\.dismiss) private var dismiss
    @State private var showingQualityPicker = false

    private var computedThumbnails: [UIImage] {
        let selectedURLs: [URL] = viewModel.selectedVideoURLs
        let thumbnailsDict: [URL: UIImage] = viewModel.thumbnails
        var thumbnails: [UIImage] = []
        for url in selectedURLs {
            if let image = thumbnailsDict[url] {
                thumbnails.append(image)
            }
        }
        return thumbnails
    }

    private var previewSection: some View {
        MultiVideoPreviewSection(
            thumbnails: computedThumbnails,
            onTap: { showingPhotoPicker = true }
        )
    }

    private var uploadStack: some View {
        VStack(spacing: 20) {
            previewSection
            CaptionInputField(
                caption: $viewModel.caption,
                isEnabled: !viewModel.isUploading
            )

            if !viewModel.selectedVideoURLs.isEmpty {
                Text("Selected Videos: \(viewModel.selectedVideoURLs.count)")
                    .foregroundColor(.secondary)
            }

            UploadProgressSection(
                isUploading: viewModel.isUploading,
                progress: viewModel.uploadProgress,
                onCancel: { viewModel.cancelUpload() }
            )
            .allowsHitTesting(true)

            UploadButton(
                isUploading: viewModel.isUploading,
                hasVideo: !viewModel.selectedVideoURLs.isEmpty,
                action: viewModel.uploadVideos
            )

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundColor(error.hasPrefix("✅") ? .green : .red)
                    .padding()
            }

            Spacer()
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                uploadStack
            }
            .navigationTitle("Upload Videos")
            .navigationDestination(isPresented: $viewModel.shouldNavigateToProfile) {
                ProfileView()
            }
            .sheet(isPresented: $showingPhotoPicker) {
                VideoPicker(selectedVideoURLs: $viewModel.selectedVideoURLs, viewModel: viewModel)
            }
            .disabled(viewModel.isUploading && !viewModel.shouldNavigateToProfile)

            // Overlay cancel button when uploading
            if viewModel.isUploading {
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
                .onAppear {
                    print("📱 Cancel overlay appeared")
                }
            }
        }
        .onChange(of: viewModel.shouldNavigateToProfile) { _, shouldNavigate in
            if shouldNavigate {
                dismiss()
            }
        }
        .onChange(of: viewModel.selectedVideoURLs) { _, newValue in
            if !newValue.isEmpty {
                showingQualityPicker = true
            }
        }
    }
}

// MARK: - Subviews

struct MultiVideoPreviewSection: View {
    let thumbnails: [UIImage]
    let onTap: () -> Void

    var body: some View {
        Group {
            if !thumbnails.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(thumbnails, id: \.self) { thumbnail in
                            Image(uiImage: thumbnail)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 150)
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                }
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
