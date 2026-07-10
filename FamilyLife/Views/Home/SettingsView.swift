import SwiftUI
import PhotosUI

struct SettingsView: View {
    var showsDismissButton = false
    @Environment(AuthService.self) private var auth
    @Environment(APIService.self) private var api
    @Environment(HouseholdService.self) private var household
    @Environment(LocationService.self) private var locationService
    @Environment(CalendarService.self) private var calendarService
    @Environment(ProfileImageCache.self) private var profileCache
    @Environment(\.dismiss) private var dismiss

    @State private var showingLogoutConfirm = false
    @State private var notificationsEnabled = false
    @State private var locationEnabled = false
    @State private var showingHousehold = false
    @State private var showingPhotoPicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var profileImage: Image?
    @State private var copiedCode = false
    @State private var showingNameEdit = false
    @State private var editingName = ""
    @State private var nameError: String?
    @AppStorage("cloudAIEnabled") private var cloudAIEnabled = true
    @AppStorage(AppleCalendarSyncMode.storageKey) private var calendarSyncMode: AppleCalendarSyncMode = .off

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
                        Button {
                            editingName = user.name
                            nameError = nil
                            showingNameEdit = true
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(user.name)
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(WarmPalette.ink1)
                                    Image(systemName: "pencil")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(WarmPalette.ink3)
                                }
                                Text(user.username)
                                    .font(.system(size: 13))
                                    .foregroundStyle(WarmPalette.ink3)
                            }
                        }
                        .buttonStyle(.plain)
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

            Section("Household") {
                NavigationLink { HouseholdView() } label: {
                    Label("My Household", systemImage: "house.fill")
                        .foregroundStyle(TabAccent.home.color)
                }

                if let code = household.householdGroup?.invite_code {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Invite Code")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(WarmPalette.ink3)
                        HStack {
                            Text(code)
                                .font(.system(size: 22, weight: .bold, design: .monospaced))
                                .foregroundStyle(WarmPalette.ink1)
                                .tracking(2)
                            Spacer()
                            Button {
                                UIPasteboard.general.string = code
                                copiedCode = true
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                Task {
                                    try? await Task.sleep(for: .seconds(2))
                                    copiedCode = false
                                }
                            } label: {
                                Image(systemName: copiedCode ? "checkmark.circle.fill" : "doc.on.doc")
                                    .font(.system(size: 16))
                                    .foregroundStyle(copiedCode ? WarmPalette.good : WarmPalette.ink3)
                            }
                        }
                    }
                    .padding(.vertical, 2)

                    ShareLink(
                        item: "Join my household on Kinrows! Use invite code: \(code)",
                        subject: Text("Join my household"),
                        message: Text("I set up our family organizer. Use this code to join: \(code)")
                    ) {
                        Label("Send invite to partner", systemImage: "message.fill")
                            .foregroundStyle(TabAccent.home.color)
                    }
                }
            }

            Section("Groups & Circles") {
                NavigationLink { FamilyGroupsView() } label: {
                    Label("Family Groups", systemImage: "person.3.fill")
                        .foregroundStyle(TabAccent.home.color)
                }
            }

            Section("Account") {
                NavigationLink { ChangePasswordView() } label: {
                    Label("Change Password", systemImage: "lock.fill")
                        .foregroundStyle(TabAccent.home.color)
                }
                NavigationLink { SecurityView() } label: {
                    Label("Security & 2FA", systemImage: "lock.shield.fill")
                        .foregroundStyle(TabAccent.home.color)
                }
            }

            Section {
                Toggle(isOn: $cloudAIEnabled) {
                    Label("Use cloud AI", systemImage: "cloud")
                        .foregroundStyle(TabAccent.home.color)
                }
                .tint(AccentTheme.sage.color)
            } header: {
                Text("Privacy")
            } footer: {
                Text(cloudAIEnabled
                    ? "Your daily brief is summarized privately on-device when your iPhone supports it — nothing is sent. The concierge chat sends what it needs to Anthropic to answer and take actions; Anthropic doesn’t train on it."
                    : "Cloud AI is off. The brief stays fully on-device/offline and the concierge chat is disabled, so no household data is sent to Anthropic.")
            }

            Section {
                Picker(selection: $calendarSyncMode) {
                    ForEach(AppleCalendarSyncMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                } label: {
                    Label("Apple Calendar sync", systemImage: "calendar")
                        .foregroundStyle(TabAccent.calendar.color)
                }
                .tint(AccentTheme.sage.color)
            } header: {
                Text("Apple Calendar")
            } footer: {
                Text("Adds Kinrows events to your iPhone's default calendar — which also syncs to Google if that account is connected in iOS Settings. \"Ask each time\" lets you choose per event. Applies to events created on this device.")
            }

            Section {
                Toggle(isOn: Binding(
                    get: { calendarService.shareEnabled },
                    set: { on in
                        calendarService.shareEnabled = on
                        if on {
                            Task {
                                if calendarService.access != .granted { _ = await calendarService.requestAccess() }
                                await calendarService.syncToHousehold(api: api)
                            }
                        }
                    }
                )) {
                    Label("Share my calendar", systemImage: "person.2")
                        .foregroundStyle(TabAccent.calendar.color)
                }
                .tint(AccentTheme.sage.color)

                if calendarService.shareEnabled {
                    NavigationLink {
                        CalendarSharePicker()
                    } label: {
                        HStack {
                            Text("Calendars to share")
                            Spacer()
                            Text("\(calendarService.sharedCalendarIDs.count) selected")
                                .foregroundStyle(WarmPalette.ink3)
                        }
                    }
                }
            } header: {
                Text("Household calendar")
            } footer: {
                Text("Share your selected device calendars (including synced Google calendars) so your household can see your schedule at a glance. Pick which calendars below.")
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
        // Clearance for the floating tab bar + chat button, which overlay content
        // in MainTabView's ZStack — without it the Sign Out row can never scroll
        // above them. Sheets (showsDismissButton) have no tab bar underneath.
        .contentMargins(.bottom, showsDismissButton ? 0 : 100, for: .scrollContent)
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
                if let data = try? await selectedPhoto?.loadTransferable(type: Data.self) {
                    auth.setProfileImage(data)
                    if let thumb = auth.profileUIImage {
                        profileImage = Image(uiImage: thumb)
                        // Update the shared avatar cache too, so your new photo
                        // shows everywhere immediately (not after a restart).
                        if let userId = auth.currentUser?.id {
                            profileCache.setImage(thumb, for: userId)
                        }
                    }
                }
            }
        }
        .onAppear {
            if let thumb = auth.profileUIImage {
                profileImage = Image(uiImage: thumb)
            }
        }
        .confirmationDialog("Sign out?", isPresented: $showingLogoutConfirm) {
            Button("Sign Out", role: .destructive) {
                auth.logout()
                dismiss()
            }
        }
        .alert("Edit Name", isPresented: $showingNameEdit) {
            TextField("Your name", text: $editingName)
                .textInputAutocapitalization(.words)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let trimmed = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                Task {
                    do {
                        try await auth.updateName(trimmed)
                    } catch {
                        nameError = "Couldn't update your name. Try again."
                    }
                }
            }
        } message: {
            if let nameError {
                Text(nameError)
            } else {
                Text("This is how your name appears across the app.")
            }
        }
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationsEnabled = settings.authorizationStatus == .authorized
            locationEnabled = locationService.authorizationStatus == .authorizedWhenInUse || locationService.authorizationStatus == .authorizedAlways
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
    .environment(LocationService())
    .environment(CalendarService())
    .environment(ProfileImageCache())
}

// MARK: - Calendar Share Picker

private struct CalendarSharePicker: View {
    @Environment(CalendarService.self) private var calendarService
    @Environment(APIService.self) private var api
    @State private var calendars: [CalendarService.DeviceCalendar] = []

    var body: some View {
        List {
            Section {
                ForEach(calendars) { cal in
                    Button {
                        toggle(cal.id)
                    } label: {
                        HStack(spacing: 12) {
                            Circle().fill(cal.color).frame(width: 12, height: 12)
                            Text(cal.title)
                                .foregroundStyle(WarmPalette.ink1)
                            Spacer()
                            if calendarService.sharedCalendarIDs.contains(cal.id) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(AccentTheme.sage.color)
                            }
                        }
                    }
                }
            } footer: {
                Text("Tap to choose which calendars your household can see. Includes any Google or iCloud calendars synced to this iPhone.")
            }
        }
        .navigationTitle("Calendars to Share")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if calendarService.access != .granted { _ = await calendarService.requestAccess() }
            calendars = calendarService.availableCalendars()
        }
    }

    private func toggle(_ id: String) {
        if calendarService.sharedCalendarIDs.contains(id) {
            calendarService.sharedCalendarIDs.remove(id)
        } else {
            calendarService.sharedCalendarIDs.insert(id)
        }
        Task { await calendarService.syncToHousehold(api: api) }
    }
}
