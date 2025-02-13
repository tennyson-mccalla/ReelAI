import FirebaseAuth
import FirebaseDatabase
import os

protocol AuthServiceProtocol {
    var currentUser: FirebaseAuth.User? { get }
    func signOut() throws
}

class FirebaseAuthService: AuthServiceProtocol {
    // MARK: - Shared Instance
    static let shared = FirebaseAuthService()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReelAI", category: "FirebaseAuthService")

    // MARK: - Properties
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
        let criticalRefs = [
            Database.database().reference().child("videos"),
            Database.database().reference().child("users"),
            Database.database().reference().child("profiles")
        ]

        criticalRefs.forEach { ref in
            ref.keepSynced(true)
            logger.debug("Enabled sync for path: \(ref.url)")
        }
    }

    // MARK: - Auth Methods
    func signOut() throws {
        try Auth.auth().signOut()
    }
}
