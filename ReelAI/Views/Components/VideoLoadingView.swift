import SwiftUI

struct VideoLoadingView: View {
    let message: String?

    var body: some View {
        VStack {
            ProgressView()
            if let message = message {
                Text(message)
                    .foregroundColor(.white)
                    .padding(.top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.5))
    }
}

#Preview {
    VideoLoadingView(message: "Loading video...")
}
