import CoreLocation
import HealthKit
import SwiftUI

enum MainTab: Hashable, CaseIterable {
    case calendar, lists, home, concierge, budget, more

    var icon: String {
        switch self {
        case .calendar:   "calendar"
        case .lists:      "list.bullet.rectangle.fill"
        case .home:       "house.fill"
        case .concierge:  "sparkles"
        case .budget:     "creditcard.fill"
        case .more:       "ellipsis.circle.fill"
        }
    }

    /// Tabs shown in the floating bar. Concierge is intentionally excluded —
    /// it's an opt-in AI surface reached from its own floating button.
    static var barTabs: [MainTab] { [.calendar, .lists, .home, .budget, .more] }
}

struct ContentView: View {
    @Environment(AuthService.self) private var authService

    var body: some View {
        content
        #if DEBUG
            .task { await ScreenshotHarness.autoLoginIfNeeded(authService) }
        #endif
    }

    @ViewBuilder
    private var content: some View {
        if authService.isRestoringSession {
            ZStack {
                AmbientBackground(style: .home)
                ProgressView()
                    .tint(WarmPalette.ink2)
            }
        } else if authService.isAuthenticated {
            MainTabView()
        } else {
            LoginView()
        }
    }
}

#if DEBUG
/// DEBUG-only hooks for capturing marketing screenshots without manual taps.
/// Driven by launch env vars (set via `simctl launch ... SIMCTL_CHILD_UITEST_*`).
enum ScreenshotHarness {
    static var env: [String: String] { ProcessInfo.processInfo.environment }

    static var initialTab: MainTab {
        switch env["UITEST_TAB"] {
        case "calendar":  return .calendar
        case "lists":     return .lists
        case "concierge": return .concierge
        case "budget":    return .budget
        case "more":      return .more
        default:          return .home
        }
    }

    static var initialChat: Bool { env["UITEST_SHEET"] == "chat" }

    static var initialChatThread: ChatSheet.ChatThread? {
        guard let v = env["UITEST_CHAT_DM"] else { return nil }
        let parts = v.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, let id = Int(parts[0]) else { return nil }
        return .dm(partnerId: id, name: String(parts[1]))
    }

    static var openCare: Bool { env["UITEST_SHEET"] == "care" }

    /// Present the concierge chat sheet directly (its empty "How can I help?"
    /// state), bypassing the premium gate, for the marketing "ask" screenshot.
    static var openConciergeChat: Bool { env["UITEST_SHEET"] == "conciergechat" }

    /// Full-screen view to present for screenshots that live deeper than a tab.
    static var screen: String? { env["UITEST_SCREEN"] }

    @MainActor
    static func autoLoginIfNeeded(_ auth: AuthService) async {
        guard let creds = env["UITEST_AUTOLOGIN"] else { return }
        let parts = creds.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return }
        // Force a deterministic fresh login (skip the racy optimistic-restore path).
        // Screenshot runs hit a server with 2FA off, so this returns .authenticated.
        auth.isRestoringSession = false
        _ = try? await auth.login(username: String(parts[0]), password: String(parts[1]))
    }
}
#endif

struct MainTabView: View {
    @Environment(APIService.self) private var api
    @Environment(AuthService.self) private var auth
    @Environment(DeepLinkRouter.self) private var deepLinkRouter
    #if DEBUG
    @State private var selectedTab: MainTab = ScreenshotHarness.initialTab
    @State private var loadedTabs: Set<MainTab> = [ScreenshotHarness.initialTab, .home]
    @State private var showingChat = ScreenshotHarness.initialChat
    @State private var showingConciergeChat = ScreenshotHarness.openConciergeChat
    #else
    @State private var selectedTab: MainTab = .home
    @State private var loadedTabs: Set<MainTab> = [.home]
    @State private var showingChat = false
    #endif
    @State private var pendingListName: String?
    #if DEBUG
    @State private var chatInitialThread: ChatSheet.ChatThread? = ScreenshotHarness.initialChatThread
    #else
    @State private var chatInitialThread: ChatSheet.ChatThread?
    #endif
    @State private var unreadCount = 0
    @Environment(LocationService.self) private var locationService
    @Environment(ConciergeLaunch.self) private var conciergeLaunch
    @State private var trackedTripId: Int?
    @State private var deepRivalry: RivalryResponse?
    @State private var deepDecision: DecisionResponse?
    @State private var deepEvent: AppointmentResponse?
    @State private var showingDeepCoverage = false
    @State private var showingDeepTravel = false
    @AppStorage("aiConciergeEnabled") private var aiConciergeEnabled = false
    @State private var ptt = PushToTalkController()

    var body: some View {
        ZStack(alignment: .bottom) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                if loadedTabs.contains(tab) {
                    tabView(for: tab)
                        .opacity(selectedTab == tab ? 1 : 0)
                        .allowsHitTesting(selectedTab == tab)
                }
            }

            VStack {
                Spacer()
                FloatingTabBar(selectedTab: $selectedTab, onSelect: switchTab)
            }

            // Floating chat button — visible on all tabs
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button { showingChat = true } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.white)
                                .frame(width: 52, height: 52)
                                .background(TabAccent.home.color, in: Circle())
                                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)

                            if unreadCount > 0 {
                                Text("\(unreadCount)")
                                    .font(.flCaption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(minWidth: 18, minHeight: 18)
                                    .background(AccentTheme.rose.color, in: Circle())
                                    .offset(x: 4, y: -4)
                            }
                        }
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 80)
                }
            }

            // Floating AI concierge launcher — opt-in, mirrored across from chat.
            // Tap opens the concierge; press-and-hold dictates a quick note that
            // is sent to the AI in the background without leaving this screen.
            if aiConciergeEnabled {
                VStack {
                    Spacer()
                    HStack {
                        ConciergeLauncherButton(ptt: ptt) {
                            loadedTabs.insert(.concierge)
                            switchTab(to: .concierge)
                        }
                        .padding(.leading, 20)
                        .padding(.bottom, 80)
                        Spacer()
                    }
                }

                // Push-to-talk feedback (live transcript / sending / confirmation).
                PushToTalkOverlay(ptt: ptt)
            }
        }
        .ignoresSafeArea(.keyboard)
        .onChange(of: selectedTab) {
            loadedTabs.insert(selectedTab)  // backstop for non-switchTab writers
        }
        .sheet(isPresented: $showingChat) {
            ChatSheet(initialThread: chatInitialThread)
        }
        .onChange(of: showingChat) { _, showing in
            if !showing { chatInitialThread = nil }
        }
        .sheet(item: $deepRivalry) { rivalry in
            NavigationStack { RivalryDetailView(rivalry: rivalry) }
        }
        .sheet(item: $deepDecision) { decision in
            NavigationStack { DecisionDetailView(decision: decision) }
        }
        .sheet(item: $deepEvent) { event in
            NavigationStack { EventDetailView(appointment: event) }
        }
        .sheet(isPresented: $showingDeepCoverage) {
            NavigationStack { MyCoverageRequestsView() }
        }
        .sheet(isPresented: $showingDeepTravel) {
            NavigationStack { TravelHubView() }
        }
        #if DEBUG
        .fullScreenCover(isPresented: .constant(ScreenshotHarness.screen != nil)) {
            NavigationStack {
                switch ScreenshotHarness.screen {
                case "rivalries": RivalriesView()
                case "travel":    TravelHubView()
                default:          EmptyView()
                }
            }
        }
        .sheet(isPresented: $showingConciergeChat) {
            ConciergeChatView()
        }
        #endif
        .onChange(of: deepLinkRouter.pendingType) {
            guard let type = deepLinkRouter.pendingType else { return }
            Task { await handleDeepLink(type: type) }
        }
        .onChange(of: conciergeLaunch.requestID) {
            if conciergeLaunch.requestID != 0 {
                loadedTabs.insert(.concierge)
                switchTab(to: .concierge)
            }
        }
        .task {
            await pollUnread()
        }
    }

    /// Single entry point for changing tabs: preloads the destination BEFORE
    /// the animated transaction so its view is present to crossfade in, and
    /// animates the selection pill + content together. All programmatic tab
    /// changes (deep links, concierge launch) route through here too.
    private func switchTab(to tab: MainTab) {
        loadedTabs.insert(tab)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            selectedTab = tab
        }
    }

    private let healthKit = HealthKitManager()

    private func pollUnread() async {
        var locationReportCounter = 0
        var stepSyncCounter = 19  // trigger on second poll cycle (30s in)
        var isFirstPoll = true
        // Don't wipe delivered notifications on launch — that erased the user's
        // Notification Center history, including unread coverage/trip alerts
        // they hadn't acted on. Only clear stale PENDING (future) calendar ones.
        NotificationService.shared.removeStalePendingCalendarNotifications()
        while !Task.isCancelled {
            // Update badge count
            unreadCount = (try? await api.fetchUnreadMessageCount()) ?? 0

            // Fire local notifications for new messages (skip first poll to avoid flood on relaunch)
            if await NotificationService.shared.isAuthorized() {
                if isFirstPoll {
                    // Catch up watermarks without firing notifications
                    if let convos = try? await api.fetchConversations() {
                        NotificationService.shared.syncWatermark(convos)
                    }
                    if let feed = try? await api.fetchActivity() {
                        NotificationService.shared.syncFeedWatermark(feed)
                    }
                    isFirstPoll = false
                } else {
                    if let convos = try? await api.fetchConversations() {
                        NotificationService.shared.checkForNewMessages(convos)
                    }
                    let currentUser = auth.currentUser?.name ?? ""
                    if let feed = try? await api.fetchActivity() {
                        NotificationService.shared.checkForNewFeedItems(
                            feed,
                            currentUser: currentUser
                        )
                    }
                }
            }

            // Report location every ~5 minutes (every 20th poll cycle) — ONLY
            // if the user explicitly opted into household presence sharing.
            // Without this gate the app silently shared coordinates whenever OS
            // permission was granted, contradicting the "trips only" disclosure.
            locationReportCounter += 1
            if locationReportCounter >= 20 {
                locationReportCounter = 0
                if UserDefaults.standard.bool(forKey: "sharePresenceEnabled"),
                   let coord = await locationService.currentLocationIfAuthorized() {
                    _ = try? await api.reportLocation(lat: coord.latitude, lng: coord.longitude)
                }
            }

            // Auto-sync HealthKit steps for active step rivalries every ~5 minutes
            stepSyncCounter += 1
            if stepSyncCounter >= 20 {
                stepSyncCounter = 0
                await syncStepRivalries()
            }

            await syncActiveTripTracking()

            try? await Task.sleep(for: .seconds(15))
        }
    }

    private func syncActiveTripTracking() async {
        guard let trip = await currentUserActiveTrip() else {
            trackedTripId = nil
            locationService.stopTracking()
            return
        }

        if trackedTripId == trip.id, locationService.isTracking { return }

        trackedTripId = trip.id
        locationService.requestTripTrackingPermission()
        locationService.startTracking { coordinate in
            Task { await updateTripLocation(tripId: trip.id, coordinate: coordinate) }
        }

        // Set up geofence for auto-arrive
        if let destLat = trip.destination_lat, let destLng = trip.destination_lng {
            let dest = CLLocationCoordinate2D(latitude: destLat, longitude: destLng)
            locationService.monitorArrival(tripId: trip.id, destination: dest) {
                Task {
                    try? await api.arriveTrip(id: trip.id)
                    NotificationService.shared.notifyTripArrival(
                        traveler: trip.traveler.capitalized,
                        destination: trip.destination
                    )
                    NotificationService.shared.clearTripAlertState(tripId: trip.id)
                    trackedTripId = nil
                    locationService.stopTracking()
                }
            }
        }
    }

    private func syncStepRivalries() async {
        guard let rivalries = try? await api.fetchRivalries() else { return }

        let active = rivalries.filter {
            $0.status == RivalryStatus.active.rawValue && $0.challengeType.isHealthKitSynced
        }
        guard !active.isEmpty else { return }

        let dayFormatter = DateFormatter()
        dayFormatter.calendar = Calendar.current
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"

        for rivalry in active {
            let isStairs = rivalry.challengeType == .stairs
            let authorized = isStairs
                ? await healthKit.requestFlightsAuthorization()
                : await healthKit.requestStepAuthorization()
            guard authorized else { continue }

            let startDate = ISO8601DateFormatter.flexible.date(from: rivalry.start_date)
                ?? DateFormatter.isoDate.date(from: rivalry.start_date)
                ?? Date()
            let endDate = rivalry.endDate ?? Date()
            let identifier: HKQuantityTypeIdentifier = isStairs ? .flightsClimbed : .stepCount
            let daily = await healthKit.fetchDailyTotals(for: identifier, from: startDate, to: min(endDate, Date()))
            let myName = myRivalryName(in: rivalry)

            for entry in daily {
                try? await api.addRivalryEntry(id: rivalry.id, data: [
                    "member_name": myName,
                    "value": Int(entry.value.rounded()),
                    "activity_date": dayFormatter.string(from: entry.day),
                    "note": "Synced from Apple Health",
                    "is_verified": true
                ])
            }
        }

        // Refresh milestone notifications so their baked-in scores reflect the
        // totals we just synced. Local notifications can't recompute at fire
        // time, so without this the "last day / final push" reminder shows
        // whatever the score was the last time the Rivalries tab was opened.
        if let myName = auth.currentUser?.name {
            var entriesByRivalry: [Int: [RivalryEntryResponse]] = [:]
            for rivalry in rivalries {
                entriesByRivalry[rivalry.id] = (try? await api.fetchRivalryEntries(id: rivalry.id)) ?? []
            }
            NotificationService.shared.scheduleRivalryMilestones(
                rivalries,
                myName: myName,
                myUsername: auth.currentUser?.username ?? "",
                entriesByRivalry: entriesByRivalry
            )
        }
    }

    /// The current user's name as it appears in this rivalry's participants
    /// (e.g. "Sophie Chiasson" not "sophie"), so synced rows match across paths.
    private func myRivalryName(in rivalry: RivalryResponse) -> String {
        let name = auth.currentUser?.name ?? ""
        let username = auth.currentUser?.username ?? ""
        for participant in rivalry.participantNames {
            let p = participant.lowercased()
            for candidate in [name, username] where !candidate.isEmpty {
                let c = candidate.lowercased()
                if p == c || p.hasPrefix(c + " ") || c.hasPrefix(p + " ") { return participant }
            }
        }
        return name.isEmpty ? username : name
    }

    private func currentUserActiveTrip() async -> TripResponse? {
        guard let trips = try? await api.fetchTrips(status: "active") else { return nil }
        let currentNames = [
            auth.currentUser?.name.lowercased(),
            auth.currentUser?.username.lowercased()
        ].compactMap { $0 }
        return trips.first { currentNames.contains($0.traveler.lowercased()) }
    }

    private func updateTripLocation(tripId: Int, coordinate: CLLocationCoordinate2D) async {
        guard let trips = try? await api.fetchTrips(status: "active"),
              let trip = trips.first(where: { $0.id == tripId }),
              let destLat = trip.destination_lat,
              let destLng = trip.destination_lng else { return }

        let distance = LocationService.distance(
            from: coordinate,
            to: CLLocationCoordinate2D(latitude: destLat, longitude: destLng)
        )
        let destination = CLLocationCoordinate2D(latitude: destLat, longitude: destLng)
        let eta = await LocationService.routeEtaMinutes(from: coordinate, to: destination)
            ?? LocationService.etaMinutes(distanceMeters: distance)
        try? await api.updateTrip(id: tripId, updates: [
            "current_lat": coordinate.latitude,
            "current_lng": coordinate.longitude,
            "eta_minutes": eta
        ])
    }

    private func handleDeepLink(type: String) async {
        let refId = deepLinkRouter.pendingRefId
        let name = deepLinkRouter.pendingName
        deepLinkRouter.consume()

        switch type {
        case "rivalry":
            if let refId {
                let rivalries = (try? await api.fetchRivalries()) ?? []
                if let rivalry = rivalries.first(where: { $0.id == refId }) {
                    deepRivalry = rivalry
                }
            }
            switchTab(to: .home)
        case "decision":
            if let refId {
                deepDecision = try? await api.fetchDecision(id: refId)
            }
            switchTab(to: .home)
        case "event", "appointment":
            // Open the specific event when the id is known; else the calendar.
            if let refId,
               let event = try? await api.fetchAppointment(id: refId) {
                deepEvent = event
            } else {
                switchTab(to: .calendar)
            }
        case "message":
            if let refId, let name {
                chatInitialThread = .dm(partnerId: refId, name: name)
            }
            showingChat = true
        case "group_message":
            if let refId, let name {
                chatInitialThread = .group(groupId: refId, name: name)
            }
            showingChat = true
        case "coverage", "coverage_request", "coverage_confirmed":
            // Land on the coverage screen, not a generic home tab.
            showingDeepCoverage = true
        case "stay_request", "stay_confirmed", "stay_declined":
            showingDeepTravel = true
        case "post", "comment", "like", "mention", "milestone":
            // Feed-centric items live on Home.
            switchTab(to: .home)
        case "concierge":
            switchTab(to: .concierge)
        default:
            switchTab(to: .home)
        }
    }

    @ViewBuilder
    private func tabView(for tab: MainTab) -> some View {
        switch tab {
        case .calendar:  NavigationStack { CalendarView() }
        case .lists:     NavigationStack { FamilyListsView(pendingListName: $pendingListName) }
        case .home:      NavigationStack { HomeView(selectedTab: $selectedTab, pendingListName: $pendingListName, ptt: ptt) }
        case .concierge: NavigationStack { ConciergeView(selectedTab: $selectedTab) }
        case .budget:    NavigationStack { ExpensesView() }
        case .more:      NavigationStack { MoreView() }
        }
    }
}

// MARK: - Floating Glass Tab Bar

struct FloatingTabBar: View {
    @Binding var selectedTab: MainTab
    /// Owner's tab switch (preloads the destination, then animates). Falls back
    /// to a plain animated write if not supplied.
    var onSelect: ((MainTab) -> Void)? = nil
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.barTabs, id: \.self) { tab in
                Button {
                    if let onSelect {
                        onSelect(tab)
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            selectedTab = tab
                        }
                    }
                } label: {
                    Image(systemName: tab.icon)
                        .font(.system(size: 18, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(selectedTab == tab ? accentColor(for: tab) : WarmPalette.ink3)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                        .background {
                            if selectedTab == tab {
                                // One pill that slides between tabs rather than
                                // blinking in per-tab.
                                Circle()
                                    .fill(accentColor(for: tab).opacity(0.15))
                                    .frame(width: 40, height: 40)
                                    .matchedGeometryEffect(id: "tab-pill", in: pill)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.1), radius: 12, y: 4)
        .padding(.horizontal, 40)
        .padding(.bottom, 20)
    }

    private func accentColor(for tab: MainTab) -> Color {
        switch tab {
        case .calendar:  TabAccent.calendar.color
        case .lists:     TabAccent.home.color
        case .home:      TabAccent.home.color
        case .concierge: AccentTheme.saffron.color
        case .budget:    AccentTheme.terracotta.color
        case .more:      WarmPalette.ink2
        }
    }
}

#Preview {
    ContentView()
        .environment(AuthService())
        .environment(APIService())
        .environment(HouseholdService())
        .environment(ProfileImageCache())
        .environment(DeepLinkRouter())
        .environment(MessageCache())
        .environment(LocationService())
        .environment(SubscriptionService())
        .environment(ConciergeLaunch())
        .environment(CalendarService())
}
