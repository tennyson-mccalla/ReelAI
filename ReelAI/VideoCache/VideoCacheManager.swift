import Foundation
import os
import UIKit

extension Notification.Name {
    static let videoCacheCleared = Notification.Name("videoCacheCleared")
    static let videoCacheSizeChanged = Notification.Name("videoCacheSizeChanged")
}

actor VideoCacheManager {
    private let fileManager: FileManager
    private let videoCacheDirectory: URL
    private let thumbnailCacheDirectory: URL
    private var cacheMetadata: [String: CacheEntry] = [:]
    private let logger = Logger(subsystem: "com.reelai.videocache", category: "VideoCacheManager")
    
    // Configurable cache limits
    private let maxCacheSize: UInt64 = 1 * 1024 * 1024 * 1024  // 1GB for videos
    private let maxThumbnailCacheSize: UInt64 = 100 * 1024 * 1024  // 100MB for thumbnails
    private let maxCacheAge: TimeInterval = 7 * 24 * 60 * 60  // 1 week
    
    // Tracking cache metadata
    private var hasLoggedInitialStatus = false

    // Cache entry to track metadata
    private struct CacheEntry: Codable {
        let id: String
        let cachedAt: Date
        let fileSize: Int64
        var lastAccessedAt: Date
    }

    // Static shared instance with lazy initialization
    static let shared: VideoCacheManager = {
        do {
            return try VideoCacheManager()
        } catch {
            // Log the error and provide a fallback
            print("❌ Failed to initialize VideoCacheManager: \(error)")
            fatalError("Could not initialize VideoCacheManager")
        }
    }()

    // Designated initializer
    private init() throws {
        self.fileManager = .default
        
        // Use the app support directory for persistent cache
        guard let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw VideoCacheError.failedToGetSupportDirectory
        }

        self.videoCacheDirectory = appSupportDir.appendingPathComponent("VideoCache", isDirectory: true)
        self.thumbnailCacheDirectory = appSupportDir.appendingPathComponent("ThumbnailCache", isDirectory: true)

        // Create cache directories
        try Self.createDirectoriesNonIsolated(
            directories: [videoCacheDirectory, thumbnailCacheDirectory], 
            fileManager: fileManager
        )

        // Load cache metadata
        self.cacheMetadata = try Self.loadCacheMetadataNonIsolated(
            metadataURL: videoCacheDirectory.appendingPathComponent("cache_metadata.json"), 
            fileManager: fileManager
        )

        // Start periodic maintenance
        Task { [weak self] in
            try? await self?.performCacheMaintenance()
        }
    }

    // Static method for non-isolated directory creation
    private static func createDirectoriesNonIsolated(
        directories: [URL], 
        fileManager: FileManager
    ) throws {
        for directory in directories {
            if !fileManager.fileExists(atPath: directory.path) {
                try fileManager.createDirectory(
                    at: directory, 
                    withIntermediateDirectories: true, 
                    attributes: nil
                )
            }
        }
    }

    // Static method for non-isolated metadata loading
    private static func loadCacheMetadataNonIsolated(
        metadataURL: URL, 
        fileManager: FileManager
    ) throws -> [String: CacheEntry] {
        guard fileManager.fileExists(atPath: metadataURL.path) else { 
            // Initialize empty metadata if file doesn't exist
            return [:]
        }
        
        let data = try Data(contentsOf: metadataURL)
        return try JSONDecoder().decode([String: CacheEntry].self, from: data)
    }

    // Public async initialization method
    static func initialize() async throws -> VideoCacheManager {
        return try VideoCacheManager()
    }

    private func performCacheMaintenance() async throws {
        let currentTime = Date()
        
        // Remove expired entries
        var removedEntries = 0
        for (id, entry) in cacheMetadata {
            if currentTime.timeIntervalSince(entry.cachedAt) > maxCacheAge {
                try? removeFile(at: getCacheURL(forIdentifier: id, fileExtension: "mp4"))
                cacheMetadata.removeValue(forKey: id)
                removedEntries += 1
            }
        }

        // Enforce total cache size limit
        try await enforceMaxCacheSize()

        // Save updated metadata
        try saveCacheMetadata()

        logger.info("Cache maintenance: Removed \(removedEntries) expired entries")
    }

    private func enforceMaxCacheSize() async throws {
        // Sort entries by last access time, oldest first
        let sortedEntries = cacheMetadata.values.sorted { $0.lastAccessedAt < $1.lastAccessedAt }
        var currentCacheSize = try await calculateSize(of: videoCacheDirectory)

        for entry in sortedEntries {
            guard currentCacheSize > maxCacheSize else { break }
            
            let fileURL = getCacheURL(forIdentifier: entry.id, fileExtension: "mp4")
            try? removeFile(at: fileURL)
            cacheMetadata.removeValue(forKey: entry.id)
            
            currentCacheSize -= UInt64(entry.fileSize)
        }
    }

    func cacheVideo(from url: URL, withIdentifier id: String) throws -> URL {
        let cachedFileURL = getCacheURL(forIdentifier: id, fileExtension: "mp4")

        // Return cached version if exists and update access time
        if fileExists(at: cachedFileURL) {
            updateCacheEntryAccessTime(for: id)
            return cachedFileURL
        }

        // Perform actual caching (synchronous)
        let videoData = try Data(contentsOf: url)
        try saveData(videoData, to: cachedFileURL)
        
        // Update cache metadata
        let entry = CacheEntry(
            id: id, 
            cachedAt: Date(), 
            fileSize: Int64(videoData.count), 
            lastAccessedAt: Date()
        )
        cacheMetadata[id] = entry
        
        try saveCacheMetadata()
        
        // Notify of cache size change
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .videoCacheSizeChanged, object: nil)
        }

        logger.debug("Cached video for id: \(id)")
        return cachedFileURL
    }

    private func updateCacheEntryAccessTime(for id: String) {
        guard var entry = cacheMetadata[id] else { return }
        entry.lastAccessedAt = Date()
        cacheMetadata[id] = entry
        
        // Periodically save metadata to avoid constant writes
        Task {
            try? saveCacheMetadata()
        }
    }

    private func getCacheURL(forIdentifier identifier: String, fileExtension: String) -> URL {
        return videoCacheDirectory.appendingPathComponent("\(identifier).\(fileExtension)")
    }

    private func getThumbnailCacheURL(forIdentifier identifier: String, fileExtension: String) -> URL {
        return thumbnailCacheDirectory.appendingPathComponent("\(identifier).\(fileExtension)")
    }

    private func fileExists(at url: URL) -> Bool {
        return fileManager.fileExists(atPath: url.path)
    }

    private func saveData(_ data: Data, to url: URL) throws {
        try data.write(to: url)
    }

    private func loadData(from url: URL) throws -> Data {
        return try Data(contentsOf: url)
    }

    private func removeFile(at url: URL) throws {
        if fileExists(at: url) {
            try fileManager.removeItem(at: url)
        }
    }

    private func moveFileToCache(from tempURL: URL, to targetURL: URL) throws {
        do {
            if fileManager.fileExists(atPath: targetURL.path) {
                logger.info("File already exists in cache, removing old version: \(targetURL.lastPathComponent)")
                try fileManager.removeItem(at: targetURL)
            }
            try fileManager.moveItem(at: tempURL, to: targetURL)
            logger.info("Successfully moved file to cache: \(targetURL.lastPathComponent)")
        } catch {
            logger.error("Failed to move file to cache: \(error.localizedDescription)")
            throw error
        }
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
        let thumbnailURL = thumbnailCacheDirectory.appendingPathComponent("\(id).jpg")

        if fileManager.fileExists(atPath: thumbnailURL.path) {
            logger.debug("Found cached thumbnail for id: \(id)")
            return thumbnailURL
        }

        guard let data = image.jpegData(compressionQuality: 0.8) else {
            throw VideoCacheError.thumbnailConversionFailed
        }

        try data.write(to: thumbnailURL)
        logger.info("Cached new thumbnail for id: \(id)")
        return thumbnailURL
    }

    func clearCache() async throws {
        // Clear both caches
        try await clearVideoCache()
        try await clearThumbnailCache()
        
        // Post notification that cache was cleared
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .videoCacheCleared, object: nil)
        }
        
        // Log status after clearing
        let message = "Cache cleared successfully"
        print(message)
        logger.info("\(message)")
        logCacheStatus()
    }

    private func clearVideoCache() async throws {
        let contents = try fileManager.contentsOfDirectory(at: videoCacheDirectory, includingPropertiesForKeys: nil)
        for url in contents {
            try removeFile(at: url)
        }
        let message = "Video cache cleared (\(contents.count) files)"
        print(message)
        logger.info("\(message)")
    }

    func clearThumbnailCache() async throws {
        let contents = try fileManager.contentsOfDirectory(at: thumbnailCacheDirectory, includingPropertiesForKeys: nil)
        var count = 0
        for url in contents where url.lastPathComponent != ".nomedia" {
            try removeFile(at: url)
            count += 1
        }
        let message = "Thumbnail cache cleared (\(count) files)"
        print(message)
        logger.info("\(message)")
    }

    func removeVideo(withIdentifier id: String) async throws {
        let fileURL = getCacheURL(forIdentifier: id, fileExtension: "mp4")
        try removeFile(at: fileURL)
        logger.debug("Removed video for id: \(id)")
    }

    func removeThumbnail(withIdentifier id: String) async throws {
        let fileURL = getThumbnailCacheURL(forIdentifier: id, fileExtension: "jpg")
        try removeFile(at: fileURL)
        logger.debug("Removed thumbnail for id: \(id)")
    }

    func calculateCacheSize() async throws -> UInt64 {
        let contents = try fileManager.contentsOfDirectory(at: videoCacheDirectory, includingPropertiesForKeys: [.fileSizeKey])
        return try contents.reduce(0) { total, url in
            let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
            return total + UInt64(resourceValues.fileSize ?? 0)
        }
    }

    func calculateThumbnailCacheSize() async throws -> UInt64 {
        let contents = try fileManager.contentsOfDirectory(at: thumbnailCacheDirectory, includingPropertiesForKeys: [.fileSizeKey])
        return try contents.reduce(0) { total, url in
            let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
            return total + UInt64(resourceValues.fileSize ?? 0)
        }
    }

    func logCacheStatus() {
        Task {
            let videoCount = try? await countFiles(in: videoCacheDirectory)
            let thumbnailCount = try? await countFiles(in: thumbnailCacheDirectory)
            let videoSize = try? await calculateSize(of: videoCacheDirectory)
            let thumbnailSize = try? await calculateSize(of: thumbnailCacheDirectory)
            
            let message = """
            📊 Cache Status:
            Videos: \(videoCount ?? 0) files (\(ByteCountFormatter.string(fromByteCount: Int64(videoSize ?? 0), countStyle: .file)))
            Thumbnails: \(thumbnailCount ?? 0) files (\(ByteCountFormatter.string(fromByteCount: Int64(thumbnailSize ?? 0), countStyle: .file)))
            """
            
            // Only log once
            if !hasLoggedInitialStatus {
                logger.info("\(message)")
                hasLoggedInitialStatus = true
            }
        }
    }
    
    private func countFiles(in directory: URL) async throws -> Int {
        let contents = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return contents.count
    }
    
    private func calculateSize(of directory: URL) async throws -> UInt64 {
        let contents = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
        return try contents.reduce(0) { total, url in
            let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
            return total + UInt64(resourceValues.fileSize ?? 0)
        }
    }

    private func saveCacheMetadata() throws {
        let metadataURL = videoCacheDirectory.appendingPathComponent("cache_metadata.json")
        let data = try JSONEncoder().encode(cacheMetadata)
        try data.write(to: metadataURL)
    }

    enum VideoCacheError: Error {
        case failedToGetSupportDirectory
        case failedToCreateDirectory
        case failedToSaveFile
        case failedToLoadFile
        case fileNotFound
        case invalidData
        case downloadFailed
        case thumbnailConversionFailed
    }
}
