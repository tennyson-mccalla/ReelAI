import SwiftUI
import UIKit

struct SnapScrollView<Content: View>: UIViewRepresentable {
    let content: Content
    let onSnap: (Int) -> Void
    @Binding var currentIndex: Int

    init(currentIndex: Binding<Int>, @ViewBuilder content: () -> Content, onSnap: @escaping (Int) -> Void) {
        self.content = content()
        self._currentIndex = currentIndex
        self.onSnap = onSnap
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.isPagingEnabled = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bounces = false
        scrollView.contentInsetAdjustmentBehavior = .never

        let hostView = UIHostingController(rootView: content)
        hostView.view.translatesAutoresizingMaskIntoConstraints = false
        hostView.view.backgroundColor = .clear

        scrollView.addSubview(hostView.view)

        NSLayoutConstraint.activate([
            hostView.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hostView.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hostView.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hostView.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            hostView.view.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])

        DispatchQueue.main.async {
            let height = UIScreen.main.bounds.height * CGFloat(hostView.view.subviews.count)
            scrollView.contentSize = CGSize(width: UIScreen.main.bounds.width, height: height)
        }

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.parent = self
    }

    class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: SnapScrollView
        private var isScrolling = false

        init(_ parent: SnapScrollView) {
            self.parent = parent
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            isScrolling = true
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            let index = Int(scrollView.contentOffset.y / scrollView.bounds.height)
            if parent.currentIndex != index {
                parent.currentIndex = index
                parent.onSnap(index)
            }
            isScrolling = false
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate {
                let index = Int(scrollView.contentOffset.y / scrollView.bounds.height)
                if parent.currentIndex != index {
                    parent.currentIndex = index
                    parent.onSnap(index)
                }
                isScrolling = false
            }
        }
    }
}
