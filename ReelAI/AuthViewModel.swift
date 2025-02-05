import SwiftUI
import FirebaseAuth

class AuthViewModel: ObservableObject {
    @Published var user: User?
    @Published var isAuthenticated = false
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var email = ""
    @Published var password = ""

    init() {
        // Listen for auth state changes
        // Store the listener to prevent it from being deallocated
        _ = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                self?.user = user
                self?.isAuthenticated = user != nil
            }
        }
    }

    func signUp() {
        isLoading = true
        errorMessage = nil
        Auth.auth().createUser(withEmail: email, password: password) { [weak self] _, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    return
                }
                self?.password = ""
            }
        }
    }

    func signIn() {
        isLoading = true
        errorMessage = nil
        Auth.auth().signIn(withEmail: email, password: password) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    self?.isLoading = false
                    return
                }
                self?.password = ""
                self?.isLoading = false
            }
        }
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resetPassword() {
        Auth.auth().sendPasswordReset(withEmail: email) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    return
                }
                self?.errorMessage = "Password reset email sent"
            }
        }
    }
}
