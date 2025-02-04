struct AuthView: View {
    @StateObject private var viewModel = AuthViewModel()
    
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
                    .autocapitalization(.none)
                    // Make touch target larger
                    .frame(height: 44)
                
                SecureField("Password", text: $viewModel.password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    // Make touch target larger
                    .frame(height: 44)
            }
            .padding(.horizontal, 40)
            
            // Buttons with larger touch targets
            Button(action: viewModel.signIn) {
                Text("Sign In")
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .padding(.horizontal, 40)
            
            // Add Spacer at bottom to push content up
            Spacer()
        }
        .background(Color(.systemBackground))
    }
} 