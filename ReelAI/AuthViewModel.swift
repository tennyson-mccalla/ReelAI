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
        print("🔐 AuthViewModel: Initializing")

        // Listen for auth state changes
        // Store the listener to prevent it from being deallocated
        _ = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            print("🔐 AuthViewModel: Auth state changed - User: \(user != nil)")
            DispatchQueue.main.async {
                self?.user = user
                self?.isAuthenticated = user != nil
                print("🔐 AuthViewModel: Updated auth state - isAuthenticated: \(user != nil)")
            }
        }

        // Check initial state after setting up listener
        DispatchQueue.main.async { [weak self] in
            let currentUser = Auth.auth().currentUser
            print("🔐 AuthViewModel: Initial auth check - User: \(currentUser != nil)")
            self?.user = currentUser
            self?.isAuthenticated = currentUser != nil
        }
    }

    func signUp() async {
        print("🔐 AuthViewModel: Attempting sign up")
        isLoading = true
        errorMessage = nil
        do {
            _ = try await Auth.auth().createUser(withEmail: email, password: password)
            password = ""
            print("🔐 AuthViewModel: Sign up successful")
        } catch {
            print("🔐 AuthViewModel: Sign up failed - \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func signIn() async {
        print("🔐 AuthViewModel: Attempting sign in")
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        do {
            _ = try await Auth.auth().signIn(withEmail: email, password: password)
            await MainActor.run {
                password = ""
            }
            print("🔐 AuthViewModel: Sign in successful")
        } catch {
            print("🔐 AuthViewModel: Sign in failed - \(error.localizedDescription)")
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
        await MainActor.run {
            isLoading = false
        }
    }

    func signOut() {
        print("🔐 AuthViewModel: Attempting sign out")
        do {
            try Auth.auth().signOut()
            print("🔐 AuthViewModel: Sign out successful")
        } catch {
            print("🔐 AuthViewModel: Sign out failed - \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    func resetPassword() async {
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
            errorMessage = "Password reset email sent"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
