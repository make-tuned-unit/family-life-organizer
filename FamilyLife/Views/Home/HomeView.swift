import SwiftUI

struct HomeView: View {
    @Binding var selectedTab: MainTab
    @Environment(APIService.self) private var api
    @Environment(AuthService.self) private var auth
    @State private var viewModel = HomeViewModel()
    @State private var showingAddTask = false
    @State private var showingSettings = false
    @State private var todaySteps: Int?
    @State private var activityFeed: [APIService.ActivityItem] = []
    @State private var activeTrips: [TripResponse] = []
    @State private var healthKit = HealthKitManager()

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 17 { return "Good afternoon" }
        return "Good evening"
    }

    private var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE '\u{00B7}' MMMM d"
        return f.string(from: Date())
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                headerSection
                greetingSection
                presenceRow
                heroFocusCard
                statsGrid
                upNextSection
                activityFeedSection
            }
            .padding(.bottom, DesignTokens.Spacing.bottomBuffer)
        }
        .background { AmbientBackground(style: .home) }
        .refreshable { await viewModel.loadAll(api: api) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showingSettings = true } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(WarmPalette.ink2)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAddTask = true } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(WarmPalette.ink2)
                }
            }
        }
        .sheet(isPresented: $showingAddTask) {
            AddTaskView { task in Task { await viewModel.addTask(task, api: api) } }
        }
        .sheet(isPresented: $showingSettings) { NavigationStack { SettingsView(showsDismissButton: true) } }
        // Rivalries and Gifts accessed via More tab
        .overlay {
            if viewModel.isLoading && viewModel.summary == nil { ProgressView() }
        }
        .alert("Something went wrong", isPresented: errorAlertIsPresented) {
            Button("OK") { viewModel.error = nil }
        } message: {
            Text(viewModel.error ?? "An unexpected error occurred.")
        }
        .task {
            await viewModel.loadAll(api: api)
            await loadLiveData()
        }
    }

    private func loadLiveData() async {
        if healthKit.isAvailable {
            if await healthKit.requestStepAuthorization() {
                let start = Calendar.current.startOfDay(for: Date())
                let steps = await healthKit.fetchSteps(from: start, to: Date())
                todaySteps = Int(steps)
            }
        }
        do { activeTrips = try await api.fetchTrips(status: "active") } catch {}
        do { activityFeed = try await api.fetchActivity() } catch {}
    }

    private var errorAlertIsPresented: Binding<Bool> {
        Binding(get: { viewModel.error != nil }, set: { if !$0 { viewModel.error = nil } })
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Text(dateString)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WarmPalette.ink2)
                .opacity(0.7)
                .tracking(0.4)
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(TabAccent.home.color)
                    .frame(width: 8, height: 8)
                Text("Home")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WarmPalette.ink2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    // MARK: - Greeting

    private var greetingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(greeting),")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(WarmPalette.ink1)
                    .tracking(-0.68)
                Text("\(auth.currentUser?.name ?? "there").")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(TabAccent.home.color)
                    .tracking(-0.68)
            }
            familyStatusSubtitle
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private var familyStatusSubtitle: some View {
        if let trip = activeTrips.first {
            Text("\(trip.traveler.capitalized) is on the way home.")
                .font(.system(size: 15))
                .foregroundStyle(WarmPalette.ink2)
        } else {
            Text("Everyone's home. Quiet evening ahead.")
                .font(.system(size: 15))
                .foregroundStyle(WarmPalette.ink2)
        }
    }

    // MARK: - Presence Row

    private var presenceRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if let trip = activeTrips.first {
                    PresenceChip(
                        initial: String(trip.traveler.prefix(1)).uppercased(),
                        name: trip.traveler.capitalized,
                        status: "On the way \u{00B7} \(trip.eta_minutes ?? 0) min",
                        statusColor: WarmPalette.warn,
                        showTrip: true
                    )
                }
                // Additional family members would be populated from API
            }
            .padding(.horizontal, 22)
        }
        .padding(.bottom, 16)
    }

    // MARK: - Hero Focus Card

    @ViewBuilder
    private var heroFocusCard: some View {
        if let appt = viewModel.todayAppointments.first {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("TODAY'S FOCUS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(TabAccent.home.color)
                        .tracking(0.4)
                    Spacer()
                    if let time = appt.appointment_time {
                        Text(time)
                            .font(.system(size: 13))
                            .foregroundStyle(WarmPalette.ink3)
                    }
                }

                Text(appt.title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(WarmPalette.ink1)
                    .tracking(-0.56)

                if let location = appt.location, !location.isEmpty {
                    Text(location)
                        .font(.system(size: 15))
                        .foregroundStyle(WarmPalette.ink2)
                        .padding(.bottom, 2)
                }

                HStack(spacing: 8) {
                    if let location = appt.location, !location.isEmpty {
                        Button {
                            let query = location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? location
                            if let url = URL(string: "maps://?q=\(query)") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Text("Get directions")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(WarmPalette.cream1)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(WarmPalette.ink1)
                                .clipShape(Capsule())
                        }
                    }
                    Button {
                        viewModel.dismissHeroCard()
                    } label: {
                        Text("Done")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(WarmPalette.ink1)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 22)
            .glassEffect(.regular.tint(TabAccent.home.color.opacity(0.04)), in: .rect(cornerRadius: DesignTokens.CornerRadius.cardLarge))
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            .padding(.bottom, 14)
        }
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            WarmStatTile(label: "Tasks", value: "\(viewModel.summary?.tasks_today ?? 0)", sub: "today")
            WarmStatTile(label: "Events", value: "\(viewModel.summary?.appointments_today ?? 0)", sub: "today")
            WarmStatTile(label: "Grocery", value: "\(viewModel.summary?.groceries_needed ?? 0)", sub: "needed")
            WarmStatTile(label: "Overdue", value: "\(viewModel.summary?.overdue_tasks ?? 0)", sub: "tasks")
        }
        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
        .padding(.bottom, 14)
    }

    // MARK: - Up Next

    @ViewBuilder
    private var upNextSection: some View {
        if !viewModel.todayAppointments.isEmpty || !viewModel.activeTasks.isEmpty {
            VStack(spacing: 6) {
                WarmSectionHeader(title: "Up next", trailing: "This evening")
                    .padding(.bottom, 6)

                VStack(spacing: 0) {
                    ForEach(Array(viewModel.todayAppointments.prefix(3).enumerated()), id: \.element.id) { index, appt in
                        if index > 0 { GlassDivider() }
                        NavigationLink {
                            EventDetailView(appointment: appt) {
                                await viewModel.loadAll(api: api)
                            }
                        } label: {
                            WarmAgendaRow(
                                time: appt.appointment_time ?? "",
                                title: appt.title,
                                subtitle: appt.location ?? "",
                                tagInitial: appt.person_tags.flatMap { $0.first.map(String.init) }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    if viewModel.todayAppointments.count < 3 {
                        ForEach(Array(viewModel.activeTasks.prefix(3 - viewModel.todayAppointments.count).enumerated()), id: \.element.id) { _, task in
                            GlassDivider()
                            WarmAgendaRow(
                                time: "",
                                title: task.title,
                                subtitle: task.category,
                                isAuto: true
                            )
                        }
                    }
                }
                .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: DesignTokens.CornerRadius.card))
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            }
            .padding(.bottom, 14)
        }
    }

    // MARK: - Activity Feed

    @ViewBuilder
    private var activityFeedSection: some View {
        if !activityFeed.isEmpty {
            WarmSectionHeader(title: "Feed")
                .padding(.bottom, 8)

            VStack(spacing: 8) {
                ForEach(activityFeed.prefix(10)) { item in
                    ActivityFeedCard(item: item, selectedTab: $selectedTab)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            .padding(.bottom, 18)
        }
    }
}

// MARK: - Row Components

struct TaskRow: View {
    let task: TaskResponse
    let onComplete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onComplete) {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(TabAccent.home.color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.subheadline.weight(.medium))
                if let assigned = task.assigned_to, !assigned.isEmpty {
                    Text(assigned.capitalized)
                        .font(.caption)
                        .foregroundStyle(WarmPalette.ink3)
                }
            }
            Spacer()
            if task.priority == "high" {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(WarmPalette.warn)
            }
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .flCard(tint: TabAccent.home.color)
    }
}

struct AppointmentRow: View {
    let appointment: AppointmentResponse

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(TabAccent.calendar.color)
                .frame(width: 4, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(appointment.title)
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 6) {
                    if let time = appointment.appointment_time {
                        Label(time, systemImage: "clock")
                    }
                    if let location = appointment.location {
                        Label(location, systemImage: "mappin")
                    }
                }
                .font(.caption)
                .foregroundStyle(WarmPalette.ink3)
            }
            Spacer()
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .flCard(tint: TabAccent.calendar.color)
    }
}

struct GroceryRow: View {
    let grocery: GroceryResponse
    let onComplete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onComplete) {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(WarmPalette.good)
            }
            Text(grocery.item)
                .font(.subheadline)
            Spacer()
            if let category = grocery.category {
                Text(category)
                    .font(.caption2)
                    .padding(.horizontal, DesignTokens.Spacing.chipPadding)
                    .padding(.vertical, DesignTokens.Spacing.tinyLabel)
                    .glassEffect(.regular, in: .capsule)
            }
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .flCard(tint: WarmPalette.good)
    }
}

// MARK: - Activity Feed Card

struct ActivityFeedCard: View {
    let item: APIService.ActivityItem
    @Binding var selectedTab: MainTab

    var body: some View {
        Button { navigate() } label: {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(accentColor)
                    .frame(width: 32, height: 32)
                    .background(accentColor.opacity(0.15))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(headline)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WarmPalette.ink1)
                        .lineLimit(1)
                    if let sub = subtitle {
                        Text(sub)
                            .font(.system(size: 12))
                            .foregroundStyle(WarmPalette.ink3)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Text(typeBadge)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .glassEffect(.regular.tint(accentColor.opacity(0.08)), in: .capsule)
            }
            .padding(12)
            .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var headline: String {
        switch item.feed_type {
        case "decision":
            return "\(item.author ?? "Someone") posted: \(item.title ?? "a decision")"
        case "event":
            return item.title ?? "Upcoming event"
        case "coverage":
            return "Coverage: \(item.title ?? "request")"
        case "post":
            return "\(item.author ?? "Someone"): \(item.title ?? item.body ?? "shared something")"
        default:
            return item.title ?? "Activity"
        }
    }

    private var subtitle: String? {
        switch item.feed_type {
        case "decision": return "Tap to vote or comment"
        case "event": return item.body // location
        case "coverage":
            return item.status == "approved" ? "Confirmed - book your time" : "Waiting for reply"
        case "post": return item.body
        default: return nil
        }
    }

    private var iconName: String {
        switch item.feed_type {
        case "decision": "bubble.left.and.bubble.right.fill"
        case "event": "calendar"
        case "coverage": "arrow.triangle.swap"
        case "post": "text.bubble.fill"
        default: "bell.fill"
        }
    }

    private var accentColor: Color {
        switch item.feed_type {
        case "decision": TabAccent.decisions.color
        case "event": TabAccent.calendar.color
        case "coverage": TabAccent.care.color
        case "post": AccentTheme.ocean.color
        default: WarmPalette.ink3
        }
    }

    private var typeBadge: String {
        switch item.feed_type {
        case "decision": "Decision"
        case "event": "Event"
        case "coverage": "Coverage"
        case "post": "Post"
        default: "Update"
        }
    }

    private func navigate() {
        switch item.feed_type {
        case "decision": selectedTab = .decisions
        case "event": selectedTab = .calendar
        default: break
        }
    }
}

#Preview {
    NavigationStack {
        HomeView(selectedTab: .constant(.home))
    }
    .environment(APIService())
    .environment(AuthService())
}
