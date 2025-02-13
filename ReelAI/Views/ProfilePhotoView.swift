import SwiftUI
import PhotosUI

struct ProfilePhotoView: View {
    @StateObject private var photoManager: ProfilePhotoManager
    let photoURL: URL?
    let size: CGFloat

    init(photoManager: ProfilePhotoManager? = nil, photoURL: URL?, size: CGFloat) {
        // Create a temporary manager that will be initialized in task
        let tempManager = ProfilePhotoManager(
            storage: FirebaseStorageManager(),
            database: nil,  // Will be set during initialization
            userId: Auth.auth().currentUser?.uid ?? ""
        )
        _photoManager = StateObject(wrappedValue: tempManager)
        self.photoURL = photoURL
        self.size = size
    }

    var body: some View {
        ZStack {
            if !photoManager.isInitialized {
                ProgressView()
                    .task {
                        // Initialize the manager
                        let database = await FirebaseDatabaseManager.shared
                        await photoManager.initialize(database: database)
                    }
            } else {
                PhotosPicker(
                    selection: $photoManager.photoSelection,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    photoContent
                }
                .disabled(photoManager.isLoading)

                if photoManager.isLoading {
                    Color.black.opacity(0.4)
                        .frame(width: size, height: size)
                        .clipShape(Circle())

                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                }
            }
        }
        .alert(
            "Photo Error",
            isPresented: Binding(
                get: { photoManager.error != nil },
                set: { if !$0 { photoManager.clearError() } }
            ),
            actions: {
                Button("OK", role: .cancel) {}
            },
            message: {
                if let error = photoManager.error {
                    Text(error.localizedDescription)
                    if let localizedError = error as? LocalizedError,
                       let recovery = localizedError.recoverySuggestion {
                        Text(recovery)
                    }
                }
            }
        )
    }

    private var photoContent: some View {
        ZStack(alignment: .bottomTrailing) {
            AsyncImage(
                url: photoURL,
                transaction: Transaction(animation: .easeInOut)
            ) { phase in
                switch phase {
                case .empty:
                    placeholderImage
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    placeholderImage
                @unknown default:
                    placeholderImage
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white, lineWidth: 4))
            .shadow(radius: 7)

            Image(systemName: "pencil.circle.fill")
                .resizable()
                .frame(width: 30, height: 30)
                .background(Color.white)
                .clipShape(Circle())
                .offset(x: -10, y: -10)
                .opacity(photoManager.isLoading ? 0 : 1)
        }
    }

    private var placeholderImage: some View {
        Image(systemName: "person.circle.fill")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .foregroundColor(.gray)
            .opacity(0.8)
    }
}

#Preview {
    ProfilePhotoView(
        photoManager: ProfilePhotoManager(
            storage: FirebaseStorageManager(),
            database: nil,
            userId: "preview-user"
        ),
        photoURL: nil,
        size: 120
    )
}
