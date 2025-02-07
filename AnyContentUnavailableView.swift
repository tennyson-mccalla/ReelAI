import SwiftUI

/// A type-erased wrapper around ContentUnavailableView that hardcodes the generics.
struct AnyContentUnavailableView: View {
    private let anyView: AnyView

    /// Initializes with a title, system image, and a description.
    init(title: String, systemImage: String, description: Text) {
        // Wrap ContentUnavailableView with fixed generic types.
        self.anyView = AnyView(
            ContentUnavailableView<String, String, Text>(
                title,
                systemImage: systemImage,
                description: description
            )
        )
    }

    var body: some View {
        anyView
    }
}
