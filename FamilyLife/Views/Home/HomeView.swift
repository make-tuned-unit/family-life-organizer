import SwiftUI

struct HomeView: View {
    @Binding var selectedTab: MainTab
    @Binding var pendingListName: String?
    @Environment(APIService.self) private var api
    @Environment(AuthService.self) private var auth
    @State private var viewModel = HomeViewModel()
    @State private var showingAddTask = false
    @State private var showingNewDecision = false
    @State private var showingNewEvent = false
    @State private var showingNewPost = false
    @State private var showingSettings = false
    @State private var presenceMembers: [APIService.PresenceMember] = []
    @State private var eventRange = 0 // 0=today, 1=week, 2=month
    enum FeedFilter: Equatable {
        case all, forYou, group(Int)
    }
    @State private var feedFilter: FeedFilter = .all
    @State private var userGroups: [APIService.GroupResponse] = []
    @State private var showingFeedFilter = false
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
                greetingSection
                presenceRow
                statsGrid
                heroFocusCard
                upNextSection
                activityFeedSection
            }
            .padding(.bottom, DesignTokens.Spacing.bottomBuffer)
        }
        .refreshable {
            await viewModel.loadAll(api: api, userName: auth.currentUser?.name, username: auth.currentUser?.username)
            checkFeedNotifications()
        }
        .background { AmbientBackground(style: .home) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showingSettings = true } label: {
                    ProfileAvatar(size: 36)
                }
            }
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(dateString)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WarmPalette.ink3)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(currentLocationColor)
                            .frame(width: 6, height: 6)
                        Text(currentLocationLabel)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(WarmPalette.ink2)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
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
            userGroups = (try? await api.fetchGroups()) ?? []
            presenceMembers = (try? await api.fetchHouseholdPresence()) ?? []
            checkFeedNotifications()
            await checkMessageNotifications()
        }
        .onChange(of: selectedTab) {
            if selectedTab == .home {
                Task {
                    await viewModel.loadAll(api: api, userName: auth.currentUser?.name, username: auth.currentUser?.username)
                }
            }
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

    // MARK: - Greeting

    private var firstName: String {
        let name = auth.currentUser?.name ?? "there"
        return name.components(separatedBy: " ").first ?? name
    }

    private var greetingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(greeting), \(firstName).")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(WarmPalette.ink1)
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

    private var familyStatusSubtitle: some View {
        Text(familyStatusText)
            .font(.system(size: 15))
            .foregroundStyle(WarmPalette.ink2)
    }

    private var familyStatusText: String {
        if let trip = viewModel.activeTrips.first {
            return "\(trip.traveler.capitalized) is on the way home."
        }

        let othersAway = presenceMembers.filter { member in
            member.id != auth.currentUser?.id
            && member.last_location_name != nil
            && member.last_location_name != "Home"
            && member.last_location_name != "Fairbanks"
        }

        if othersAway.count > 1 {
            let names = ListFormatter.localizedString(byJoining: othersAway.map(\.name))
            return "\(names) are out."
        } else if let away = othersAway.first {
            return "\(away.name) is at \(away.last_location_name ?? "away")."
        }

        // Everyone's home — reflect time + what's actually on the schedule
        let hour = Calendar.current.component(.hour, from: Date())
        let events = viewModel.todayAppointments.count
        let tasks = viewModel.summary?.tasks_today ?? 0

        if events > 0 {
            let when = hour < 12 ? "today" : hour < 17 ? "this afternoon" : "tonight"
            return "\(events) event\(events == 1 ? "" : "s") \(when)."
        }

        if tasks > 0 {
            return "\(tasks) task\(tasks == 1 ? "" : "s") on the list."
        }

        let quiet = hour < 12 ? "Easy morning ahead." : hour < 17 ? "Quiet afternoon." : "Quiet night ahead."
        return "Everyone's home. \(quiet)"
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
            heroCard(appt, label: "TODAY'S FOCUS", subtitle: appt.appointment_time, showDismiss: true)
        } else if let appt = viewModel.nextAppointment {
            heroCard(appt, label: "NEXT EVENT", subtitle: Self.friendlyDate(appt.appointment_date, time: appt.appointment_time), showDismiss: false)
        }
    }

    private func heroCard(_ appt: AppointmentResponse, label: String, subtitle: String?, showDismiss: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(TabAccent.home.color)
                Spacer()
                if let subtitle {
                    Text(subtitle)
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
                if showDismiss {
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
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 22)
        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.cardLarge))
        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
        .padding(.bottom, 14)
        .contentShape(Rectangle())
        .onTapGesture { selectedTab = .calendar }
    }

    private static let friendlyDateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()

    private static func friendlyDate(_ dateStr: String, time: String?) -> String {
        guard let date = DateFormatter.isoDate.date(from: dateStr) else { return dateStr }
        let day = friendlyDateFmt.string(from: date)
        if let time, !time.isEmpty { return "\(day) · \(time)" }
        return day
    }

    // MARK: - Stats Grid

    private var eventCount: Int {
        switch eventRange {
        case 1: viewModel.weekEventCount
        case 2: viewModel.monthEventCount
        default: viewModel.summary?.appointments_today ?? 0
        }
    }

    private var eventSub: String {
        switch eventRange {
        case 1: "this week"
        case 2: "this month"
        default: "today"
        }
    }

    private var statsGrid: some View {
        HStack(spacing: 8) {
            WarmStatTile(label: "Tasks", value: "\(viewModel.summary?.tasks_today ?? 0)", sub: "today")
                .onTapGesture { pendingListName = "Tasks"; selectedTab = .lists }
            WarmStatTile(label: "Events", value: "\(eventCount)", sub: eventSub)
                .onTapGesture { withAnimation { eventRange = (eventRange + 1) % 3 } }
            WarmStatTile(label: viewModel.summary?.pinned_list_name ?? "List", value: "\(viewModel.summary?.groceries_needed ?? 0)", sub: "items")
                .onTapGesture { pendingListName = viewModel.summary?.pinned_list_name; selectedTab = .lists }
            WarmStatTile(label: "Overdue", value: "\(viewModel.summary?.overdue_tasks ?? 0)", sub: "tasks")
                .onTapGesture { pendingListName = "Tasks"; selectedTab = .lists }
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

    private var feedFilterLabel: String {
        switch feedFilter {
        case .all: "All"
        case .forYou: "For You"
        case .group(let id): userGroups.first { $0.id == id }?.name ?? "Group"
        }
    }

    /// All groups the user belongs to (for feed filter dropdown)
    private var feedGroups: [(id: Int, name: String)] {
        userGroups.map { (id: $0.id, name: $0.name) }.sorted { $0.name < $1.name }
    }

    private var filteredFeed: [PreparedFeedItem] {
        let myName = auth.currentUser?.name ?? ""
        switch feedFilter {
        case .all:
            return viewModel.activityFeed
        case .forYou:
            return viewModel.activityFeed.filter { item in
                let author = item.item.author ?? ""
                let body = item.item.body ?? ""
                let title = item.item.title ?? ""
                let involvesMe = body.localizedCaseInsensitiveContains(myName)
                    || title.localizedCaseInsensitiveContains(myName)
                let isRivalry = item.item.feed_type == "rivalry"
                    && (title.localizedCaseInsensitiveContains(myName)
                        || author.localizedCaseInsensitiveCompare(myName) == .orderedSame)
                let isDirectedAtMe = item.item.feed_type == "decision"
                    && author.localizedCaseInsensitiveCompare(myName) != .orderedSame
                return involvesMe || isRivalry || isDirectedAtMe
            }
        case .group(let groupId):
            return viewModel.activityFeed.filter { $0.item.group_id == groupId }
        }
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
                Button { showingFeedFilter = true } label: {
                    HStack(spacing: 4) {
                        Text(feedFilterLabel)
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(TabAccent.home.color)
                }
                .confirmationDialog("Filter Feed", isPresented: $showingFeedFilter) {
                    Button("All") { feedFilter = .all }
                    Button("For You") { feedFilter = .forYou }
                    ForEach(feedGroups, id: \.id) { group in
                        Button(group.name) { feedFilter = .group(group.id) }
                    }
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
        HomeView(selectedTab: .constant(.home), pendingListName: .constant(nil))
    }
    .environment(APIService())
    .environment(AuthService())
    .environment(ProfileImageCache())
}
