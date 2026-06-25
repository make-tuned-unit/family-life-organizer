import SwiftUI

/// Account security: shows the 2FA email + verification status and lets the user
/// change/confirm the email a sign-in code is sent to.
struct SecurityView: View {
    @Environment(APIService.self) private var api

    @State private var status: APIService.SecurityStatus?
    @State private var loading = true

    // Change-email flow
    @State private var newEmail = ""
    @State private var challenge: String?
    @State private var code = ""
    @State private var emailHint: String?
    @State private var isWorking = false
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        Form {
            Section {
                if loading {
                    HStack { ProgressView(); Text("Loading…").foregroundStyle(WarmPalette.ink3) }
                } else if let status {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(status.two_factor_enabled ? "On" : "Setup needed")
                            .foregroundStyle(status.two_factor_enabled ? AccentTheme.sage.color : WarmPalette.bad)
                    }
                    HStack(spacing: 6) {
                        Text("Email")
                        Spacer()
                        Text(status.email ?? "—").foregroundStyle(WarmPalette.ink2)
                        if status.email_verified {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(AccentTheme.sage.color)
                        }
                    }
                }
            } header: {
                Text("Two-factor sign-in")
            } footer: {
                Text("A 6-digit code is emailed here each time you sign in.")
            }

            Section(challenge == nil ? "Change email" : "Enter the code") {
                if challenge == nil {
                    TextField("New email address", text: $newEmail)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Send verification code") { sendCode() }
                        .disabled(!newEmail.contains("@") || isWorking)
                } else {
                    Text("Code sent to \(emailHint ?? newEmail).")
                        .font(.system(size: 13)).foregroundStyle(WarmPalette.ink3)
                    TextField("123456", text: $code)
                        .textContentType(.oneTimeCode)
                        .keyboardType(.numberPad)
                    Button("Verify") { verify() }
                        .disabled(code.count < 6 || isWorking)
                    Button("Cancel", role: .cancel) { resetFlow() }
                }
            }

            if let message {
                Section {
                    Label(message, systemImage: isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(isError ? WarmPalette.bad : AccentTheme.sage.color)
                        .font(.system(size: 14))
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background { AmbientBackground(style: .settings) }
        .navigationTitle("Security")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        loading = true
        status = try? await api.fetchSecurityStatus()
        loading = false
    }

    private func sendCode() {
        isWorking = true; message = nil
        Task {
            do {
                let r = try await api.changeAccountEmail(newEmail.trimmingCharacters(in: .whitespaces))
                challenge = r.challenge; emailHint = r.email_hint; code = ""
            } catch {
                message = "Couldn't send the code. Check the address."; isError = true
            }
            isWorking = false
        }
    }

    private func verify() {
        guard let challenge else { return }
        isWorking = true; message = nil
        Task {
            do {
                try await api.verifyAccountEmail(challenge: challenge, code: code.trimmingCharacters(in: .whitespaces))
                message = "Email updated."; isError = false
                resetFlow()
                await load()
            } catch {
                message = "That code didn't work."; isError = true
            }
            isWorking = false
        }
    }

    private func resetFlow() {
        challenge = nil; code = ""; newEmail = ""; emailHint = nil
    }
}
