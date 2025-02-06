import SwiftUI

struct PlaceholderView: View {
    let feature: String

    var body: some View {
        ContentUnavailableView(
            "\(feature) coming soon...",
            systemImage: "hammer.fill",
            description: Text("This feature is under development")
        )
    }
}
