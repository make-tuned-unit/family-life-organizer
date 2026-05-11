import SwiftUI
import PhotosUI

struct SettingsView: View {
    var showsDismissButton = false
    @Environment(AuthService.self) private var auth
    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss

    @State private var serverURL: String = ""
    @State private var showingLogoutConfirm = false
    @State private var notificationsEnabled = false
    @State private var locationEnabled = false
    @State private var showingHousehold = false
    @State private var showingPhotoPicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var profileImage: Image?

    var body: some View {
        Form {
            // Profile section
            Section {
                HStack(spacing: 14) {
                    // Profile picture
                    Button { showingPhotoPicker = true } label: {
                        if let profileImage {
                            profileImage
                                .resizable()
                                .scaledToFill()
                                .frame(width: 56, height: 56)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 1))
                        } else {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [WarmPalette.peach, AccentTheme.terracotta.color],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 56, height: 56)
                                Text(String(auth.currentUser?.name.prefix(1) ?? "?"))
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white)
                                    .frame(width: 20, height: 20)
                                    .background(WarmPalette.ink1)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(.white, lineWidth: 1.5))
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    if let user = auth.currentUser {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.name)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(WarmPalette.ink1)
                            Text(user.username)
                                .font(.system(size: 13))
                                .foregroundStyle(WarmPalette.ink3)
                        }
                    }

                    Spacer()
                }
                .padding(.vertical, 4)
            }

            Section("Notifications") {
                HStack {
                    Image(systemName: "bell.fill")
                        .foregroundStyle(AccentTheme.saffron.color)
                    Text("Notifications")
                    Spacer()
                    Text(notificationsEnabled ? "Enabled" : "Disabled")
                        .foregroundStyle(WarmPalette.ink3)
                }

                if notificationsEnabled {
                    Label("Appointment reminders", systemImage: "calendar.badge.clock")
                        .font(.subheadline)
                        .foregroundStyle(WarmPalette.ink2)
                    Label("Expiry alerts", systemImage: "clock.badge.exclamationmark")
                        .font(.subheadline)
                        .foregroundStyle(WarmPalette.ink2)
                    Label("Trip updates", systemImage: "car.fill")
                        .font(.subheadline)
                        .foregroundStyle(WarmPalette.ink2)
                } else {
                    Button {
                        Task { notificationsEnabled = await NotificationService.shared.requestPermission() }
                    } label: {
                        Label("Enable Notifications", systemImage: "bell.badge")
                            .foregroundStyle(TabAccent.home.color)
                    }
                }
            }

            Section("Location") {
                HStack {
                    Image(systemName: "location.fill")
                        .foregroundStyle(AccentTheme.ocean.color)
                    Text("Location Access")
                    Spacer()
                    Text(locationEnabled ? "Enabled" : "Disabled")
                        .foregroundStyle(WarmPalette.ink3)
                }
                Text("Used for trip tracking and ETA calculation.")
                    .font(.caption)
                    .foregroundStyle(WarmPalette.ink3)
            }

            Section("Server") {
                TextField("Server URL", text: $serverURL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onAppear { serverURL = api.baseURL }

                Button {
                    api.baseURL = serverURL
                    UserDefaults.standard.set(serverURL, forKey: "server_url")
                } label: {
                    Text("Update Server URL")
                        .foregroundStyle(TabAccent.home.color)
                }
                .disabled(serverURL == api.baseURL)
            }

            Section("Household") {
                NavigationLink { HouseholdView() } label: {
                    Label("My Household", systemImage: "house.fill")
                        .foregroundStyle(TabAccent.home.color)
                }
            }

            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(AppConfig.appVersion)
                        .foregroundStyle(WarmPalette.ink3)
                }
            }

            Section {
                Button(role: .destructive) {
                    showingLogoutConfirm = true
                } label: {
                    HStack {
                        Spacer()
                        Text("Sign Out")
                        Spacer()
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background { AmbientBackground(style: .settings) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .toolbar {
            if showsDismissButton {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(WarmPalette.ink2)
                }
            }
        }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedPhoto, matching: .images)
        .onChange(of: selectedPhoto) {
            Task {
                if let data = try? await selectedPhoto?.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    profileImage = Image(uiImage: uiImage)
                    auth.setProfileImage(data)
                }
            }
        }
        .onAppear {
            if let data = auth.profileImageData,
               let uiImage = UIImage(data: data) {
                profileImage = Image(uiImage: uiImage)
            }
        }
        .confirmationDialog("Sign out?", isPresented: $showingLogoutConfirm) {
            Button("Sign Out", role: .destructive) {
                auth.logout()
                dismiss()
            }
        }
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationsEnabled = settings.authorizationStatus == .authorized
            let locService = LocationService()
            locationEnabled = locService.authorizationStatus == .authorizedWhenInUse || locService.authorizationStatus == .authorizedAlways
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(AuthService())
    .environment(APIService())
    .environment(HouseholdService())
}
