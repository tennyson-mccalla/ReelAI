import SwiftUI
import AVKit

struct CustomVideoPlayer: UIViewRepresentable {
    let player: AVPlayer?
    var onTap: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let playerLayer = AVPlayerLayer()
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        view.layer.addSublayer(playerLayer)

        let gestureHandler = PlayerGestureHandler(onTap: onTap)
        gestureHandler.addGestures(to: view)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let playerLayer = uiView.layer.sublayers?.first as? AVPlayerLayer {
            playerLayer.player = player
            playerLayer.frame = uiView.bounds
            playerLayer.videoGravity = .resizeAspect
        }
    }
}
