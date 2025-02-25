import Foundation
import os
import UIKit

extension Notification.Name {
    static let videoCacheCleared = Notification.Name("videoCacheCleared")
}

actor VideoCacheManager {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReelAI", category: "VideoCacheManager")
    private let fileManager: FileManager
    private let videoCacheDirectory: URL
    private let thumbnailCacheDirectory: URL
    private let maxCacheSize: UInt64 = 500 * 1024 * 1024  // 500MB default
    private let maxThumbnailCacheSize: UInt64 = 50 * 1024 * 1024  // 50MB default
    
    // Use actor-isolated property for thread safety
    private var hasLoggedInitialStatus = false

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

        self.videoCacheDirectory = appSupportDir.appendingPathComponent("VideoCache", isDirectory: true)
        self.thumbnailCacheDirectory = appSupportDir.appendingPathComponent("ThumbnailCache", isDirectory: true)

        // Create cache directories if they don't exist
        if !fileManager.fileExists(atPath: videoCacheDirectory.path) {
            try fileManager.createDirectory(at: videoCacheDirectory, withIntermediateDirectories: true)
        }

        if !fileManager.fileExists(atPath: thumbnailCacheDirectory.path) {
            try fileManager.createDirectory(at: thumbnailCacheDirectory, withIntermediateDirectories: true)
        }

        // Add a .nomedia file to prevent thumbnails from showing in photo galleries
        let nomediaPath = thumbnailCacheDirectory.appendingPathComponent(".nomedia")
        if !fileManager.fileExists(atPath: nomediaPath.path) {
            try Data().write(to: nomediaPath)
        }

        // Log initial status in next run loop to ensure proper initialization
        Task { [self] in
            await checkAndLogInitialStatus()
        }
    }

    private func checkAndLogInitialStatus() async {
        guard !hasLoggedInitialStatus else { return }
        hasLoggedInitialStatus = true
        
        let message = "📱 VideoCacheManager initialized"
        print(message)
        logger.info("\(message)")
        logCacheStatus()
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

    // MARK: - Helper Methods

    private func getCacheURL(forIdentifier identifier: String, fileExtension: String) -> URL {
        return videoCacheDirectory.appendingPathComponent("\(identifier).\(fileExtension)")
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

    // MARK: - Public Methods

    func cacheVideo(from url: URL, withIdentifier id: String) async throws -> URL {
        let cachedFileURL = getCacheURL(forIdentifier: id, fileExtension: "mp4")

        // Return cached version if exists
        if fileExists(at: cachedFileURL) {
            return cachedFileURL
        }

        // Download and cache
        let (downloadURL, _) = try await URLSession.shared.download(from: url)
        try moveFileToCache(from: downloadURL, to: cachedFileURL)

        logger.debug("Cached video for id: \(id)")
        return cachedFileURL
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
            logger.info("\(message)")
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
}
