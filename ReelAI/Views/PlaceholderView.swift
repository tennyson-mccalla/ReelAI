import SwiftUI

struct PlaceholderView: View {
    let feature: String

    var body: some View {
        VStack {
            Image(systemName: "hammer.fill")
                .font(.largeTitle)
                .padding()
            Text("\(feature) coming soon...")
                .font(.headline)
        }
        .foregroundColor(.gray)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
