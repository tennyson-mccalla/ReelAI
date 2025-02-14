import Foundation
import AVFoundation

struct PlayerState: Equatable {
    // MARK: - Playback State
    var isPlaying: Bool = false
    var isMuted: Bool = true
    var isBuffering: Bool = false
    var isPreloadingNext: Bool = false

    // MARK: - Progress
    var currentTime: Double = 0
    var duration: Double = 0
    var bufferingProgress: Double = 0

    // MARK: - Video Info
    var currentVideoID: String?
    var preloadedVideoIDs: Set<String> = []

    // MARK: - Error Handling
    var error: PlayerError?

    // MARK: - Equatable
    static func == (lhs: PlayerState, rhs: PlayerState) -> Bool {
        lhs.isPlaying == rhs.isPlaying &&
        lhs.isMuted == rhs.isMuted &&
        lhs.isBuffering == rhs.isBuffering &&
        lhs.currentTime == rhs.currentTime &&
        lhs.duration == rhs.duration &&
        lhs.bufferingProgress == rhs.bufferingProgress &&
        lhs.currentVideoID == rhs.currentVideoID &&
        lhs.preloadedVideoIDs == rhs.preloadedVideoIDs &&
        lhs.error?.localizedDescription == rhs.error?.localizedDescription
    }
}

// MARK: - Player Errors
enum PlayerError: LocalizedError {
    case failedToLoad(String)
    case playbackStalled(String)
    case networkError(String)
    case resourceUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .failedToLoad(let videoID):
            return "Failed to load video: \(videoID)"
        case .playbackStalled(let videoID):
            return "Playback stalled for video: \(videoID)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .resourceUnavailable(let videoID):
            return "Video resource unavailable: \(videoID)"
        }
    }
}
