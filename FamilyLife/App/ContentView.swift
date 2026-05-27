import CoreLocation
import SwiftUI

enum MainTab: Hashable, CaseIterable {
    case calendar, lists, home, budget, more

    var icon: String {
        switch self {
        case .calendar:  "calendar"
        case .lists:     "list.bullet.rectangle.fill"
        case .home:      "house.fill"
        case .budget:    "creditcard.fill"
        case .more:      "ellipsis.circle.fill"
        }
    }
}

struct ContentView: View {
    @Environment(AuthService.self) private var authService

    var body: some View {
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

struct MainTabView: View {
    @Environment(APIService.self) private var api
    @Environment(AuthService.self) private var auth
    @Environment(DeepLinkRouter.self) private var deepLinkRouter
    @State private var selectedTab: MainTab = .home
    @State private var pendingListName: String?
    @State private var loadedTabs: Set<MainTab> = [.home]
    @State private var showingChat = false
    @State private var chatInitialThread: ChatSheet.ChatThread?
    @State private var unreadCount = 0
    @Environment(LocationService.self) private var locationService
    @State private var trackedTripId: Int?
    @State private var deepRivalry: RivalryResponse?
    @State private var deepDecision: DecisionResponse?
    @State private var deepEvent: AppointmentResponse?

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
                FloatingTabBar(selectedTab: $selectedTab)
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
                                    .font(.system(size: 10, weight: .bold))
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
        }
        .ignoresSafeArea(.keyboard)
        .onChange(of: selectedTab) {
            loadedTabs.insert(selectedTab)
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
        .onChange(of: deepLinkRouter.pendingType) {
            guard let type = deepLinkRouter.pendingType else { return }
            Task { await handleDeepLink(type: type) }
        }
        .task {
            await pollUnread()
        }
    }

    private let healthKit = HealthKitManager()

    private func pollUnread() async {
        var locationReportCounter = 0
        var stepSyncCounter = 19  // trigger on second poll cycle (30s in)
        var isFirstPoll = true
        // Clear stale local notifications on launch to prevent flood
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
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

            // Report location every ~5 minutes (every 20th poll cycle)
            locationReportCounter += 1
            if locationReportCounter >= 20 {
                locationReportCounter = 0
                if let coord = await locationService.getCurrentLocation() {
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
        guard await healthKit.requestStepAuthorization() else { return }
        guard let rivalries = try? await api.fetchRivalries() else { return }
        let myName = auth.currentUser?.username ?? auth.currentUser?.name ?? ""

        let activeStepRivalries = rivalries.filter {
            $0.status == RivalryStatus.active.rawValue
            && $0.challengeType == .steps
        }

        for rivalry in activeStepRivalries {
            let startDate = ISO8601DateFormatter.flexible.date(from: rivalry.start_date)
                ?? DateFormatter.isoDate.date(from: rivalry.start_date)
                ?? Date()
            let endDate = rivalry.endDate ?? Date()
            let hkSteps = await healthKit.fetchSteps(from: startDate, to: min(endDate, Date()))
            guard hkSteps > 0 else { continue }

            let entries = (try? await api.fetchRivalryEntries(id: rivalry.id)) ?? []
            let myLogged = entries
                .filter { $0.member_name.localizedCaseInsensitiveCompare(myName) == .orderedSame }
                .reduce(0.0) { $0 + $1.value }
            let delta = hkSteps - myLogged
            guard delta > 0 else { continue }

            try? await api.addRivalryEntry(id: rivalry.id, data: [
                "member_name": myName,
                "value": delta,
                "note": "Synced from Apple Health",
                "is_verified": true
            ])
        }
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
            selectedTab = .home
        case "decision":
            if let refId {
                deepDecision = try? await api.fetchDecision(id: refId)
            }
            selectedTab = .home
        case "event", "appointment":
            selectedTab = .calendar
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
        case "coverage":
            selectedTab = .home
        default:
            selectedTab = .home
        }
    }

    @ViewBuilder
    private func tabView(for tab: MainTab) -> some View {
        switch tab {
        case .calendar:  NavigationStack { CalendarView() }
        case .lists:     NavigationStack { FamilyListsView(pendingListName: $pendingListName) }
        case .home:      NavigationStack { HomeView(selectedTab: $selectedTab, pendingListName: $pendingListName) }
        case .budget:    NavigationStack { ExpensesView() }
        case .more:      NavigationStack { MoreView() }
        }
    }
}

// MARK: - Floating Glass Tab Bar

struct FloatingTabBar: View {
    @Binding var selectedTab: MainTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Image(systemName: tab.icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(selectedTab == tab ? accentColor(for: tab) : WarmPalette.ink3)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                        .background {
                            if selectedTab == tab {
                                Circle()
                                    .fill(accentColor(for: tab).opacity(0.15))
                                    .frame(width: 40, height: 40)
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
}
