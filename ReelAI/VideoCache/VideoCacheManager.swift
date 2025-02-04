import Foundation
import AVFoundation

actor VideoCacheManager {
    static let shared = VideoCacheManager()

    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let maxCacheSize: UInt64 = 500 * 1024 * 1024  // 500MB default

    private init() {
        let cachePath = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)[0]
        cacheDirectory = URL(fileURLWithPath: cachePath).appendingPathComponent("VideoCache")

        try? fileManager.createDirectory(at: cacheDirectory,
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
}
