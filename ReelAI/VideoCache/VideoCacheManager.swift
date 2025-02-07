import Foundation
import AVFoundation
import UIKit
import os

actor VideoCacheManager {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReelAI", category: "VideoCacheManager")
    private let fileManager: FileManager
    private let cacheDirectory: URL
    private let thumbnailCacheDirectory: URL
    private let maxCacheSize: UInt64 = 500 * 1024 * 1024  // 500MB default
    private let maxThumbnailCacheSize: UInt64 = 50 * 1024 * 1024  // 50MB default
    
    static let shared: VideoCacheManager = {
        do {
            return try VideoCacheManager()
        } catch {
            fatalError("Failed to initialize VideoCacheManager: \(error)")
        }
    }()
    
    private init() throws {
        self.fileManager = FileManager.default
        
        // Use the app support directory for persistent cache
        guard let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw VideoCacheError.failedToGetSupportDirectory
        }
        
        self.cacheDirectory = appSupportDir.appendingPathComponent("VideoCache", isDirectory: true)
        self.thumbnailCacheDirectory = appSupportDir.appendingPathComponent("ThumbnailCache", isDirectory: true)
        
        // Create cache directories if they don't exist
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
        
        if !fileManager.fileExists(atPath: thumbnailCacheDirectory.path) {
            try fileManager.createDirectory(at: thumbnailCacheDirectory, withIntermediateDirectories: true)
        }
        
        // Add a .nomedia file to prevent thumbnails from showing in photo galleries
        let nomediaPath = thumbnailCacheDirectory.appendingPathComponent(".nomedia")
        if !fileManager.fileExists(atPath: nomediaPath.path) {
            try Data().write(to: nomediaPath)
        }
        
        // Log cache status on initialization
        logger.info("📂 Cache initialized at:")
        logger.info("   Video cache: \(self.cacheDirectory.path)")
        logger.info("   Thumbnail cache: \(self.thumbnailCacheDirectory.path)")
    }
    
    enum VideoCacheError: Error {
        case failedToGetSupportDirectory
        case failedToCreateDirectory
        case failedToSaveFile
        case failedToLoadFile
        case fileNotFound
        case invalidData
    }
    
    private func getCacheURL(forIdentifier identifier: String, fileExtension: String) -> URL {
        return cacheDirectory.appendingPathComponent("\(identifier).\(fileExtension)")
    }
    
    private func getThumbnailCacheURL(forIdentifier identifier: String, fileExtension: String) -> URL {
        return thumbnailCacheDirectory.appendingPathComponent("\(identifier).\(fileExtension)")
    }
    
    private func fileExists(at url: URL) -> Bool {
        return fileManager.fileExists(atPath: url.path)
    }
    
    private func createDirectory(at url: URL) throws {
        if !fileExists(at: url) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
    
    private func saveData(_ data: Data, to url: URL) throws {
        try data.write(to: url)
    }
    
    private func loadData(from url: URL) throws -> Data {
        return try Data(contentsOf: url)
    }
    
    func getCachedThumbnail(withIdentifier id: String) async -> UIImage? {
        let cachedFileURL = getThumbnailCacheURL(forIdentifier: id, fileExtension: "jpg")
        
        guard fileExists(at: cachedFileURL) else {
            logger.debug("No cached thumbnail found for id: \(id)")
            return nil
        }
        
        do {
            let imageData = try loadData(from: cachedFileURL)
            if let image = UIImage(data: imageData) {
                logger.debug("Loaded cached thumbnail for id: \(id)")
                return image
            }
        } catch {
            logger.error("Failed to load cached thumbnail: \(error.localizedDescription)")
        }
        
        return nil
    }
    
    func cacheThumbnail(_ image: UIImage, withIdentifier id: String) async throws -> URL {
        let cachedFileURL = getThumbnailCacheURL(forIdentifier: id, fileExtension: "jpg")
        
        // Check if already cached
        if fileExists(at: cachedFileURL) {
            logger.debug("Thumbnail already cached for id: \(id)")
            return cachedFileURL
        }
        
        // Convert to JPEG data
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw VideoCacheError.invalidData
        }
        
        // Write to cache
        try saveData(imageData, to: cachedFileURL)
        logger.debug("Cached new thumbnail for id: \(id)")
        
        return cachedFileURL
    }
    
    func calculateCacheSize() async -> UInt64 {
        do {
            let contents = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey])
            var totalSize: UInt64 = 0
            for url in contents {
                let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
                totalSize += UInt64(resourceValues.fileSize ?? 0)
            }
            return totalSize
        } catch {
            logger.error("Failed to calculate cache size: \(error.localizedDescription)")
            return 0
        }
    }
    
    func calculateThumbnailCacheSize() async -> UInt64 {
        do {
            let contents = try fileManager.contentsOfDirectory(at: thumbnailCacheDirectory, includingPropertiesForKeys: [.fileSizeKey])
            var totalSize: UInt64 = 0
            for url in contents {
                let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
                totalSize += UInt64(resourceValues.fileSize ?? 0)
            }
            return totalSize
        } catch {
            logger.error("Failed to calculate thumbnail cache size: \(error.localizedDescription)")
            return 0
        }
    }
    
    func cacheVideo(from url: URL, withIdentifier id: String) async throws -> URL {
        let cachedFileURL = getCacheURL(forIdentifier: id, fileExtension: "mp4")

        // Return cached version if exists
        if await Task.detached {
            self.fileExists(at: cachedFileURL)
        }.value {
            return cachedFileURL
        }

        // Download and cache
        let (downloadURL, _) = try await URLSession.shared.download(from: url)
        // Add error handling for existing file
        if await Task.detached {
            self.fileExists(at: cachedFileURL)
        }.value {
            try await Task.detached {
                try self.fileManager.removeItem(at: cachedFileURL)
            }.value
        }
        try await Task.detached {
            try self.fileManager.moveItem(at: downloadURL, to: cachedFileURL)
        }.value

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

    private func cleanupOldestFiles(targetSize: UInt64) async {
        // Get all cached files with their creation dates
        let contents = try? await listCachedFiles()
        
        // Sort by creation date (oldest first)
        let sortedFiles = contents?.compactMap { url -> (URL, Date)? in
            guard let date = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate
            else { return nil }
            return (url, date)
        }.sorted { $0.1 < $1.1 }

        // Remove oldest files until we're under target size
        var currentSize = await calculateCacheSize()
        for (fileURL, _) in sortedFiles ?? [] {
            if currentSize <= targetSize { break }
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                try? await Task.detached {
                    try self.fileManager.removeItem(at: fileURL)
                }.value
                currentSize -= UInt64(size)
            }
        }
    }

    private func listCachedFiles() async throws -> [URL] {
        try await Task.detached {
            try self.fileManager.contentsOfDirectory(at: self.cacheDirectory, includingPropertiesForKeys: nil)
        }.value
    }

    func debugPrintCache() async {
        let contents = try? await listCachedFiles()
        print("Cache directory: \(cacheDirectory)")
        print("Cached files: \(contents?.count ?? 0)")
        print("Total size: \(await calculateCacheSize() / 1024 / 1024)MB")
    }

    func clearCache() async throws {
        do {
            let contents = try await listCachedFiles()
            for file in contents ?? [] {
                try await Task.detached {
                    try self.fileManager.removeItem(at: file)
                }.value
            }
            print("Cache cleared successfully")
        } catch {
            print("Error clearing cache: \(error)")
        }
    }

    func clearThumbnailCache() async throws {
        do {
            let contents = try await listCachedThumbnails()
            for file in contents ?? [] {
                try await Task.detached {
                    try self.fileManager.removeItem(at: file)
                }.value
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
        let contents = try? await listCachedThumbnails()
        print("Cache directory: \(thumbnailCacheDirectory)")
        print("Cached thumbnails: \(contents?.count ?? 0)")
        print("Total size: \(await calculateThumbnailCacheSize() / 1024 / 1024)MB")
    }

    private func performThumbnailCacheCleanupIfNeeded() async {
        let currentSize = await calculateThumbnailCacheSize()
        logger.debug("Current thumbnail cache size: \(currentSize/1024/1024)MB")
        
        if currentSize > maxThumbnailCacheSize {
            logger.info("Cleaning up thumbnail cache (current size: \(currentSize/1024/1024)MB)")
            await cleanupOldestThumbnails(targetSize: maxThumbnailCacheSize * 3 / 4)
        }
    }

    private func cleanupOldestThumbnails(targetSize: UInt64) async {
        let contents = try? await listCachedThumbnails()
        
        let sortedFiles = contents?.compactMap { url -> (URL, Date)? in
            guard let date = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate
            else { return nil }
            return (url, date)
        }.sorted { $0.1 < $1.1 }

        var currentSize = await calculateThumbnailCacheSize()
        for (fileURL, _) in sortedFiles ?? [] {
            if currentSize <= targetSize { break }
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                try? await Task.detached {
                    try self.fileManager.removeItem(at: fileURL)
                }.value
                currentSize -= UInt64(size)
                logger.debug("Removed cached thumbnail: \(fileURL.lastPathComponent)")
            }
        }
        
        logger.info("Finished cleanup. New cache size: \(currentSize/1024/1024)MB")
    }

    private func listCachedThumbnails() async throws -> [URL] {
        try await Task.detached {
            try self.fileManager.contentsOfDirectory(at: self.thumbnailCacheDirectory, includingPropertiesForKeys: nil)
        }.value
    }

    func logCacheStatus() async {
        let videoSize = await calculateCacheSize()
        let thumbnailSize = await calculateThumbnailCacheSize()
        logger.info("💾 Cache sizes:")
        logger.info("   Video: \(videoSize/1024/1024)MB")
        logger.info("   Thumbnail: \(thumbnailSize/1024/1024)MB")
        
        if let thumbnails = try? await listCachedThumbnails() {
            logger.info("🖼️ Found \(thumbnails.count) cached thumbnails")
        }
    }
}
