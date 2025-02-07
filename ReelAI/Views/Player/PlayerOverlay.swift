// Loading states, error views, info overlays
// ~50 lines

import SwiftUI

enum PlayerOverlay {
    struct ErrorView: View {
        let error: Error
        let onRetry: () -> Void

        var body: some View {
            VStack {
                Text("Failed to load video")
                    .foregroundColor(.white)
                Text(error.localizedDescription)
                    .foregroundColor(.gray)
                    .font(.caption)
                Button("Retry", action: onRetry)
                    .foregroundColor(.white)
                    .padding()
            }
        }
    }

    struct LoadingView: View {
        var body: some View {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
        }
    }
}
