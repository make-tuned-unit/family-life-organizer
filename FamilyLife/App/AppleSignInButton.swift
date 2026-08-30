import AuthenticationServices
import CryptoKit
import SwiftUI

enum AppleNonce {
    static func random() -> String {
        UUID().uuidString
    }

    static func sha256(_ raw: String) -> String {
        SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Official Sign in with Apple control, sized to match `.flCTA`.
struct AppleSignInButton: View {
    enum Label {
        case signIn
        case signUp

        var appleLabel: SignInWithAppleButton.Label {
            switch self {
            case .signIn: .signIn
            case .signUp: .signUp
            }
        }

        var accessibilityText: String {
            switch self {
            case .signIn: "Sign in with Apple"
            case .signUp: "Sign up with Apple"
            }
        }
    }

    var label: Label = .signIn
    var inviteCode: String? = nil
    var householdName: String? = nil
    /// When set, the identity token is handed to the caller instead of signing in.
    var onIdentity: ((String, String) -> Void)? = nil
    var onError: (String) -> Void

    @Environment(AuthService.self) private var auth
    @State private var rawNonce = ""
    @State private var isWorking = false

    var body: some View {
        SignInWithAppleButton(label.appleLabel) { request in
            rawNonce = AppleNonce.random()
            request.requestedScopes = [.fullName, .email]
            request.nonce = AppleNonce.sha256(rawNonce)
        } onCompletion: { result in
            Task { await handle(result) }
        }
        .signInWithAppleButtonStyle(.black)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .disabled(isWorking)
        .accessibilityLabel(Text(verbatim: label.accessibilityText))
    }

    @MainActor
    private func handle(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            let ns = error as NSError
            if ns.domain == ASAuthorizationError.errorDomain,
               ns.code == ASAuthorizationError.canceled.rawValue {
                return
            }
            onError("Apple sign-in didn’t complete. Try again or use email.")
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8) else {
                onError("Apple sign-in didn’t complete. Try again or use email.")
                return
            }
            isWorking = true
            defer { isWorking = false }
            if !credential.user.isEmpty {
                auth.rememberAppleUserID(credential.user)
            }
            if let onIdentity {
                onIdentity(identityToken, rawNonce)
                return
            }
            let name: String? = {
                guard let fullName = credential.fullName else { return nil }
                let formatted = PersonNameComponentsFormatter().string(from: fullName)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return formatted.isEmpty ? nil : formatted
            }()
            do {
                try await auth.signInWithApple(
                    identityToken: identityToken,
                    rawNonce: rawNonce,
                    name: name,
                    inviteCode: inviteCode,
                    householdName: householdName
                )
            } catch APIError.serverMessage(_, let message) {
                onError(message)
            } catch {
                onError("Apple sign-in didn’t complete. Try again or use email.")
            }
        }
    }
}

struct LegalConsentFooter: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("By continuing you agree to the Terms of Use and Privacy Policy. You must be 18 or older.")
                .font(.flCaption2)
                .foregroundStyle(WarmPalette.ink3)
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Link("Terms of Use", destination: AppConfig.termsOfUseURL)
                Link("Privacy Policy", destination: AppConfig.privacyPolicyURL)
            }
            .font(.flCaption.weight(.medium))
        }
        .padding(.horizontal, 24)
    }
}

#Preview {
    AppleSignInButton { _ in }
        .padding()
        .background { AmbientBackground(style: .home) }
        .environment(AuthService())
}
