import Foundation
import AVFoundation
import UIKit

actor VideoCacheManager {
    static let shared = VideoCacheManager()

    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let thumbnailCacheDirectory: URL
    private let maxCacheSize: UInt64 = 500 * 1024 * 1024  // 500MB default
    private let maxThumbnailCacheSize: UInt64 = 50 * 1024 * 1024  // 50MB default

    private init() {
        let cachePath = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)[0]
        cacheDirectory = URL(fileURLWithPath: cachePath).appendingPathComponent("VideoCache")
        thumbnailCacheDirectory = URL(fileURLWithPath: cachePath).appendingPathComponent("ThumbnailCache")

        try? fileManager.createDirectory(at: cacheDirectory,
                                       withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: thumbnailCacheDirectory,
                                       withIntermediateDirectories: true)
    }

    func cacheVideo(from url: URL, withIdentifier id: String) async throws -> URL {
        let cachedFileURL = cacheDirectory.appendingPathComponent(id)

        // Return cached version if exists
        if fileManager.fileExists(atPath: cachedFileURL.path) {
            return cachedFileURL
        }

        // Download and cache
        let (downloadURL, _) = try await URLSession.shared.download(from: url)
        // Add error handling for existing file
        if fileManager.fileExists(atPath: cachedFileURL.path) {
            try fileManager.removeItem(at: cachedFileURL)
        }
        try fileManager.moveItem(at: downloadURL, to: cachedFileURL)

        // Cleanup if needed
        await performCacheCleanupIfNeeded()

        return cachedFileURL
    }

    private func performCacheCleanupIfNeeded() async {
        let currentSize = await calculateCacheSize()

        if currentSize > maxCacheSize {
            await cleanupOldestFiles(targetSize: maxCacheSize * 3 / 4)
        }
    }

    private func calculateCacheSize() async -> UInt64 {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey]
        ) else { return 0 }

        return contents.reduce(0) { sum, url in
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            else { return sum }
            return sum + UInt64(size)
        }
    }

    private func cleanupOldestFiles(targetSize: UInt64) async {
        // Get all cached files with their creation dates
        guard let contents = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey]
        ) else { return }

        // Sort by creation date (oldest first)
        let sortedFiles = contents.compactMap { url -> (URL, Date)? in
            guard let date = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate
            else { return nil }
            return (url, date)
        }.sorted { $0.1 < $1.1 }

        // Remove oldest files until we're under target size
        var currentSize = await calculateCacheSize()
        for (fileURL, _) in sortedFiles {
            if currentSize <= targetSize { break }
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                try? fileManager.removeItem(at: fileURL)
                currentSize -= UInt64(size)
            }
        }
    }

    func debugPrintCache() async {
        let contents = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey]
        )
        print("Cache directory: \(cacheDirectory)")
        print("Cached files: \(contents?.count ?? 0)")
        print("Total size: \(await calculateCacheSize() / 1024 / 1024)MB")
    }

    func clearCache() async {
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: nil
            )

            for file in contents {
                try fileManager.removeItem(at: file)
            }
            print("Cache cleared successfully")
        } catch {
            print("Error clearing cache: \(error)")
        }
    }

    // MARK: - Thumbnail Caching

    func cacheThumbnail(_ image: UIImage, withIdentifier id: String) async throws -> URL {
        let cachedFileURL = thumbnailCacheDirectory.appendingPathComponent("\(id).jpg")
        
        // Return cached version if exists
        if fileManager.fileExists(atPath: cachedFileURL.path) {
            return cachedFileURL
        }
        
        // Convert image to data and cache
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw NSError(domain: "VideoCacheManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to data"])
        }
        
        try imageData.write(to: cachedFileURL)
        
        // Cleanup if needed
        await performThumbnailCacheCleanupIfNeeded()
        
        return cachedFileURL
    }
    
    func getCachedThumbnail(withIdentifier id: String) -> UIImage? {
        let cachedFileURL = thumbnailCacheDirectory.appendingPathComponent("\(id).jpg")
        guard fileManager.fileExists(atPath: cachedFileURL.path),
              let imageData = try? Data(contentsOf: cachedFileURL) else {
            return nil
        }
        return UIImage(data: imageData)
    }
    
    private func performThumbnailCacheCleanupIfNeeded() async {
        let currentSize = await calculateThumbnailCacheSize()
        
        if currentSize > maxThumbnailCacheSize {
            await cleanupOldestThumbnails(targetSize: maxThumbnailCacheSize * 3 / 4)
        }
    }
    
    private func calculateThumbnailCacheSize() async -> UInt64 {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: thumbnailCacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        
        return contents.reduce(0) { sum, url in
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            else { return sum }
            return sum + UInt64(size)
        }
    }
    
    private func cleanupOldestThumbnails(targetSize: UInt64) async {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: thumbnailCacheDirectory,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey]
        ) else { return }
        
        let sortedFiles = contents.compactMap { url -> (URL, Date)? in
            guard let date = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate
            else { return nil }
            return (url, date)
        }.sorted { $0.1 < $1.1 }
        
        var currentSize = await calculateThumbnailCacheSize()
        for (fileURL, _) in sortedFiles {
            if currentSize <= targetSize { break }
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                try? fileManager.removeItem(at: fileURL)
                currentSize -= UInt64(size)
            }
        }
    }
    
    func clearThumbnailCache() async {
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: thumbnailCacheDirectory,
                includingPropertiesForKeys: nil
            )
            
            for file in contents {
                try fileManager.removeItem(at: file)
            }
            print("Thumbnail cache cleared successfully")
        } catch {
            print("Error clearing thumbnail cache: \(error)")
        }
    }
    
    func debugPrintCaches() async {
        print("Video Cache:")
        await debugPrintCache()
        
        print("\nThumbnail Cache:")
        let contents = try? fileManager.contentsOfDirectory(
            at: thumbnailCacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey]
        )
        print("Cache directory: \(thumbnailCacheDirectory)")
        print("Cached thumbnails: \(contents?.count ?? 0)")
        print("Total size: \(await calculateThumbnailCacheSize() / 1024 / 1024)MB")
    }
}
