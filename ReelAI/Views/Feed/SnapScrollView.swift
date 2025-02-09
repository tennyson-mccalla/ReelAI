import SwiftUI
import UIKit

struct SnapScrollView: UIViewRepresentable {
    @Binding var currentIndex: Int
    let itemCount: Int
    let content: () -> AnyView
    let onSnap: (Int) -> Void
    
    init(currentIndex: Binding<Int>, itemCount: Int, @ViewBuilder content: @escaping () -> some View, onSnap: @escaping (Int) -> Void) {
        self._currentIndex = currentIndex
        self.itemCount = itemCount
        self.content = { AnyView(content()) }
        self.onSnap = onSnap
    }
    
    func makeUIView(context: Context) -> UIView {
        print("SnapScrollView: Creating container view")
        // Create a container view
        let containerView = UIView()
        containerView.backgroundColor = .black
        
        // Create scroll view
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.isPagingEnabled = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bounces = true
        scrollView.alwaysBounceVertical = true
        scrollView.isScrollEnabled = true
        scrollView.backgroundColor = .clear
        
        // Add scroll view to container
        containerView.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        // Create content view
        let hostingController = UIHostingController(rootView: content())
        hostingController.view.backgroundColor = .clear
        
        // Add content view to scroll view
        scrollView.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        
        // Set up constraints for content
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            hostingController.view.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
        
        // Set content size
        let screenHeight = UIScreen.main.bounds.height
        let contentHeight = CGFloat(itemCount) * screenHeight
        hostingController.view.heightAnchor.constraint(equalToConstant: contentHeight).isActive = true
        scrollView.contentSize = CGSize(width: UIScreen.main.bounds.width, height: contentHeight)
        
        print("SnapScrollView: Initial setup - content size: \(scrollView.contentSize), isScrollEnabled: \(scrollView.isScrollEnabled)")
        context.coordinator.scrollView = scrollView
        return containerView
    }
    
    func updateUIView(_ containerView: UIView, context: Context) {
        guard let scrollView = context.coordinator.scrollView else { return }
        
        // Update content size if needed
        let screenHeight = UIScreen.main.bounds.height
        let contentHeight = CGFloat(itemCount) * screenHeight
        if scrollView.contentSize.height != contentHeight {
            scrollView.contentSize = CGSize(width: UIScreen.main.bounds.width, height: contentHeight)
            if let hostView = scrollView.subviews.first {
                for constraint in hostView.constraints where constraint.firstAttribute == .height {
                    constraint.constant = contentHeight
                }
            }
        }
        
        // Update scroll position if needed
        let targetOffset = CGFloat(currentIndex) * screenHeight
        if abs(scrollView.contentOffset.y - targetOffset) > 1 {
            scrollView.setContentOffset(CGPoint(x: 0, y: targetOffset), animated: true)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: SnapScrollView
        weak var scrollView: UIScrollView?
        private var lastContentOffset: CGFloat = 0
        
        init(_ parent: SnapScrollView) {
            self.parent = parent
            super.init()
        }
        
        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            print("SnapScrollView: Begin dragging at offset \(scrollView.contentOffset.y)")
        }
        
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            print("SnapScrollView: Scrolling at offset \(scrollView.contentOffset.y)")
            let screenHeight = UIScreen.main.bounds.height
            let currentPage = Int(round(scrollView.contentOffset.y / screenHeight))
            
            if currentPage != Int(round(lastContentOffset / screenHeight)) {
                if currentPage >= 0 && currentPage < parent.itemCount {
                    print("SnapScrollView: Updating to page \(currentPage)")
                    parent.currentIndex = currentPage
                    parent.onSnap(currentPage)
                }
            }
            
            lastContentOffset = scrollView.contentOffset.y
        }
        
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            print("SnapScrollView: End dragging, will decelerate: \(decelerate)")
            if !decelerate {
                snapToNearestPage(scrollView)
            }
        }
        
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            print("SnapScrollView: End decelerating")
            snapToNearestPage(scrollView)
        }
        
        private func snapToNearestPage(_ scrollView: UIScrollView) {
            let screenHeight = UIScreen.main.bounds.height
            let page = round(scrollView.contentOffset.y / screenHeight)
            let targetOffset = page * screenHeight
            
            if abs(targetOffset - scrollView.contentOffset.y) > 1 {
                scrollView.setContentOffset(CGPoint(x: 0, y: targetOffset), animated: true)
            }
            
            let currentPage = Int(page)
            if currentPage >= 0 && currentPage < parent.itemCount {
                parent.currentIndex = currentPage
                parent.onSnap(currentPage)
                print("SnapScrollView: Snapped to page \(currentPage)")
            }
        }
    }
}
