import SwiftUI

/// Lets the signed-in user change their password. The new-password fields use
/// `.newPassword` content type so iOS offers a strong password and saves it to
/// the Passwords app (Face ID autofill on next sign-in).
struct ChangePasswordView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var current = ""
    @State private var newPassword = ""
    @State private var confirm = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didSucceed = false

    private var canSave: Bool {
        !current.isEmpty && newPassword.count >= 8 && newPassword == confirm && !isSaving
    }

    var body: some View {
        Form {
            Section {
                SecureField("Current password", text: $current)
                    .textContentType(.password)
            } header: {
                Text("Current")
            }

            Section {
                SecureField("New password", text: $newPassword)
                    .textContentType(.newPassword)
                SecureField("Confirm new password", text: $confirm)
                    .textContentType(.newPassword)
            } header: {
                Text("New password")
            } footer: {
                Text("At least 8 characters. Choose \"Use Strong Password\" to save it to your iPhone for Face ID sign-in.")
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(WarmPalette.bad)
                        .font(.flSubheadline)
                }
            }

            if didSucceed {
                Section {
                    Label("Password updated", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(AccentTheme.sage.color)
                }
            }

            Section {
                Button {
                    save()
                } label: {
                    HStack {
                        Spacer()
                        if isSaving { ProgressView() } else { Text("Update Password").fontWeight(.semibold) }
                        Spacer()
                    }
                }
                .disabled(!canSave)
            }
        }
        .scrollContentBackground(.hidden)
        .background { AmbientBackground(style: .settings) }
        .navigationTitle("Change Password")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() {
        guard newPassword == confirm else { errorMessage = "New passwords don't match"; return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await auth.changePassword(current: current, new: newPassword)
                didSucceed = true
                current = ""; newPassword = ""; confirm = ""
                try? await Task.sleep(for: .seconds(1))
                dismiss()
            } catch {
                errorMessage = "Couldn't update password. Check your current password and try again."
            }
            isSaving = false
        }
    }
}

#Preview {
    NavigationStack {
        ChangePasswordView()
            .environment(AuthService())
    }
}
