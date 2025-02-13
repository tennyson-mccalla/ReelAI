import FirebaseAuth

protocol AuthServiceProtocol {
    var currentUser: FirebaseAuth.User? { get }
    func signOut() throws
}

class FirebaseAuthService: AuthServiceProtocol {
    // MARK: - Shared Instance
    static let shared = FirebaseAuthService()

    var currentUser: FirebaseAuth.User? {
        Auth.auth().currentUser
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }

    private init() {}
}
