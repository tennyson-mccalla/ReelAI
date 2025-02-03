import Foundation
import FirebaseStorage
import AVFoundation
import UIKit
import FirebaseFirestore
import FirebaseAuth

class VideoUploadViewModel: ObservableObject {
    @Published var uploadProgress: Double = 0
    @Published var isUploading = false
    @Published var errorMessage: String?
    @Published var selectedVideoURL: URL?
    @Published var thumbnailImage: UIImage?
    @Published var caption: String = ""
    
    private let storage = Storage.storage().reference()
    private let db = Firestore.firestore()
    private var thumbnailURL: String?
    
    func uploadVideo() {
        guard let videoURL = selectedVideoURL else {
            errorMessage = "No video selected"
            return
        }
        
        isUploading = true
        let videoName = UUID().uuidString + ".mp4"
        let videoRef = storage.child("videos/\(videoName)")
        
        let metadata = StorageMetadata()
        metadata.contentType = "video/mp4"
        
        let uploadTask = videoRef.putFile(from: videoURL, metadata: metadata) { metadata, error in
            DispatchQueue.main.async {
                self.isUploading = false
                
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                
                self.saveVideoMetadata(videoName: videoName)
            }
        }
        
        uploadTask.observe(.progress) { snapshot in
            DispatchQueue.main.async {
                self.uploadProgress = Double(snapshot.progress?.completedUnitCount ?? 0) / Double(snapshot.progress?.totalUnitCount ?? 1)
            }
        }
    }
    
    private func saveVideoMetadata(videoName: String) {
        guard let user = Auth.auth().currentUser else {
            errorMessage = "User not authenticated"
            return
        }
        
        if let thumbnail = thumbnailImage,
           let thumbnailData = thumbnail.jpegData(compressionQuality: 0.7) {
            let thumbnailName = UUID().uuidString + ".jpg"
            let thumbnailRef = storage.child("thumbnails/\(thumbnailName)")
            
            thumbnailRef.putData(thumbnailData, metadata: nil) { metadata, error in
                if let error = error {
                    print("Error uploading thumbnail: \(error.localizedDescription)")
                    return
                }
                
                thumbnailRef.downloadURL { url, error in
                    if let thumbnailURL = url?.absoluteString {
                        self.thumbnailURL = thumbnailURL
                        self.saveToFirestore(videoName: videoName, thumbnailName: thumbnailName)
                    }
                }
            }
        } else {
            saveToFirestore(videoName: videoName, thumbnailName: nil)
        }
    }
    
    private func saveToFirestore(videoName: String, thumbnailName: String?) {
        guard let user = Auth.auth().currentUser else { return }
        
        let videoData: [String: Any] = [
            "userId": user.uid,
            "videoName": videoName,
            "caption": caption,
            "thumbnailURL": thumbnailURL ?? "",
            "timestamp": FieldValue.serverTimestamp(),
            "likes": 0,
            "comments": 0
        ]
        
        db.collection("videos").addDocument(data: videoData) { error in
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = "Error saving metadata: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func generateThumbnail() {
        guard let url = selectedVideoURL else { return }
        
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        do {
            let cgImage = try imageGenerator.copyCGImage(at: .zero, actualTime: nil)
            thumbnailImage = UIImage(cgImage: cgImage)
        } catch {
            errorMessage = "Could not generate thumbnail"
        }
    }
} 