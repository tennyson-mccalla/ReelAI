import SwiftUI
import PhotosUI

struct VideoUploadView: View {
    @StateObject private var viewModel = VideoUploadViewModel()
    @State private var showingPhotoPicker = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if let thumbnail = viewModel.thumbnailImage {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 200)
                        .cornerRadius(12)
                } else {
                    VideoPlaceholderView()
                        .onTapGesture {
                            showingPhotoPicker = true
                        }
                }
                
                TextField("Add a caption...", text: $viewModel.caption)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                
                if viewModel.isUploading {
                    ProgressView(value: viewModel.uploadProgress) {
                        Text("Uploading... \(Int(viewModel.uploadProgress * 100))%")
                    }
                    .padding()
                }
                
                Button(action: viewModel.uploadVideo) {
                    Text("Upload Video")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .disabled(viewModel.isUploading || viewModel.selectedVideoURL == nil)
                .padding(.horizontal)
                
                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .padding()
                }
                
                Spacer()
            }
            .navigationTitle("Upload Video")
            .sheet(isPresented: $showingPhotoPicker) {
                VideoPicker(videoURL: $viewModel.selectedVideoURL) {
                    viewModel.generateThumbnail()
                }
            }
        }
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