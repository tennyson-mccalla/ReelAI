import SwiftUI
import PhotosUI

struct VideoUploadView: View {
    @StateObject private var viewModel = VideoUploadViewModel()
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var showingPhotoPicker = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                SignOutButton(action: authViewModel.signOut)
                VideoPreviewSection(
                    thumbnail: viewModel.thumbnailImage,
                    onTap: { showingPhotoPicker = true }
                )
                CaptionInputField(caption: $viewModel.caption)
                UploadProgressSection(
                    isUploading: viewModel.isUploading,
                    progress: viewModel.uploadProgress
                )
                UploadButton(
                    isUploading: viewModel.isUploading,
                    hasVideo: viewModel.selectedVideoURL != nil,
                    action: viewModel.uploadVideo
                )
                
                if let error = viewModel.errorMessage {
                    ErrorView(message: error)
                }
                
                Spacer()
            }
            .navigationTitle("Upload Video")
            .sheet(isPresented: $showingPhotoPicker) {
                VideoPicker(viewModel: viewModel)
            }
            .alert("Upload Complete", isPresented: .init(
                get: { viewModel.uploadComplete },
                set: { if !$0 { viewModel.reset() } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your video has been uploaded successfully!")
            }
            .alert("Upload Error", isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil }}
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage ?? "Unknown error")
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
    
    var body: some View {
        TextField("Add a caption...", text: $caption)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .padding(.horizontal)
    }
}

struct UploadProgressSection: View {
    let isUploading: Bool
    let progress: Double
    
    var body: some View {
        if isUploading {
            ProgressView(value: progress) {
                Text("Uploading... \(Int(progress * 100))%")
            }
            .padding()
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