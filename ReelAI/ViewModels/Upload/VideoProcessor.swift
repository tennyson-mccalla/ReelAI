// Video processing logic (compression, thumbnail generation)
// ~100 lines

import AVFoundation
import UIKit

@MainActor
final class VideoProcessor {
    enum Quality {
        case high    // 1080p, 8Mbps
        case medium  // 720p, 5Mbps
        case low     // 480p, 2Mbps
        case custom(width: Int, bitrate: Int)

        var configuration: (width: Int, bitrate: Int) {
            switch self {
            case .high:    return (1920, 8_000_000)
            case .medium:  return (1280, 5_000_000)
            case .low:     return (858, 2_000_000)
            case .custom(let width, let bitrate): return (width, bitrate)
            }
        }

        var exportPreset: String {
            switch self {
            case .high: return AVAssetExportPreset1920x1080
            case .medium: return AVAssetExportPreset1280x720
            case .low: return AVAssetExportPreset640x480
            case .custom: return AVAssetExportPresetPassthrough
            }
        }
    }

    func compressVideo(at sourceURL: URL, quality: Quality) async throws -> URL {
        let inputSize = try sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        print("📱 Original video size: \(Float(inputSize) / 1_000_000)MB")

        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent(UUID().uuidString + ".mp4")

        let asset = AVURLAsset(url: sourceURL)

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: quality.exportPreset
        ) else {
            throw NSError(domain: "VideoCompression", code: -1)
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        try await exportSession.export(to: outputURL, as: .mp4)

        if let outputSize = try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            print("📱 Compressed video size: \(Float(outputSize) / 1_000_000)MB")
            print("📱 Compression ratio: \(Float(outputSize) / Float(inputSize))")
            return outputURL
        }

        throw NSError(domain: "VideoCompression", code: -1)
    }

    func generateThumbnail(from url: URL) async throws -> UIImage {
        let asset = AVURLAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true

        return try await withCheckedThrowingContinuation { continuation in
            imageGenerator.generateCGImageAsynchronously(for: .zero) { cgImage, _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let cgImage = cgImage else {
                    continuation.resume(throwing: NSError(domain: "ThumbnailError", code: -1))
                    return
                }

                let thumbnail = UIImage(cgImage: cgImage)
                continuation.resume(returning: thumbnail)
            }
        }
    }
}
