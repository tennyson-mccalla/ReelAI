// Play/pause, progress bar, volume controls
// ~100 lines

import SwiftUI
import AVKit

struct PlayerControls: View {
    @Binding var state: PlayerState
    let player: AVPlayer?
    @State private var showDebugControls = false

    private var progress: Double {
        guard state.duration > 0 else { return 0 }
        let calculatedProgress = state.currentTime / state.duration
        print("📊 Progress: \(calculatedProgress), Time: \(state.currentTime), Duration: \(state.duration)")
        return calculatedProgress
    }

    var body: some View {
        VStack {
            // Top mute button
            HStack {
                Spacer()
                Image(systemName: state.isMuted ? "speaker.slash.fill" : "speaker.fill")
                    .foregroundColor(.white)
                    .font(.system(size: 20))
                    .padding(12)
                    .onTapGesture {
                        toggleMute()
                    }
                    .onLongPressGesture(minimumDuration: 1) {
                        print("🔍 Debug: Long press detected")
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showDebugControls.toggle()
                        }
                    }
            }
            .padding(.top, 48)

            Spacer()

            // Progress bar with increased visibility
            VStack(spacing: 0) {
                ProgressBar(progress: progress)
                    .frame(maxWidth: .infinity)
                    .frame(height: 2) // Slightly taller
                    .padding(.horizontal, 8)
                    .padding(.bottom, 40)

                #if DEBUG
                // Debug text to show progress values
                Text(String(format: "%.2f / %.2f", state.currentTime, state.duration))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.bottom, 8)
                #endif
            }
        }
        .overlay {
            #if DEBUG
            VStack {
                if showDebugControls {
                    debugControls
                        .padding(.vertical, 20)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(12)
                        .padding()
                        .transition(.move(edge: .bottom))
                }
            }
            .animation(.spring(), value: showDebugControls)
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
                    await VideoCacheManager.shared.logCacheStatus()
                }
            }
            .padding()
            .background(Color.black.opacity(0.5))
            .foregroundColor(.white)
            .cornerRadius(8)

            Button("Clear Cache") {
                Task {
                    do {
                        try await VideoCacheManager.shared.clearCache()
                        await VideoCacheManager.shared.logCacheStatus()
                    } catch {
                        print("Failed to clear cache: \(error.localizedDescription)")
                    }
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
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                Rectangle()
                    .fill(Color.white.opacity(0.3))

                // Progress fill
                Rectangle()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: geometry.size.width * max(0, min(1, progress)))
            }
        }
    }
}
