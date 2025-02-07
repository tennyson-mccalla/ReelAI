import Foundation
import AVFoundation
import UIKit
import os

actor VideoCacheManager {
    static let shared = VideoCacheManager()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReelAI", category: "VideoCacheManager")
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let thumbnailCacheDirectory: URL
    private let maxCacheSize: UInt64 = 500 * 1024 * 1024  // 500MB default
    private let maxThumbnailCacheSize: UInt64 = 50 * 1024 * 1024  // 50MB default

    private init() {
        // Use the app support directory for persistent cache
        let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        cacheDirectory = appSupportDir.appendingPathComponent("VideoCache", isDirectory: true)
        thumbnailCacheDirectory = appSupportDir.appendingPathComponent("ThumbnailCache", isDirectory: true)

        do {
            // Create cache directories if they don't exist
            try fileManager.createDirectory(at: cacheDirectory,
                                         withIntermediateDirectories: true,
                                         attributes: nil)
            try fileManager.createDirectory(at: thumbnailCacheDirectory,
                                         withIntermediateDirectories: true,
                                         attributes: nil)
            
            // Add a .nomedia file to prevent thumbnails from showing in photo galleries
            let nomediaPath = thumbnailCacheDirectory.appendingPathComponent(".nomedia")
            if !fileManager.fileExists(atPath: nomediaPath.path) {
                try Data().write(to: nomediaPath)
            }
            
            // Log cache status on initialization
            logger.info("📂 Cache initialized at:")
            logger.info("   Video cache: \(self.cacheDirectory.path)")
            logger.info("   Thumbnail cache: \(self.thumbnailCacheDirectory.path)")
            
            Task {
                let videoSize = await calculateCacheSize()
                let thumbnailSize = await calculateThumbnailCacheSize()
                logger.info("💾 Initial cache sizes:")
                logger.info("   Video: \(videoSize/1024/1024)MB")
                logger.info("   Thumbnail: \(thumbnailSize/1024/1024)MB")
                
                // Log cached thumbnails
                let thumbnails = try? fileManager.contentsOfDirectory(at: thumbnailCacheDirectory, includingPropertiesForKeys: nil)
                logger.info("🖼️ Found \(thumbnails?.count ?? 0) cached thumbnails")
            }
        } catch {
            logger.error("❌ Failed to initialize cache directories: \(error.localizedDescription)")
        }
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
            logger.debug("📸 Thumbnail already cached for id: \(id)")
            return cachedFileURL
        }
        
        logger.debug("💾 Caching new thumbnail for id: \(id)")
        
        // Convert image to data and cache
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            logger.error("Failed to convert image to data for id: \(id)")
            throw NSError(domain: "VideoCacheManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to data"])
        }
        
        do {
            try imageData.write(to: cachedFileURL)
            logger.debug("✅ Successfully cached thumbnail for id: \(id)")
        } catch {
            logger.error("Failed to write thumbnail to cache for id: \(id): \(error.localizedDescription)")
            throw error
        }
        
        // Cleanup if needed
        await performThumbnailCacheCleanupIfNeeded()
        
        return cachedFileURL
    }
    
    func getCachedThumbnail(withIdentifier id: String) async -> UIImage? {
        let cachedFileURL = thumbnailCacheDirectory.appendingPathComponent("\(id).jpg")
        
        if fileManager.fileExists(atPath: cachedFileURL.path) {
            do {
                let imageData = try Data(contentsOf: cachedFileURL)
                if let image = UIImage(data: imageData) {
                    logger.debug("✅ Loaded cached thumbnail: \(id)")
                    return image
                }
                logger.error("⚠️ Failed to create UIImage from cached data: \(id)")
            } catch {
                logger.error("⚠️ Failed to read cached thumbnail: \(id)")
            }
        } else {
            logger.debug("❌ No cached thumbnail found: \(id)")
        }
        return nil
    }
    
    private func performThumbnailCacheCleanupIfNeeded() async {
        let currentSize = await calculateThumbnailCacheSize()
        logger.debug("Current thumbnail cache size: \(currentSize/1024/1024)MB")
        
        if currentSize > maxThumbnailCacheSize {
            logger.info("Cleaning up thumbnail cache (current size: \(currentSize/1024/1024)MB)")
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
                do {
                    try fileManager.removeItem(at: fileURL)
                    currentSize -= UInt64(size)
                    logger.debug("Removed cached thumbnail: \(fileURL.lastPathComponent)")
                } catch {
                    logger.error("Failed to remove cached thumbnail: \(error.localizedDescription)")
                }
            }
        }
        
        logger.info("Finished cleanup. New cache size: \(currentSize/1024/1024)MB")
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
            logger.info("Thumbnail cache cleared successfully")
        } catch {
            logger.error("Error clearing thumbnail cache: \(error.localizedDescription)")
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
