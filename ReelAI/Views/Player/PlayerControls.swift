// Play/pause, progress bar, volume controls
// ~100 lines

import SwiftUI
import AVKit

struct PlayerControls: View {
    @Binding var state: PlayerState
    let player: AVPlayer?
    @State private var showDebugControls = false  // Add state for visibility

    var body: some View {
        VStack {
            // Top mute button
            HStack {
                Spacer()
                // Wrap the button in a gesture container
                Image(systemName: state.isMuted ? "speaker.slash.fill" : "speaker.fill")
                    .foregroundColor(.white)
                    .font(.system(size: 20))
                    .padding(12)
                    .onTapGesture {
                        toggleMute()
                    }
                    .onLongPressGesture(minimumDuration: 1) {  // Specify duration
                        print("Debug: Long press detected")  // Add debug print
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showDebugControls.toggle()
                        }
                    }
            }
            .padding(.top, 48)

            Spacer()

            // Progress bar
            ProgressBar(progress: state.progress)
                .padding(.horizontal, 8)
                .padding(.bottom, 40)
        }
        .overlay {
            #if DEBUG
            VStack {
                Spacer()
                    .frame(height: 300)  // Add fixed spacing from top
                if showDebugControls {  // Only show when toggled
                    debugControls
                        .padding(.bottom, 150)  // Increased padding further to show both buttons
                        .transition(.opacity)  // Smooth fade transition
                }
                Spacer()  // This will push the buttons up from the bottom
            }
            #endif
        }
    }

    private func toggleMute() {
        state.isMuted.toggle()
        player?.isMuted = state.isMuted
    }

    #if DEBUG
    private var debugControls: some View {
        VStack {
            Button("Test Cache") {
                Task {
                    await VideoCacheManager.shared.debugPrintCache()
                }
            }
            .padding()
            .background(Color.black.opacity(0.5))
            .foregroundColor(.white)
            .cornerRadius(8)

            Button("Clear Cache") {
                Task {
                    await VideoCacheManager.shared.clearCache()
                    await VideoCacheManager.shared.debugPrintCache()
                }
            }
            .padding()
            .background(Color.orange.opacity(0.5))
            .foregroundColor(.white)
            .cornerRadius(8)
        }
    }
    #endif
}

struct ProgressBar: View {
    let progress: Double

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.2))
            .frame(height: 1.5)
            .overlay(
                Rectangle()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: UIScreen.main.bounds.width * progress)
                    .frame(height: 1.5),
                alignment: .leading
            )
    }
}
