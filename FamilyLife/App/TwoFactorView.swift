import SwiftUI

/// Second factor after the password step. Either collects an email (first login)
/// then a 6-digit code, or jumps straight to the code if an email is on file.
/// On success, AuthService flips `isAuthenticated` and the app root swaps away.
struct TwoFactorView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    let initialStep: AuthService.LoginStep

    private enum Mode { case email, code }
    @State private var mode: Mode = .code
    @State private var challenge = ""
    @State private var emailHint: String?
    @State private var email = ""
    @State private var code = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var resendNote: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                Spacer(minLength: 80)

                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(AccentTheme.sage.color)

                Text(mode == .email ? "Verify your email" : "Enter your code")
                    .font(.flScreenTitle)
                    .foregroundStyle(WarmPalette.ink1)

                Text(subtitle)
                    .font(.flSubheadline)
                    .foregroundStyle(WarmPalette.ink2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                if mode == .email {
                    field {
                        TextField("you@example.com", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } else {
                    field {
                        TextField("123456", text: $code)
                            .textContentType(.oneTimeCode)
                            .keyboardType(.numberPad)
                            .font(.system(.title2, design: .rounded).weight(.semibold))
                            .tracking(6)
                    }
                }

                if let resendNote {
                    Label(resendNote, systemImage: "checkmark.circle.fill")
                        .font(.flFootnote)
                        .foregroundStyle(WarmPalette.good)
                }

                Button { primaryAction() } label: {
                    if isWorking { ProgressView() }
                    else { Text(mode == .email ? "Send code" : "Verify") }
                }
                .buttonStyle(.flCTA(fill: AccentTheme.sage.color))
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.6)
                .padding(.top, 4)

                if mode == .code {
                    Button { resend() } label: {
                        Text("Resend code")
                            .font(.flSubheadline)
                            .foregroundStyle(WarmPalette.ink2)
                    }
                    .disabled(isWorking)
                }

                Button { dismiss() } label: {
                    Text("Back")
                        .font(.flSubheadline)
                        .foregroundStyle(WarmPalette.ink3)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 40)
        }
        .background { AmbientBackground(style: .home) }
        .inlineError(errorMessage) { errorMessage = nil }
        .preferredColorScheme(.light)
        .onAppear(perform: configureFromStep)
    }

    private var subtitle: String {
        switch mode {
        case .email: return "We'll email a 6-digit code to confirm it's you. This becomes your sign-in verification."
        case .code:  return "We sent a 6-digit code to \(emailHint ?? "your email"). Enter it to finish signing in."
        }
    }

    private var canSubmit: Bool {
        if isWorking { return false }
        return mode == .email ? email.contains("@") : code.count >= 6
    }

    private let deliveryFailedMessage = "We couldn't send your code — check the address or tap Resend."

    private func configureFromStep() {
        switch initialStep {
        case .needsEmailEnrollment(let ch):
            challenge = ch; mode = .email
        case .needsCode(let ch, let hint, let emailSent):
            challenge = ch; emailHint = hint; mode = .code
            if !emailSent { errorMessage = deliveryFailedMessage }
        case .authenticated:
            dismiss()
        }
    }

    private func primaryAction() {
        errorMessage = nil; resendNote = nil; isWorking = true
        Task {
            do {
                if mode == .email {
                    let step = try await auth.submitLoginEmail(challenge: challenge, email: email.trimmingCharacters(in: .whitespaces))
                    if case let .needsCode(_, hint, emailSent) = step {
                        emailHint = hint; mode = .code; code = ""
                        if !emailSent { errorMessage = deliveryFailedMessage }
                    }
                } else {
                    try await auth.verifyLoginCode(challenge: challenge, code: code.trimmingCharacters(in: .whitespaces))
                }
            } catch {
                errorMessage = mode == .email
                    ? "Couldn't send the code. Check the address and try again."
                    : "That code didn't work. Check it or resend a new one."
            }
            isWorking = false
        }
    }

    private func resend() {
        errorMessage = nil; resendNote = nil; isWorking = true
        Task {
            do {
                let sent = try await auth.resendLoginCode(challenge: challenge)
                if sent { resendNote = "A new code is on its way." }
                else { errorMessage = deliveryFailedMessage }
            } catch {
                errorMessage = "Couldn't resend the code."
            }
            isWorking = false
        }
    }

    @ViewBuilder private func field<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .foregroundStyle(WarmPalette.ink1)
            .font(.flBody)
            .padding(16)
            .frame(maxWidth: .infinity)
            .flGlassSurface(tint: .white.opacity(0.03), strokeOpacity: 0.08, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.tile))
            .multilineTextAlignment(.center)
    }
}

#Preview {
    TwoFactorView(initialStep: .needsCode(challenge: "x", emailHint: "j***@icloud.com", emailSent: true))
        .environment(AuthService())
}
