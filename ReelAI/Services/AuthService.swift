import FirebaseAuth
import FirebaseDatabase
import os

protocol AuthServiceProtocol {
    var currentUser: FirebaseAuth.User? { get }
    func signOut() throws
    func ensureCriticalPathsSync()
}

class FirebaseAuthService: AuthServiceProtocol {
    // MARK: - Shared Instance
    static let shared = FirebaseAuthService()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReelAI", category: "FirebaseAuthService")

    // MARK: - Properties
    private var criticalRefs: [DatabaseReference] = []

    var currentUser: FirebaseAuth.User? {
        Auth.auth().currentUser
    }

    // MARK: - Initialization
    private init() {
        setupFirebasePersistence()
    }

    // MARK: - Firebase Setup
    private func setupFirebasePersistence() {
        // Enable persistence before any Firebase calls
        Database.database().isPersistenceEnabled = true

        // Keep critical paths synced
        criticalRefs = [
            Database.database().reference().child("videos"),
            Database.database().reference().child("users"),
            Database.database().reference().child("profiles")
        ]

        ensureCriticalPathsSync()
    }

    // MARK: - Connection Management
    func ensureCriticalPathsSync() {
        criticalRefs.forEach { ref in
            ref.keepSynced(true)
            logger.debug("🔄 Ensuring sync for path: \(ref.url)")
        }
    }

    // MARK: - Auth Methods
    func signOut() throws {
        // 1. Stop syncing critical paths
        criticalRefs.forEach { ref in
            ref.keepSynced(false)
            logger.debug("Disabled sync for path: \(ref.url)")
        }

        // 2. Clear any cached data
        Database.database().purgeOutstandingWrites()

        // 3. Sign out from Firebase
        try Auth.auth().signOut()

        logger.debug("✅ Successfully signed out and cleaned up Firebase state")
    }
}
