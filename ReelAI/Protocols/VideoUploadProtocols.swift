import Foundation
import UIKit
import AVFoundation

/// Represents errors that can occur during the video upload process
public enum PublicUploadError: Error {
    /// Video processing failed with a specific reason
    case videoProcessingFailed(reason: String)
    /// Network is not available for upload
    case networkUnavailable
    /// Error occurred while accessing storage
    case storageError
    /// General network error occurred
    case networkError
    /// Unknown error occurred
    case unknownError

    public var localizedDescription: String {
        switch self {
        case .videoProcessingFailed(let reason):
            return "Video processing failed: \(reason)"
        case .networkUnavailable:
            return "Network is unavailable"
        case .storageError:
            return "Storage error occurred"
        case .networkError:
            return "Network error occurred"
        case .unknownError:
            return "An unknown error occurred"
        }
    }
}

/// Represents errors that can occur during video selection and processing
public enum VideoPickerError: Error {
    /// No videos were selected by the user
    case noVideosSelected
    /// The selected video format is not supported
    case invalidVideoFormat
    /// Video processing failed with a specific reason
    case processingFailed(reason: String)

    public var localizedDescription: String {
        switch self {
        case .noVideosSelected:
            return "No videos were selected"
        case .invalidVideoFormat:
            return "The selected video format is not supported"
        case .processingFailed(let reason):
            return "Video processing failed: \(reason)"
        }
    }
}

/// Protocol defining the interface for video upload view models
@MainActor
public protocol VideoUploadViewModelProtocol: AnyObject {
    /// Sets the selected video URLs for upload
    /// - Parameter urls: Array of URLs representing selected videos
    func setSelectedVideos(urls: [URL])

    /// Sets an error state in the view model
    /// - Parameter error: The upload error that occurred
    func setError(_ error: PublicUploadError)

    /// Initiates the upload process for selected videos
    func uploadVideos()
}

/// Default implementation of VideoUploadViewModelProtocol
@MainActor
public class DefaultVideoUploadViewModel: VideoUploadViewModelProtocol {
    /// Initializes a new default video upload view model
    public init() {}

    public func setSelectedVideos(urls: [URL]) {}
    public func setError(_ error: PublicUploadError) {}
    public func uploadVideos() {}
}

/// Represents the quality level for video processing
public enum VideoQuality {
    /// Low quality, smaller file size
    case low
    /// Medium quality, balanced file size
    case medium
    /// High quality, larger file size
    case high
}

/// Represents the current status of a video upload
public enum UploadStatus {
    /// Upload is waiting to begin
    case pending
    /// Upload is in progress with a progress value
    case uploading(progress: Double)
    /// Upload completed successfully with a URL
    case completed(URL)
    /// Upload failed with an error
    case failed(Error)
    /// Upload was cancelled by the user
    case cancelled
}

/// Generates a thumbnail image from a video URL
/// - Parameter videoURL: The URL of the video
/// - Returns: An optional UIImage representing the thumbnail, or nil if generation fails
public func generateThumbnail(for videoURL: URL) async -> UIImage? {
    let asset = AVURLAsset(url: videoURL)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true

    return await withCheckedContinuation { continuation in
        generator.generateCGImageAsynchronously(
            for: CMTime(seconds: 1, preferredTimescale: 60)
        ) { cgImage, time, error in
            if let error = error {
                print("❌ Could not generate thumbnail for video: \(error.localizedDescription)")
                continuation.resume(returning: nil)
                return
            }

            if let cgImage = cgImage {
                continuation.resume(returning: UIImage(cgImage: cgImage))
            } else {
                continuation.resume(returning: nil)
            }
        }
    }
}
