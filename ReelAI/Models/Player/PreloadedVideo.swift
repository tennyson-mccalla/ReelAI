import Foundation
import AVFoundation

struct PreloadedVideo {
    let id: String
    let item: AVPlayerItem
    let position: Position
    var isPreloaded: Bool
    var loadDate: Date

    enum Position: Int {
        case previous = -1
        case current = 0
        case next = 1
    }

    init(id: String, item: AVPlayerItem, position: Position) {
        self.id = id
        self.item = item
        self.position = position
        self.isPreloaded = false
        self.loadDate = Date()
    }
}
