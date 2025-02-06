import SwiftUI
struct LoginView: View {
    @State private var email: String = ""
    @State private var password: String = ""

    var body: some View {
        VStack {
            TextField("Email", text: $email)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)

            SecureField("Password", text: $password)

            Button("Sign In") {
                // Sign in action
            }
        }
        .padding()
    }
}
