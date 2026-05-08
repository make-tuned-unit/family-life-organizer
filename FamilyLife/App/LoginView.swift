import SwiftUI

struct LoginView: View {
    @Environment(AuthService.self) private var authService
    @State private var username = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var appeared = false
    @State private var showingSignUp = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Full-bleed background image
                Image("LoginBackground")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .ignoresSafeArea()

                // Gradient overlay for readability at bottom
                VStack(spacing: 0) {
                    Spacer()
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.15), .black.opacity(0.5)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: geo.size.height * 0.65)
                }
                .ignoresSafeArea()

                // Content — ScrollView handles keyboard avoidance
                ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer(minLength: geo.size.height * 0.3)

                    // Brand section
                    VStack(spacing: 8) {

                        Text("Kinrows")
                            .font(.system(size: 38, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)

                        Text("Grow together.")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .padding(.bottom, 36)

                    // Login form
                    VStack(spacing: 14) {
                        // Username field
                        HStack(spacing: 12) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(.white.opacity(0.6))
                                .frame(width: 20)
                            TextField("Username", text: $username)
                                .textContentType(.username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.system(size: 16))
                                .foregroundStyle(.white)
                                .tint(.white)
                        }
                        .padding(16)
                        .background(.ultraThinMaterial.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(.white.opacity(0.2), lineWidth: 0.5)
                        )

                        // Password field
                        HStack(spacing: 12) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(.white.opacity(0.6))
                                .frame(width: 20)
                            SecureField("Password", text: $password)
                                .textContentType(.password)
                                .font(.system(size: 16))
                                .foregroundStyle(.white)
                                .tint(.white)
                        }
                        .padding(16)
                        .background(.ultraThinMaterial.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(.white.opacity(0.2), lineWidth: 0.5)
                        )

                        // Error
                        if let errorMessage {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.system(size: 13))
                                Text(errorMessage)
                                    .font(.system(size: 13))
                            }
                            .foregroundStyle(WarmPalette.bad)
                            .padding(.top, 2)
                        }

                        // Sign in button
                        Button { login() } label: {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("Sign In")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [AccentTheme.sage.color, AccentTheme.sage.color.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: RoundedRectangle(cornerRadius: 16)
                        )
                        .shadow(color: AccentTheme.sage.color.opacity(0.4), radius: 12, y: 6)
                        .disabled(username.isEmpty || password.isEmpty || isLoading)
                        .opacity(username.isEmpty || password.isEmpty ? 0.6 : 1)
                        .padding(.top, 6)
                    }
                    .padding(.horizontal, 28)

                    // Sign up link
                    Button { showingSignUp = true } label: {
                        HStack(spacing: 4) {
                            Text("New here?")
                                .foregroundStyle(.white.opacity(0.5))
                            Text("Create an account")
                                .foregroundStyle(.white.opacity(0.85))
                                .fontWeight(.semibold)
                        }
                        .font(.system(size: 14))
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
                } // close ScrollView
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) { appeared = true }
        }
        .sheet(isPresented: $showingSignUp) {
            SignUpView()
        }
    }

    private func login() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await authService.login(username: username, password: password)
            } catch {
                errorMessage = "Invalid username or password"
            }
            isLoading = false
        }
    }
}

#Preview {
    LoginView()
        .environment(AuthService())
}
