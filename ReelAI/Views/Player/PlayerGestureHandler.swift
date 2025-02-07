// Gesture recognition and handling
// ~80 lines

import UIKit

final class PlayerGestureHandler: NSObject {
    private let onTap: () -> Void

    init(onTap: @escaping () -> Void) {
        self.onTap = onTap
        super.init()
    }

    func addGestures(to view: UIView) {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        view.addGestureRecognizer(tapGesture)
    }

    @objc private func handleTap() {
        onTap()
    }
}
