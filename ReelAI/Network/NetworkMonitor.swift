import Foundation
import Network

@MainActor
class NetworkMonitor {
    /// Represents the current status of the network connection
    public enum NetworkStatus {
        /// Network is available and functioning
        case satisfied
        /// Network is unavailable
        case unsatisfied
        /// Network requires a connection to be established
        case requiresConnection
        /// Network status cannot be determined
        case unknown
    }

    /// Represents the type of network connection
    enum ConnectionType {
        /// Wi-Fi connection
        case wifi
        /// Cellular connection
        case cellular
        /// Wired ethernet connection
        case ethernet
        /// Unknown connection type
        case unknown
    }

    /// Shared instance for singleton access
    static let shared = NetworkMonitor()

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "NetworkMonitor", qos: .background)

    private var currentStatus: NetworkStatus = .unknown
    private var currentConnectionType: ConnectionType = .unknown
    private var statusUpdateHandlers: [(NetworkStatus) -> Void] = []
    private var connectionTypeHandlers: [(ConnectionType) -> Void] = []

    /// Initializes a new network monitor instance
    public init() {
        monitor = NWPathMonitor()
        setupMonitoring()
    }

    private func setupMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }

            // Determine network status
            let status: NetworkStatus
            switch path.status {
            case .satisfied:
                status = .satisfied
            case .unsatisfied:
                status = .unsatisfied
            case .requiresConnection:
                status = .requiresConnection
            @unknown default:
                status = .unknown
            }

            // Determine connection type
            let connectionType: ConnectionType
            if path.usesInterfaceType(.wifi) {
                connectionType = .wifi
            } else if path.usesInterfaceType(.cellular) {
                connectionType = .cellular
            } else if path.usesInterfaceType(.wiredEthernet) {
                connectionType = .ethernet
            } else {
                connectionType = .unknown
            }

            // Update on main actor
            Task { @MainActor in
                // We already have self from the outer guard
                self.currentStatus = status
                self.currentConnectionType = connectionType

                // Create local copies of handlers
                let handlers = self.statusUpdateHandlers
                let typeHandlers = self.connectionTypeHandlers

                // Execute handlers
                handlers.forEach { $0(status) }
                typeHandlers.forEach { $0(connectionType) }
            }
        }
    }

    func startMonitoring(statusHandler: ((NetworkStatus) -> Void)? = nil) {
        if let statusHandler = statusHandler {
            statusUpdateHandlers.append(statusHandler)
        }
        monitor.start(queue: queue)
    }

    func stopMonitoring() {
        monitor.cancel()
    }

    func addStatusHandler(_ handler: @escaping (NetworkStatus) -> Void) {
        statusUpdateHandlers.append(handler)
    }

    func addConnectionTypeHandler(_ handler: @escaping (ConnectionType) -> Void) {
        connectionTypeHandlers.append(handler)
    }

    var isConnected: Bool {
        return currentStatus == .satisfied
    }

    var connectionType: ConnectionType {
        return currentConnectionType
    }

    @MainActor
    func checkConnectivity() async -> Bool {
        return await withCheckedContinuation { continuation in
            guard let url = URL(string: "https://www.apple.com") else {
                continuation.resume(returning: false)
                return
            }

            var request = URLRequest(url: url)
            request.timeoutInterval = 5

            let task = URLSession.shared.dataTask(with: request) { _, response, error in
                let isReachable = (error == nil) &&
                                  ((response as? HTTPURLResponse)?.statusCode ?? 0) == 200
                continuation.resume(returning: isReachable)
            }
            task.resume()
        }
    }

    deinit {
        // Create a weak reference to monitor to avoid capturing self
        let monitorRef = monitor
        Task {
            await MainActor.run {
                monitorRef.cancel()
            }
        }
    }
}

// Extension to provide more detailed network information
extension NetworkMonitor.ConnectionType {
    var description: String {
        switch self {
        case .wifi: return "Wi-Fi"
        case .cellular: return "Cellular"
        case .ethernet: return "Ethernet"
        case .unknown: return "Unknown"
        }
    }

    var isHighSpeed: Bool {
        switch self {
        case .wifi, .ethernet: return true
        case .cellular, .unknown: return false
        }
    }
}
