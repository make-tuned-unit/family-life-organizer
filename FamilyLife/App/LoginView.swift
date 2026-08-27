import SwiftUI

struct LoginView: View {
    var onCreateAccount: (() -> Void)? = nil

    @Environment(AuthService.self) private var authService
    @State private var username = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingSignUp = false
    @State private var twoFactor: TwoFactorPresentation?

    private struct TwoFactorPresentation: Identifiable {
        let id = UUID()
        let step: AuthService.LoginStep
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                Spacer(minLength: 80)

                VStack(spacing: 8) {
                    Text("Kinrows")
                        .font(.flHero)
                        .foregroundStyle(WarmPalette.ink1)
                    Text("Grow together.")
                        .font(.flBody.weight(.medium))
                        .foregroundStyle(WarmPalette.ink2)
                }
                .padding(.bottom, 36)

                VStack(spacing: 14) {
                    AppleSignInButton(label: .signIn, onError: { errorMessage = $0 })

                    HStack(spacing: 12) {
                        Rectangle().fill(WarmPalette.ink4.opacity(0.4)).frame(height: 1)
                        Text("or")
                            .font(.flCaption)
                            .foregroundStyle(WarmPalette.ink3)
                        Rectangle().fill(WarmPalette.ink4.opacity(0.4)).frame(height: 1)
                    }
                    .padding(.vertical, 4)

                    formField(icon: "person.fill", placeholder: "Username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    HStack(spacing: 12) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(WarmPalette.ink3)
                            .frame(width: 20)
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .font(.flBody)
                    }
                    .padding(16)
                    .flGlassSurface(tint: .white.opacity(0.03), strokeOpacity: 0.08, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small))

                    Button { login() } label: {
                        if isLoading {
                            ProgressView()
                        } else {
                            Text("Sign in")
                        }
                    }
                    .buttonStyle(.flCTA(fill: AccentTheme.sage.color))
                    .disabled(username.isEmpty || password.isEmpty || isLoading)
                    .opacity(username.isEmpty || password.isEmpty ? 0.6 : 1)
                    .padding(.top, 6)
                }
                .padding(.horizontal, 28)

                Button {
                    if let onCreateAccount {
                        onCreateAccount()
                    } else {
                        showingSignUp = true
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("New here?")
                            .foregroundStyle(WarmPalette.ink3)
                        Text("Create an account")
                            .foregroundStyle(WarmPalette.ink1)
                            .fontWeight(.semibold)
                    }
                    .font(.flSubheadline)
                }
                .padding(.top, 16)

                LegalConsentFooter()
                    .padding(.top, 20)
                    .padding(.bottom, 40)
            }
        }
        .background { AmbientBackground(style: .home) }
        .inlineError(errorMessage) { errorMessage = nil }
        .preferredColorScheme(.light)
        .sheet(isPresented: $showingSignUp) {
            SignUpView(mode: .create)
        }
        .fullScreenCover(item: $twoFactor) { presentation in
            TwoFactorView(initialStep: presentation.step)
                .environment(authService)
        }
    }

    private func formField(icon: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(WarmPalette.ink3)
                .frame(width: 20)
            TextField(placeholder, text: text)
                .font(.flBody)
        }
        .padding(16)
        .flGlassSurface(tint: .white.opacity(0.03), strokeOpacity: 0.08, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small))
    }

    private func login() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let step = try await authService.login(username: username, password: password)
                switch step {
                case .authenticated:
                    break
                case .needsEmailEnrollment, .needsCode:
                    twoFactor = TwoFactorPresentation(step: step)
                }
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
