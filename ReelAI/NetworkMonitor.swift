import Foundation
import Network
import Combine
import SwiftUI
import os

class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    @Published private(set) var isConnected = true
    @Published private(set) var isExpensive = false
    @Published private(set) var isConstrained = false
    @Published private(set) var connectionType = NWInterface.InterfaceType.other

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                self?.isExpensive = path.isExpensive
                self?.isConstrained = path.isConstrained
                self?.connectionType = path.availableInterfaces.first?.type ?? .other

                // Use os.Logger for structured logging.
                let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReelAI", category: "NetworkMonitor")
                logger.info("Network status: \(path.status == .satisfied ? "Connected" : "Disconnected")")

                let connectionTypeString: String = {
                    guard let type = path.availableInterfaces.first?.type else { return "unknown" }
                    switch type {
                    case .wifi: return "wifi"
                    case .cellular: return "cellular"
                    case .wiredEthernet: return "ethernet"
                    case .loopback: return "loopback"
                    case .other: return "other"
                    @unknown default: return "unknown"
                    }
                }()
                logger.info("Connection type: \(connectionTypeString)")
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
