import SwiftUI

struct HomeView: View {
    @Binding var selectedTab: MainTab
    @Environment(APIService.self) private var api
    @Environment(AuthService.self) private var auth
    @State private var viewModel = HomeViewModel()
    @State private var showingAddTask = false
    @State private var showingNewDecision = false
    @State private var showingNewEvent = false
    @State private var showingNewPost = false
    @State private var showingSettings = false
    @State private var presenceMembers: [APIService.PresenceMember] = []
    @State private var feedFilterGroupId: Int? = nil // nil = All
    @State private var selectedFeedEvent: AppointmentResponse?
    @State private var selectedFeedRivalry: RivalryResponse?

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 17 { return "Good afternoon" }
        return "Good evening"
    }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE '\u{00B7}' MMMM d"
        return f
    }()

    private var dateString: String {
        Self.dateFmt.string(from: Date())
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showingSettings = true } label: {
                    ProfileAvatar(size: 40)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 14) {
                    Button {
                        Task {
                            await viewModel.loadAll(api: api, userName: auth.currentUser?.name, username: auth.currentUser?.username)
                            checkFeedNotifications()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(WarmPalette.ink2)
                    }
                    Menu {
                        Button { showingNewPost = true } label: {
                            Label("New Post", systemImage: "text.bubble")
                        }
                        Button { showingNewDecision = true } label: {
                            Label("New Decision", systemImage: "chart.bar.fill")
                        }
                        Button { showingAddTask = true } label: {
                            Label("New Task", systemImage: "checkmark.circle")
                        }
                        Button { showingNewEvent = true } label: {
                            Label("New Event", systemImage: "calendar.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(WarmPalette.ink2)
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddTask) {
            AddTaskView { task in Task { await viewModel.addTask(task, api: api) } }
        }
        .sheet(isPresented: $showingNewDecision) {
            NewDecisionView {
                await viewModel.loadAll(api: api)
            }
        }
        .sheet(isPresented: $showingNewEvent) {
            AddAppointmentView { data in
                Task {
                    try? await api.addAppointment(data)
                    await viewModel.loadAll(api: api)
                }
            }
        }
        .sheet(isPresented: $showingNewPost) {
            NewPostView {
                await viewModel.reloadFeed(api: api)
            }
        }
        .sheet(isPresented: $showingSettings) { NavigationStack { SettingsView(showsDismissButton: true) } }
        .sheet(item: $selectedFeedEvent) { appt in
            NavigationStack {
                EventDetailView(appointment: appt) {
                    await viewModel.loadAll(api: api)
                }
            }
        }
        .sheet(item: $selectedFeedRivalry) { rivalry in
            NavigationStack {
                RivalryDetailView(rivalry: rivalry)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") { selectedFeedRivalry = nil }
                                .foregroundStyle(WarmPalette.ink2)
                        }
                    }
            }
        }
        .overlay(alignment: .center) {
            if viewModel.isLoading && viewModel.summary == nil {
                ProgressView()
            }
        }
        .alert("Something went wrong", isPresented: errorAlertIsPresented) {
            Button("OK") {
                if viewModel.error == APIError.unauthorized.localizedDescription {
                    auth.logout()
                }
                viewModel.error = nil
            }
        } message: {
            Text(viewModel.error ?? "An unexpected error occurred.")
        }
        .task {
            await viewModel.loadAll(api: api, userName: auth.currentUser?.name, username: auth.currentUser?.username)
            presenceMembers = (try? await api.fetchHouseholdPresence()) ?? []
            checkFeedNotifications()
            await checkMessageNotifications()
        }
    }

    private func checkFeedNotifications() {
        let feed = viewModel.activityFeed
        guard !feed.isEmpty else { return }
        Task {
            guard await NotificationService.shared.isAuthorized() else { return }
            NotificationService.shared.checkForNewFeedItems(
                feed.map(\.item),
                currentUser: auth.currentUser?.name ?? ""
            )
        }
    }

    private func checkMessageNotifications() async {
        do {
            let convos = try await api.fetchConversations()
            guard await NotificationService.shared.isAuthorized() else { return }
            NotificationService.shared.checkForNewMessages(convos)
        } catch {}
    }

    private func openFeedEvent(id: Int) async {
        if let appt = viewModel.todayAppointments.first(where: { $0.id == id }) {
            selectedFeedEvent = appt
            return
        }
        // Fetch only upcoming week instead of ALL appointments
        let today = DateFormatter.isoDate.string(from: Date())
        let nextWeek = DateFormatter.isoDate.string(from: Date().addingTimeInterval(7 * 86400))
        do {
            let recent = try await api.fetchAppointments(dateFrom: today, dateTo: nextWeek)
            if let appt = recent.first(where: { $0.id == id }) {
                selectedFeedEvent = appt
            }
        } catch {}
    }

    private func openFeedRivalry(id: Int) async {
        do {
            let rivalries = try await api.fetchRivalries()
            if let rivalry = rivalries.first(where: { $0.id == id }) {
                selectedFeedRivalry = rivalry
            }
        } catch {}
    }

    private var errorAlertIsPresented: Binding<Bool> {
        Binding(get: { viewModel.error != nil }, set: { if !$0 { viewModel.error = nil } })
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Text(dateString)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WarmPalette.ink3)
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(currentLocationColor)
                    .frame(width: 8, height: 8)
                Text(currentLocationLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WarmPalette.ink2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(WarmPalette.cardSurface, in: Capsule())
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
                Text("\(auth.currentUser?.name ?? "there").")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(TabAccent.home.color)
            }
            familyStatusSubtitle
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 18)
    }

    private var currentLocationLabel: String {
        let me = presenceMembers.first { $0.id == auth.currentUser?.id }
        return me?.last_location_name ?? "Home"
    }

    private var currentLocationColor: Color {
        currentLocationLabel == "Home" ? TabAccent.home.color : AccentTheme.ocean.color
    }

    @ViewBuilder
    private var familyStatusSubtitle: some View {
        if let trip = viewModel.activeTrips.first {
            Text("\(trip.traveler.capitalized) is on the way home.")
                .font(.system(size: 15))
                .foregroundStyle(WarmPalette.ink2)
        } else {
            let othersAway = presenceMembers.filter { member in
                member.id != auth.currentUser?.id
                && member.last_location_name != nil
                && member.last_location_name != "Home"
                && member.last_location_name != "Fairbanks"
            }
            if let away = othersAway.first {
                Text("\(away.name) is at \(away.last_location_name ?? "away").")
                    .font(.system(size: 15))
                    .foregroundStyle(WarmPalette.ink2)
            } else {
                Text("Everyone's home. Quiet evening ahead.")
                    .font(.system(size: 15))
                    .foregroundStyle(WarmPalette.ink2)
            }
        }
    }

    // MARK: - Presence Row

    @ViewBuilder
    private var presenceRow: some View {
        if let trip = viewModel.activeTrips.first {
            let eta = max(0, trip.eta_minutes ?? 0)
            HStack {
                PresenceChip(
                    initial: String(trip.traveler.prefix(1)).uppercased(),
                    name: trip.traveler.capitalized,
                    status: eta <= 0 ? "Arriving now" : "On the way \u{00B7} \(eta) min",
                    statusColor: eta <= 0 ? WarmPalette.good : WarmPalette.warn,
                    showTrip: true
                )
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 16)
        }
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
                                .background(WarmPalette.ink1, in: Capsule())
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
                            .background(WarmPalette.cardSurface, in: Capsule())
                    }
                }
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 22)
            .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.cardLarge))
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            .padding(.bottom, 14)
        }
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        HStack(spacing: 8) {
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
                        WarmAgendaRow(
                            time: appt.appointment_time ?? "",
                            title: appt.title,
                            subtitle: appt.location ?? "",
                            tagInitial: appt.person_tags.flatMap { $0.first.map(String.init) }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { selectedFeedEvent = appt }
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
                .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            }
            .padding(.bottom, 14)
        }
    }

    // MARK: - Activity Feed

    /// Unique groups found in the feed for the filter dropdown
    private var feedGroups: [(id: Int, name: String)] {
        var seen = Set<Int>()
        var result: [(id: Int, name: String)] = []
        for item in viewModel.activityFeed {
            if let gid = item.item.group_id, let gname = item.item.group_name, !seen.contains(gid) {
                seen.insert(gid)
                result.append((id: gid, name: gname))
            }
        }
        return result.sorted { $0.name < $1.name }
    }

    private var filteredFeed: [PreparedFeedItem] {
        guard let filterId = feedFilterGroupId else { return viewModel.activityFeed }
        return viewModel.activityFeed.filter { $0.item.group_id == filterId || $0.item.group_id == nil }
    }

    @ViewBuilder
    private var activityFeedSection: some View {
        if !viewModel.activityFeed.isEmpty {
            // Feed header with group filter
            HStack {
                Text("Feed")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(WarmPalette.ink1)
                Spacer()
                Menu {
                    Button {
                        feedFilterGroupId = nil
                    } label: {
                        HStack {
                            Text("All")
                            if feedFilterGroupId == nil { Image(systemName: "checkmark") }
                        }
                    }
                    ForEach(feedGroups, id: \.id) { group in
                        Button {
                            feedFilterGroupId = group.id
                        } label: {
                            HStack {
                                Text(group.name)
                                if feedFilterGroupId == group.id { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(feedFilterGroupId.flatMap { fid in feedGroups.first { $0.id == fid }?.name } ?? "All")
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(TabAccent.home.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(WarmPalette.cardSurface, in: Capsule())
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            .padding(.bottom, 8)

            let visible = filteredFeed.prefix(viewModel.visibleFeedCount)
            ForEach(visible) { prepared in
                FeedCard(
                    prepared: prepared,
                    selectedTab: $selectedTab,
                    onEventTap: { eventId in Task { await openFeedEvent(id: eventId) } },
                    onRivalryTap: { rivalryId in Task { await openFeedRivalry(id: rivalryId) } },
                    onCoverageTap: { selectedTab = .calendar }
                )
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                .padding(.bottom, 10)
            }

            if filteredFeed.count > viewModel.visibleFeedCount {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        viewModel.visibleFeedCount += 15
                    }
                } label: {
                    Text("Show more")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(TabAccent.home.color)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                .padding(.bottom, 10)
            }
        }
    }
}

#Preview {
    NavigationStack {
        HomeView(selectedTab: .constant(.home))
    }
    .environment(APIService())
    .environment(AuthService())
    .environment(ProfileImageCache())
}
