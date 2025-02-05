import SwiftUI

struct AuthView: View {
    @EnvironmentObject var viewModel: AuthViewModel
    @State private var isSignUp = false
    @State private var showingPasswordReset = false

    var body: some View {
        VStack(spacing: 20) {
            // Add Spacer at top to push content down
            Spacer()

            // Logo or app name
            Text("ReelAI")
                .font(.largeTitle)
                .bold()

            // Input fields in a VStack with padding
            VStack(spacing: 16) {
                TextField("Email", text: $viewModel.email)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    // Make touch target larger
                    .frame(height: 44)

                SecureField("Password", text: $viewModel.password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    // Make touch target larger
                    .frame(height: 44)

                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            .padding(.horizontal, 40)

            // Action Buttons
            VStack(spacing: 12) {
                Button(action: {
                    if isSignUp {
                        viewModel.signUp()
                    } else {
                        viewModel.signIn()
                    }
                }) {
                    HStack {
                        if viewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text(isSignUp ? "Sign Up" : "Sign In")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
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
            .padding(.horizontal, 40)

            // Add Spacer at bottom to push content up
            Spacer()
        }
        .background(Color(.systemBackground))
        .alert("Reset Password", isPresented: $showingPasswordReset) {
            TextField("Email", text: $viewModel.email)
            Button("Cancel", role: .cancel) { }
            Button("Reset") {
                viewModel.resetPassword()
            }
        } message: {
            Text("Enter your email to receive a password reset link")
        }
    }
}
