import SwiftUI

/// Represents different states that can be displayed in the content unavailable view
enum ContentUnavailableState {
    case loading
    case error(String)
    case empty

    var title: String {
        switch self {
        case .loading: return "Loading"
        case .error: return "Error Loading Videos"
        case .empty: return "No Videos Yet"
        }
    }

    var systemImage: String {
        switch self {
        case .loading: return "arrow.2.circlepath"
        case .error: return "exclamationmark.triangle"
        case .empty: return "video.slash"
        }
    }

    var message: String {
        switch self {
        case .loading: return "Please wait..."
        case .error(let message): return message
        case .empty: return "Videos you upload will appear here"
        }
    }
}

/// A wrapper around ContentUnavailableView that provides a consistent API for showing empty states
struct ContentUnavailableStateView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: systemImage)
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()
        }
    }

    /// Creates a view that represents an unavailable content state
    /// - Parameters:
    ///   - title: The title to display
    ///   - systemImage: The SF Symbol name to use
    ///   - message: The descriptive message to show
    init(_ title: String, systemImage: String, message: String) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
    }

    /// Creates a view that represents an unavailable content state
    /// - Parameter state: The state to display
    init(state: ContentUnavailableState) {
        self.title = state.title
        self.systemImage = state.systemImage
        self.message = state.message
    }
}

#if DEBUG
struct ContentUnavailableStateView_Previews: PreviewProvider {
    static var previews: some View {
        ContentUnavailableStateView(
            "No Videos",
            systemImage: "video.slash",
            message: "Videos you upload will appear here"
        )
    }
}
#endif
