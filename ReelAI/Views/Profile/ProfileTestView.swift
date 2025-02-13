import SwiftUI

/// A test view that allows switching between old and new profile implementations
struct ProfileTestView: View {
    @State private var useNewImplementation = true

    var body: some View {
        NavigationStack {
            Group {
                if useNewImplementation {
                    ProfileActorView()
                } else {
                    ProfileView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Toggle("New Implementation", isOn: $useNewImplementation)
                        .toggleStyle(.switch)
                }
            }
        }
    }
}

#Preview {
    ProfileTestView()
}
