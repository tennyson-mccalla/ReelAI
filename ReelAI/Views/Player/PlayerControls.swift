// Play/pause, progress bar, volume controls
// ~100 lines

import SwiftUI
import AVKit
import os

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
                MuteButton(isMuted: state.isMuted, onTap: {
                    print("🔈 Mute button tapped")
                    toggleMute()
                }, onLongPress: {
                    print("🔍 Long press detected - START")
                    Task { @MainActor in
                        showDebugControls.toggle()
                        print("🎛️ Debug controls visible: \(showDebugControls)")
                    }
                    print("🔍 Long press detected - END")
                })
                .padding(12)
            }
            .padding(.top, 48)
            .onChange(of: showDebugControls) { _, newValue in
                print("🔄 Debug controls state changed to: \(newValue)")
            }

            Spacer()

            // Progress bar with increased visibility
            VStack(spacing: 0) {
                ProgressBar(progress: progress)
                    .frame(maxWidth: .infinity)
                    .frame(height: 2)
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
            if showDebugControls {
                VStack {
                    Spacer()
                    debugControls
                        .transition(.opacity)
                    Spacer()
                }
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
        VStack(spacing: 12) {
            Text("Debug Controls")
                .foregroundColor(.white)
                .font(.headline)

            Button {
                Task {
                    await VideoCacheManager.shared.logCacheStatus()
                }
            } label: {
                Text("Test Cache")
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }

            Button {
                Task {
                    do {
                        try await VideoCacheManager.shared.clearCache()
                        await VideoCacheManager.shared.logCacheStatus()
                    } catch {
                        print("Failed to clear cache: \(error.localizedDescription)")
                    }
                }
            } label: {
                Text("Clear Cache")
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
        }
        .padding()
        .background(Color.black.opacity(0.5))
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

struct MuteButton: UIViewRepresentable {
    let isMuted: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReelAI", category: "MuteButton")

    func makeUIView(context: Context) -> UIView {
        // Create a container view for better touch handling
        let container = UIView()
        container.backgroundColor = .clear

        // Create the button
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: isMuted ? "speaker.slash.fill" : "speaker.fill"), for: .normal)
        button.tintColor = .white

        // Configure button layout
        button.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(button)

        // Make button fill container with padding
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 44),
            button.heightAnchor.constraint(equalToConstant: 44),
            container.widthAnchor.constraint(equalToConstant: 60),
            container.heightAnchor.constraint(equalToConstant: 60)
        ])

        // Add tap gesture to container
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        container.addGestureRecognizer(tapGesture)

        // Add long press gesture to container
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress))
        longPress.minimumPressDuration = 1.0
        container.addGestureRecognizer(longPress)

        context.coordinator.logger = logger
        logger.debug("🎯 MuteButton view created")

        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        guard let button = container.subviews.first as? UIButton else { return }
        button.setImage(UIImage(systemName: isMuted ? "speaker.slash.fill" : "speaker.fill"), for: .normal)
        logger.debug("🔄 MuteButton updated - isMuted: \(isMuted)")
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap, onLongPress: onLongPress)
    }

    class Coordinator: NSObject {
        let onTap: () -> Void
        let onLongPress: () -> Void
        var logger: Logger?

        init(onTap: @escaping () -> Void, onLongPress: @escaping () -> Void) {
            self.onTap = onTap
            self.onLongPress = onLongPress
            super.init()
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            logger?.debug("👆 Tap detected on mute button")
            if gesture.state == .ended {
                logger?.debug("✅ Executing mute button tap action")
                onTap()
            }
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            switch gesture.state {
            case .began:
                logger?.debug("👇 Long press began on mute button")
                onLongPress()
            case .ended:
                logger?.debug("☝️ Long press ended on mute button")
            default:
                break
            }
        }
    }
}
