import SwiftUI

struct SignUpView: View {
    enum Mode: Equatable {
        case create
        case join
    }

    var mode: Mode = .create
    var onCancel: (() -> Void)? = nil

    @Environment(AuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var username = ""
    @State private var password = ""
    @State private var email = ""
    @State private var inviteCode = ""
    @State private var householdName = ""
    @State private var showEmailForm = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                        .padding(.top, 30)
                        .padding(.bottom, 28)

                    VStack(spacing: 14) {
                        if mode == .create {
                            formField(icon: "house.fill", placeholder: "Household name (e.g. Our house)", text: $householdName)
                        } else {
                            inviteField
                        }

                        AppleSignInButton(
                            label: .signUp,
                            inviteCode: mode == .join ? inviteCode : nil,
                            householdName: mode == .create ? (householdName.isEmpty ? nil : householdName) : nil,
                            onError: { errorMessage = $0 }
                        )
                        .disabled(mode == .join && inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .opacity(mode == .join && inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                        .padding(.top, 4)

                        orDivider

                        if showEmailForm {
                            emailFields
                        } else {
                            Button { withAnimation { showEmailForm = true } } label: {
                                Text("or use email")
                                    .font(.flSubheadline.weight(.medium))
                                    .foregroundStyle(WarmPalette.ink2)
                            }
                        }
                    }
                    .padding(.horizontal, 24)

                    if mode == .create {
                        Text("Name your household and invite your partner after signing up.")
                            .font(.flFootnote)
                            .foregroundStyle(WarmPalette.ink3)
                            .multilineTextAlignment(.center)
                            .padding(.top, 16)
                            .padding(.horizontal, 24)
                    }

                    LegalConsentFooter()
                        .padding(.top, 20)
                }
                .padding(.bottom, 40)
            }
            .background { AmbientBackground(style: .home) }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cancel() }
                        .foregroundStyle(WarmPalette.ink2)
                }
            }
            .inlineError(errorMessage) { errorMessage = nil }
        }
        .preferredColorScheme(.light)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: mode == .join ? "person.badge.plus" : "house.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(AccentTheme.sage.color)
                .padding(.bottom, 4)
            Text(mode == .join ? "Join a household" : "Create your household")
                .font(.flScreenTitle)
                .foregroundStyle(WarmPalette.ink1)
            Text(mode == .join
                 ? "Enter the code your partner shared."
                 : "So the house can share this — not just this phone.")
                .font(.flSubheadline)
                .foregroundStyle(WarmPalette.ink2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
    }

    private var inviteField: some View {
        HStack(spacing: 12) {
            Image(systemName: "ticket.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WarmPalette.ink3)
                .frame(width: 20)
            TextField("Invite code", text: $inviteCode)
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .textContentType(.oneTimeCode)
        }
        .padding(16)
        .flGlassSurface(tint: .white.opacity(0.03), strokeOpacity: 0.08, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small))
    }

    private var orDivider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(WarmPalette.ink4.opacity(0.4)).frame(height: 1)
            Text("or")
                .font(.flCaption)
                .foregroundStyle(WarmPalette.ink3)
            Rectangle().fill(WarmPalette.ink4.opacity(0.4)).frame(height: 1)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var emailFields: some View {
        formField(icon: "person.fill", placeholder: "Your name", text: $name)
            .textContentType(.name)
        formField(icon: "at", placeholder: "Username", text: $username)
            .textContentType(.username)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        VStack(alignment: .leading, spacing: 6) {
            formField(icon: "lock.fill", placeholder: "Password", text: $password, isSecure: true)
                .textContentType(.newPassword)
            Text("At least 8 characters.")
                .font(.flCaption)
                .foregroundStyle(WarmPalette.ink3)
        }
        formField(icon: "envelope.fill", placeholder: "Email (optional)", text: $email)
            .textContentType(.emailAddress)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

        Button(action: signUp) {
            if isLoading {
                ProgressView()
            } else {
                Text(mode == .join ? "Join household" : "Create household")
            }
        }
        .buttonStyle(.flCTA(fill: AccentTheme.sage.color))
        .disabled(!canSubmitEmail || isLoading)
        .opacity(canSubmitEmail ? 1 : 0.5)
        .padding(.top, 8)
    }

    private var canSubmitEmail: Bool {
        if name.isEmpty || username.isEmpty || password.count < 8 { return false }
        if mode == .join && inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        return true
    }

    private func formField(icon: String, placeholder: String, text: Binding<String>, isSecure: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(WarmPalette.ink3)
                .frame(width: 20)
            if isSecure {
                SecureField(placeholder, text: text)
                    .font(.flBody)
            } else {
                TextField(placeholder, text: text)
                    .font(.flBody)
            }
        }
        .padding(16)
        .flGlassSurface(tint: .white.opacity(0.03), strokeOpacity: 0.08, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small))
    }

    private func cancel() {
        if let onCancel {
            onCancel()
        } else {
            dismiss()
        }
    }

    private func signUp() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedEmail.isEmpty, !trimmedEmail.contains("@") || !trimmedEmail.contains(".") {
            errorMessage = "That email doesn't look right"
            return
        }
        if password.count < 8 {
            errorMessage = "Password must be at least 8 characters"
            return
        }
        if mode == .join, inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "Enter the invite code your partner shared"
            return
        }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await authService.register(
                    username: username,
                    password: password,
                    name: name,
                    email: trimmedEmail.isEmpty ? nil : trimmedEmail,
                    inviteCode: mode == .join ? inviteCode : nil,
                    householdName: mode == .create && !householdName.isEmpty ? householdName : nil
                )
                dismiss()
            } catch APIError.serverMessage(_, let message) {
                errorMessage = message
            } catch APIError.serverError(409) {
                errorMessage = "Username already taken"
            } catch {
                errorMessage = "Could not create account"
            }
            isLoading = false
        }
    }
}

#Preview("Create") {
    SignUpView(mode: .create)
        .environment(AuthService())
}

#Preview("Join") {
    SignUpView(mode: .join)
        .environment(AuthService())
}
