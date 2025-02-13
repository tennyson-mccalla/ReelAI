import SwiftUI
import os

/// A test view that allows switching between old and new profile implementations
/// This view is used for testing and validating the new actor-based profile system
struct ProfileTestView: View {
    @State private var useNewImplementation = true
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ReelAI",
        category: "ProfileTestView"
    )

    var body: some View {
        NavigationStack {
            VStack {
                // Implementation toggle
                Toggle("Use New Implementation", isOn: $useNewImplementation)
                    .padding()
                    .onChange(of: useNewImplementation) { newValue in
                        logger.debug("🔄 Switching to \(newValue ? "new" : "old") implementation")
                    }

                // Profile view container
                ZStack {
                    if useNewImplementation {
                        ProfileActorView()
                            .transition(.opacity)
                    } else {
                        ProfileView()
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut, value: useNewImplementation)
            }
            .navigationTitle("Profile Test")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    ProfileTestView()
}
