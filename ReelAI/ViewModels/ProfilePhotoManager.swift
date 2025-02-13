import Foundation
import SwiftUI
import PhotosUI
import UIKit
import os
import FirebaseAuth

/// @deprecated Use `ProfileActorViewModel` instead. This class will be removed in a future update.
@MainActor
@available(*, deprecated, message: "Use ProfileActorViewModel instead")
final class ProfilePhotoManager: ObservableObject {
    // MARK: - Published Properties
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    @Published private(set) var isInitialized = false
    @Published var photoSelection: PhotosPickerItem? {
        didSet {
            if let selection = photoSelection {
                Task {
                    await processPhotoSelection(selection)
                }
            }
        }
    }

    // MARK: - Dependencies
    private let storage: StorageManager
    private var database: ReelDB.Manager?
    private let userId: String
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReelAI", category: "ProfilePhotoManager")

    // MARK: - Configuration
    private let maxPhotoSize: Int = 5 * 1024 * 1024  // 5MB
    private let targetDimension: CGFloat = 1024
    private let compressionQuality: CGFloat = 0.8

    // MARK: - Initialization
    init(storage: StorageManager, database: ReelDB.Manager?, userId: String) {
        self.storage = storage
        self.database = database
        self.userId = userId
    }

    func initialize(database: ReelDB.Manager) async {
        self.database = database
        self.isInitialized = true
    }

    // MARK: - Error Handling
    func clearError() {
        error = nil
    }

    // MARK: - Photo Processing
    private func loadAndProcessImage(from item: PhotosPickerItem) async throws -> UIImage {
        guard let data = try await item.loadTransferable(type: Data.self) else {
            throw ProfilePhotoError.invalidImageData
        }

        guard data.count <= maxPhotoSize else {
            throw ProfilePhotoError.imageTooLarge
        }

        guard let image = UIImage(data: data) else {
            throw ProfilePhotoError.invalidImageFormat
        }

        return processImage(image)
    }

    private func processImage(_ image: UIImage) -> UIImage {
        let size = image.size

        guard size.width > targetDimension || size.height > targetDimension else {
            return image
        }

        let ratio = size.width / size.height
        let newSize: CGSize

        if size.width > size.height {
            newSize = CGSize(width: targetDimension, height: targetDimension / ratio)
        } else {
            newSize = CGSize(width: targetDimension * ratio, height: targetDimension)
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)

        return renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private func uploadAndUpdateProfile(with image: UIImage) async throws -> URL {
        guard let database = database else {
            throw ProfilePhotoError.notInitialized
        }

        guard let data = image.jpegData(compressionQuality: compressionQuality) else {
            throw ProfilePhotoError.compressionFailed
        }

        // Upload photo and get URL
        let photoURL = try await storage.uploadProfilePhoto(data, userId: userId)

        // Update database with the URL
        try await database.updateProfilePhoto(userId: userId, photoURL: photoURL)

        return photoURL
    }

    private func processPhotoSelection(_ selection: PhotosPickerItem) async {
        do {
            guard !isLoading else { return }
            guard isInitialized else {
                throw ProfilePhotoError.notInitialized
            }

            await MainActor.run {
                isLoading = true
                error = nil
            }

            let image = try await loadAndProcessImage(from: selection)
            let photoURL = try await uploadAndUpdateProfile(with: image)

            await MainActor.run {
                isLoading = false
                photoSelection = nil
                // Notify UI to refresh with the actual URL
                NotificationCenter.default.post(
                    name: Notification.Name("ProfilePhotoUpdated"),
                    object: photoURL
                )
                logger.debug("✅ Profile photo updated successfully with URL: \(photoURL)")
            }
        } catch {
            await MainActor.run {
                self.error = error
                self.isLoading = false
                self.photoSelection = nil
                logger.error("❌ Failed to process photo: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Error Types
enum ProfilePhotoError: LocalizedError {
    case invalidImageData
    case imageTooLarge
    case invalidImageFormat
    case compressionFailed
    case uploadFailed
    case notInitialized

    var errorDescription: String? {
        switch self {
        case .invalidImageData:
            return "Unable to process the selected photo"
        case .imageTooLarge:
            return "Photo size exceeds 5MB limit"
        case .invalidImageFormat:
            return "Invalid photo format"
        case .compressionFailed:
            return "Failed to process photo"
        case .uploadFailed:
            return "Failed to upload photo"
        case .notInitialized:
            return "Photo manager not properly initialized"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .invalidImageData:
            return "Please try selecting a different photo"
        case .imageTooLarge:
            return "Please choose a smaller photo or use the built-in photo editor to reduce its size"
        case .invalidImageFormat:
            return "Please select a photo in JPEG or PNG format"
        case .compressionFailed:
            return "Please try selecting a different photo"
        case .uploadFailed:
            return "Please check your internet connection and try again"
        case .notInitialized:
            return "Please try again in a moment"
        }
    }
}
