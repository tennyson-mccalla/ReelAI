import AVFoundation

struct PlayerState {
    var isPlaying: Bool = true
    var isMuted: Bool = false
    var progress: Double = 0
    var isReadyToPlay: Bool = false
    var isLoading: Bool = true
    var error: Error?
}
