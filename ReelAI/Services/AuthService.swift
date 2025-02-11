import FirebaseAuth

protocol AuthServiceProtocol {
    var currentUser: User? { get }
    func signOut() throws
}

class FirebaseAuthService: AuthServiceProtocol {
    var currentUser: User? {
        Auth.auth().currentUser
    }
    
    func signOut() throws {
        try Auth.auth().signOut()
    }
}
