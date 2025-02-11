import SwiftUI
import PhotosUI

struct VideoUploadView: View {
    @StateObject private var viewModel = VideoUploadViewModel()
    @State private var showingPhotoPicker = false
    @Environment(\.dismiss) private var dismiss
    @State private var showingQualityPicker = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    if viewModel.selectedVideoURLs.isEmpty {
                        VideoPlaceholderView()
                            .onTapGesture { showingPhotoPicker = true }
                    } else {
                        VStack(spacing: 15) {
                            ForEach(viewModel.selectedVideoURLs, id: \.self) { url in
                                VideoUploadItemView(
                                    url: url,
                                    thumbnail: viewModel.thumbnails[url],
                                    caption: Binding(
                                        get: { viewModel.captions[url] ?? "" },
                                        set: { viewModel.captions[url] = $0 }
                                    ),
                                    uploadStatus: viewModel.uploadStatuses[url] ?? .pending,
                                    onCancel: {
                                        viewModel.cancelUpload(for: url)
                                    }
                                )
                            }
                        }

                        Text("Selected Videos: \(viewModel.selectedVideoURLs.count)")
                            .foregroundColor(.secondary)
                            .padding(.top, 5)
                    }

                    UploadButton(
                        isUploading: viewModel.isUploading,
                        hasVideo: !viewModel.selectedVideoURLs.isEmpty,
                        action: viewModel.uploadVideos
                    )
                    .padding(.horizontal)

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .foregroundColor(error.hasPrefix("✅") ? .green : .red)
                            .padding()
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Upload Videos")
            .navigationDestination(isPresented: $viewModel.shouldNavigateToProfile) {
                ProfileView()
            }
            .sheet(isPresented: $showingPhotoPicker) {
                VideoPicker(selectedVideoURLs: $viewModel.selectedVideoURLs, viewModel: viewModel)
            }
            .disabled(viewModel.isUploading && !viewModel.shouldNavigateToProfile)
        }
        .onChange(of: viewModel.shouldNavigateToProfile) { _, shouldNavigate in
            if shouldNavigate {
                dismiss()
            }
        }
    }
}

struct VideoUploadItemView: View {
    let url: URL
    let thumbnail: UIImage?
    @Binding var caption: String
    let uploadStatus: UploadStatus
    let onCancel: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 120, height: 120)
                    .cornerRadius(8)
            }

            VStack(alignment: .leading, spacing: 8) {
                TextField("Add caption for this video...", text: $caption)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                switch uploadStatus {
                case .pending:
                    Text("Pending")
                        .foregroundColor(.secondary)
                case .uploading(let progress):
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: progress) {
                            HStack {
                                Text("Uploading... \(Int(progress * 100))%")
                                Spacer()
                                Button(action: onCancel) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                case .completed(let url):
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Uploaded")
                            .foregroundColor(.green)
                    }
                case .failed(let error):
                    HStack {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.red)
                        Text(error.localizedDescription)
                            .foregroundColor(.red)
                            .lineLimit(2)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }
}

// MARK: - Subviews

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
            Text("Upload")
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
