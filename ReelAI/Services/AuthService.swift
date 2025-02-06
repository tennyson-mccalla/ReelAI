import FirebaseAuth

protocol AuthServiceProtocol {
    var currentUser: User? { get }
}

class FirebaseAuthService: AuthServiceProtocol {
    var currentUser: User? {
        Auth.auth().currentUser
    }
}
