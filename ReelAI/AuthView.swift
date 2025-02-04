import SwiftUI

struct AuthView: View {
    @EnvironmentObject var viewModel: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var showingPasswordReset = false
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text(isSignUp ? "Create Account" : "Sign In")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                TextField("Email", text: $email)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)

                SecureField("Password", text: $password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }

                Button(action: {
                    if isSignUp {
                        viewModel.signUp(email: email, password: password)
                    } else {
                        viewModel.signIn(email: email, password: password)
                    }
                }) {
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text(isSignUp ? "Sign Up" : "Sign In")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
                .disabled(viewModel.isLoading)

                Button(action: { isSignUp.toggle() }) {
                    Text(isSignUp ? "Already have an account? Sign In" : "Need an account? Sign Up")
                        .foregroundColor(.blue)
                }

                if !isSignUp {
                    Button("Forgot Password?") {
                        showingPasswordReset = true
                    }
                    .foregroundColor(.blue)
                }
            }
            .padding()
            .alert("Reset Password", isPresented: $showingPasswordReset) {
                TextField("Email", text: $email)
                Button("Cancel", role: .cancel) { }
                Button("Reset") {
                    viewModel.resetPassword(email: email)
                }
            } message: {
                Text("Enter your email to receive a password reset link")
            }
            .alert(
                "Error",
                isPresented: $showingError,
                actions: {
                    Button("OK") { }
                },
                message: {
                    Text(errorMessage)
                }
            )
        }
    }
}
