import SwiftUI

struct SignUpView: View {
    @Environment(AuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var username = ""
    @State private var password = ""
    @State private var inviteCode = ""
    @State private var householdName = ""
    @State private var hasInviteCode = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    VStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 48))
                            .foregroundStyle(AccentTheme.sage.color)
                            .padding(.bottom, 8)
                        Text("Create Account")
                            .font(.flScreenTitle)
                            .foregroundStyle(WarmPalette.ink1)
                        Text("Set up your family hub")
                            .font(.flSubheadline)
                            .foregroundStyle(WarmPalette.ink3)
                    }
                    .padding(.top, 30)
                    .padding(.bottom, 32)

                    VStack(spacing: 14) {
                        formField(icon: "person.fill", placeholder: "Your name", text: $name)
                            .textContentType(.name)
                        formField(icon: "at", placeholder: "Username", text: $username)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        formField(icon: "lock.fill", placeholder: "Password", text: $password, isSecure: true)
                            .textContentType(.newPassword)

                        // Invite code toggle
                        Button {
                            withAnimation { hasInviteCode.toggle() }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: hasInviteCode ? "checkmark.circle.fill" : "envelope.badge")
                                    .foregroundStyle(hasInviteCode ? AccentTheme.sage.color : WarmPalette.ink3)
                                Text("I have an invite code")
                                    .font(.flSubheadline.weight(.medium))
                                    .foregroundStyle(WarmPalette.ink2)
                                Spacer()
                            }
                            .padding(14)
                            .flGlassSurface(tint: .white.opacity(0.03), strokeOpacity: 0.08, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small))
                        }

                        if hasInviteCode {
                            formField(icon: "ticket.fill", placeholder: "Invite code", text: $inviteCode)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .transition(.move(edge: .top).combined(with: .opacity))
                        } else {
                            formField(icon: "house.fill", placeholder: "Household name (e.g. The Smiths)", text: $householdName)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        if let errorMessage {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.system(size: 13))
                                Text(errorMessage)
                                    .font(.flFootnote)
                            }
                            .foregroundStyle(WarmPalette.bad)
                            .padding(.top, 2)
                        }

                        Button(action: signUp) {
                            if isLoading {
                                ProgressView()
                            } else {
                                Text(hasInviteCode ? "Join Household" : "Create Household")
                            }
                        }
                        .buttonStyle(.flCTA(fill: AccentTheme.sage.color))
                        .disabled(name.isEmpty || username.isEmpty || password.isEmpty || isLoading)
                        .opacity(name.isEmpty || username.isEmpty || password.isEmpty ? 0.5 : 1)
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 24)

                    if !hasInviteCode {
                        VStack(spacing: 6) {
                            Text("Name your household and invite your partner after signing up.")
                                .font(.flFootnote)
                                .foregroundStyle(WarmPalette.ink3)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 16)
                    }
                }
                .padding(.bottom, 40)
            }
            .background { AmbientBackground(style: .home) }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(WarmPalette.ink2)
                }
            }
        }
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

    private func signUp() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await authService.register(
                    username: username,
                    password: password,
                    name: name,
                    inviteCode: hasInviteCode ? inviteCode : nil,
                    householdName: !hasInviteCode && !householdName.isEmpty ? householdName : nil
                )
                dismiss()
            } catch APIError.serverError(409) {
                errorMessage = "Username already taken"
            } catch {
                errorMessage = "Could not create account"
            }
            isLoading = false
        }
    }
}

#Preview {
    SignUpView()
        .environment(AuthService())
}
