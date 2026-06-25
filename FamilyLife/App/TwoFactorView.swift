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
        ZStack {
            Image("LoginBackground")
                .resizable().aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
            Rectangle().fill(.black.opacity(0.45)).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    Spacer(minLength: 120)

                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.white)

                    Text(mode == .email ? "Verify your email" : "Enter your code")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)

                    Text(subtitle)
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.85))
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
                                .textContentType(.oneTimeCode)   // iOS autofills from the email
                                .keyboardType(.numberPad)
                                .font(.system(size: 22, weight: .semibold, design: .rounded))
                                .tracking(6)
                        }
                    }

                    if let errorMessage {
                        label(errorMessage, icon: "exclamationmark.circle.fill", color: WarmPalette.bad)
                    }
                    if let resendNote {
                        label(resendNote, icon: "checkmark.circle.fill", color: .white)
                    }

                    Button { primaryAction() } label: {
                        Group {
                            if isWorking { ProgressView().tint(.white) }
                            else { Text(mode == .email ? "Send code" : "Verify").fontWeight(.semibold) }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AccentTheme.sage.color, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .disabled(!canSubmit)
                    .opacity(canSubmit ? 1 : 0.6)
                    .padding(.top, 4)

                    if mode == .code {
                        Button { resend() } label: {
                            Text("Resend code").font(.system(size: 14)).foregroundStyle(.white.opacity(0.85))
                        }
                        .disabled(isWorking)
                    }

                    Button { dismiss() } label: {
                        Text("Back").font(.system(size: 14)).foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 28)
            }
        }
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

    private func configureFromStep() {
        switch initialStep {
        case .needsEmailEnrollment(let ch):
            challenge = ch; mode = .email
        case .needsCode(let ch, let hint):
            challenge = ch; emailHint = hint; mode = .code
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
                    if case let .needsCode(_, hint) = step { emailHint = hint; mode = .code; code = "" }
                } else {
                    try await auth.verifyLoginCode(challenge: challenge, code: code.trimmingCharacters(in: .whitespaces))
                    // Success → AuthService.isAuthenticated flips; root view replaces us.
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
                try await auth.resendLoginCode(challenge: challenge)
                resendNote = "A new code is on its way."
            } catch {
                errorMessage = "Couldn't resend the code."
            }
            isWorking = false
        }
    }

    @ViewBuilder private func field<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .foregroundStyle(.white)
            .tint(.white)
            .font(.system(size: 18))
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.2), lineWidth: 0.5))
            .multilineTextAlignment(.center)
    }

    private func label(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 13))
            Text(text).font(.system(size: 13))
        }
        .foregroundStyle(color)
    }
}
