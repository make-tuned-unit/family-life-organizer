import SwiftUI
import MapKit

struct TripsView: View {
    var showsDismissButton = false
    @Environment(\.dismiss) private var dismiss
    @Environment(APIService.self) private var api
    @Environment(AuthService.self) private var auth
    @State private var viewModel = TripsViewModel()
    @State private var locationService = LocationService()
    @State private var showingNewTrip = false
    @State private var showingAddresses = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.activeTrip != nil ? "IN PROGRESS" : "NO ACTIVE TRIP")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(WarmPalette.ink3)
                            .tracking(0.4)
                        Text("Trips")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(WarmPalette.ink1)
                    }
                    Spacer()
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .padding(.bottom, 16)

                if let active = viewModel.activeTrip {
                    ActiveTripCard(trip: active, viewModel: viewModel)
                }

                if viewModel.activeTrip == nil {
                    Button { showingNewTrip = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "car.fill")
                                .font(.system(size: 16))
                            Text("Start a Trip")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(WarmPalette.cream1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(WarmPalette.ink1)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                    }
                    .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                }

                // Trip history
                if !viewModel.pastTrips.isEmpty {
                    WarmSectionHeader(title: "Trip History", trailing: "\(viewModel.pastTrips.count)")
                        .padding(.top, 8)

                    VStack(spacing: 8) {
                        ForEach(viewModel.pastTrips) { trip in
                            TripHistoryRow(trip: trip)
                                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                        }
                    }
                }

                if viewModel.activeTrip == nil && viewModel.pastTrips.isEmpty && !viewModel.isLoading {
                    WarmEmptyState(
                        title: "No Trips Yet",
                        systemImage: "car.fill",
                        description: "Start a trip to share your ETA with family"
                    )
                }
            }
            .padding(.vertical)
        }
        .background { AmbientBackground(style: .trips) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .toolbar {
            if showsDismissButton {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(WarmPalette.ink2)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                GlassIconButton(systemName: "mappin.and.ellipse") {
                    showingAddresses = true
                }
            }
        }
        .sheet(isPresented: $showingAddresses) {
            NavigationStack {
                FamilyAddressesView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") { showingAddresses = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingNewTrip) {
            NewTripView { trip in
                Task { await viewModel.startTrip(trip, api: api) }
            }
        }
        .overlay {
            if viewModel.isLoading && viewModel.activeTrip == nil && viewModel.pastTrips.isEmpty {
                ProgressView()
            }
        }
        .alert("Something went wrong", isPresented: errorAlertIsPresented) {
            Button("OK") { viewModel.error = nil }
        } message: {
            Text(viewModel.error ?? "An unexpected error occurred.")
        }
        .refreshable {
            await viewModel.loadAll(api: api)
        }
        .task {
            await viewModel.loadAll(api: api)
            await syncTrackingIfNeeded()
        }
        .onChange(of: viewModel.activeTrip?.id) {
            Task { await syncTrackingIfNeeded() }
        }
        .onDisappear {
            locationService.stopTracking()
        }
    }

    private var errorAlertIsPresented: Binding<Bool> {
        Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )
    }

    private func syncTrackingIfNeeded() async {
        guard let activeTrip = viewModel.activeTrip, shouldTrack(trip: activeTrip) else {
            locationService.stopTracking()
            return
        }

        locationService.requestPermission()
        locationService.startTracking { coordinate in
            Task {
                guard let latestTrip = viewModel.activeTrip, latestTrip.id == activeTrip.id else { return }
                guard let destLat = latestTrip.destination_lat, let destLng = latestTrip.destination_lng else { return }
                let distance = LocationService.distance(
                    from: coordinate,
                    to: CLLocationCoordinate2D(latitude: destLat, longitude: destLng)
                )
                let eta = LocationService.etaMinutes(distanceMeters: distance)
                await viewModel.updateLocation(
                    tripId: latestTrip.id,
                    lat: coordinate.latitude,
                    lng: coordinate.longitude,
                    etaMinutes: eta,
                    api: api
                )
                await viewModel.maybeNotifyETA(for: latestTrip, etaMinutes: eta)
            }
        }
    }

    private func shouldTrack(trip: TripResponse) -> Bool {
        let currentNames = [
            auth.currentUser?.name.lowercased(),
            auth.currentUser?.username.lowercased(),
            "jesse"
        ].compactMap { $0 }
        return currentNames.contains(trip.traveler.lowercased())
    }
}

// MARK: - Active Trip Card

struct ActiveTripCard: View {
    let trip: TripResponse
    let viewModel: TripsViewModel
    @Environment(APIService.self) var api

    var body: some View {
        VStack(spacing: 16) {
            TripStatusHeader(trip: trip)

            TripLiveMapView(trip: trip)

            TripMetricsRow(trip: trip)

            TripAlertStateRow(trip: trip)

            HStack(spacing: 12) {
                Button {
                    Task { await viewModel.arriveTrip(trip.id, api: api) }
                } label: {
                    Label("Arrived", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.flPrimary(tint: WarmPalette.good))

                Button(role: .destructive) {
                    Task { await viewModel.cancelTrip(trip.id, api: api) }
                } label: {
                    Label("Cancel", systemImage: "xmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.flSecondary)
            }
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .flCard(tint: TabAccent.trips.color)
        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
    }
}

struct TripStatusHeader: View {
    let trip: TripResponse
    @Environment(AuthService.self) private var auth

    private var isCurrentUser: Bool {
        trip.traveler.localizedCaseInsensitiveCompare(auth.currentUser?.name ?? "") == .orderedSame
        || trip.traveler.localizedCaseInsensitiveCompare(auth.currentUser?.username ?? "") == .orderedSame
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if isCurrentUser {
                        ProfileAvatar(size: 28)
                    } else {
                        FamilyAvatar(initial: String(trip.traveler.prefix(1)).uppercased(), size: 28)
                    }
                    Text("\(trip.traveler.capitalized) is on the way")
                        .font(.headline)
                }

                HStack(spacing: 8) {
                    Label("Started", systemImage: "play.circle.fill")
                    if let started = startedAtText {
                        Text(started)
                    }
                }
                .font(.caption)
                .foregroundStyle(WarmPalette.ink3)

                HStack(spacing: 8) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(WarmPalette.bad)
                    Text(trip.destination)
                        .font(.subheadline.weight(.medium))
                }
            }

            Spacer()

            if let eta = trip.eta_minutes {
                VStack(spacing: 2) {
                    Text("\(max(0, eta))")
                        .font(.title.bold())
                        .foregroundStyle(eta <= 0 ? WarmPalette.good : TabAccent.home.color)
                    Text(eta <= 0 ? "arrived" : "min")
                        .font(.caption)
                        .foregroundStyle(WarmPalette.ink3)
                }
            }
        }
    }

    private var startedAtText: String? {
        guard let started = trip.startedAtDate else { return nil }
        return started.formatted(.relative(presentation: .named))
    }
}

struct TripMetricsRow: View {
    let trip: TripResponse

    private var currentCoordinate: CLLocationCoordinate2D? {
        if let curLat = trip.current_lat, let curLng = trip.current_lng {
            return CLLocationCoordinate2D(latitude: curLat, longitude: curLng)
        }
        if let originLat = trip.origin_lat, let originLng = trip.origin_lng {
            return CLLocationCoordinate2D(latitude: originLat, longitude: originLng)
        }
        return nil
    }

    private var destinationCoordinate: CLLocationCoordinate2D? {
        guard let destLat = trip.destination_lat, let destLng = trip.destination_lng else { return nil }
        return CLLocationCoordinate2D(latitude: destLat, longitude: destLng)
    }

    private var distanceRemainingText: String {
        guard let currentCoordinate, let destinationCoordinate else { return "Live distance unavailable" }
        let distance = LocationService.distance(from: currentCoordinate, to: destinationCoordinate)
        if distance < 1000 { return "\(Int(distance)) m left" }
        return String(format: "%.1f km left", distance / 1000)
    }

    var body: some View {
        HStack(spacing: 12) {
            TripMetricPill(title: "Status", value: tripPhaseTitle, systemImage: tripPhaseIcon, tint: TabAccent.home.color)
            TripMetricPill(title: "Remaining", value: distanceRemainingText, systemImage: "location.fill", tint: AccentTheme.ocean.color)
        }
    }

    private var tripPhaseTitle: String {
        guard let eta = trip.eta_minutes else { return "Started" }
        if eta <= 5 { return "Almost there" }
        if eta <= 15 { return "15 min out" }
        return "In transit"
    }

    private var tripPhaseIcon: String {
        guard let eta = trip.eta_minutes else { return "play.circle.fill" }
        if eta <= 5 { return "bell.badge.fill" }
        if eta <= 15 { return "timer" }
        return "road.lanes"
    }
}

struct TripMetricPill: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(WarmPalette.ink3)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignTokens.Spacing.cardGap)
        .background(tint.opacity(DesignTokens.Opacity.cardTint))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct TripAlertStateRow: View {
    let trip: TripResponse

    var body: some View {
        HStack {
            Label(alertTitle, systemImage: alertIcon)
                .font(.subheadline)
                .foregroundStyle(alertColor)
            Spacer()
            Text(alertDetail)
                .font(.caption)
                .foregroundStyle(WarmPalette.ink3)
        }
        .padding(DesignTokens.Spacing.cardGap)
        .background(WarmPalette.ink1.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var alertTitle: String {
        if NotificationService.shared.shouldSendTripETAAlert(tripId: trip.id, minutes: 15) {
            return "15-minute family alert armed"
        }
        return "15-minute alert sent"
    }

    private var alertIcon: String {
        NotificationService.shared.shouldSendTripETAAlert(tripId: trip.id, minutes: 15) ? "bell.badge" : "bell.badge.fill"
    }

    private var alertColor: Color {
        NotificationService.shared.shouldSendTripETAAlert(tripId: trip.id, minutes: 15) ? AccentTheme.saffron.color : WarmPalette.good
    }

    private var alertDetail: String {
        guard let eta = trip.eta_minutes else { return "Waiting for live ETA" }
        if eta > 15 { return "Triggers at 15 min remaining" }
        if eta > 5 { return "Family should already know they’re close" }
        return "Arrival is close"
    }
}

struct TripLiveMapView: View {
    let trip: TripResponse

    @State private var position: MapCameraPosition = .automatic
    @State private var route: MKRoute?

    var body: some View {
        Group {
            if let destinationCoordinate {
                Map(position: $position) {
                    if let route {
                        MapPolyline(route.polyline)
                            .stroke(TabAccent.home.color, lineWidth: 5)
                    }

                    if let currentCoordinate {
                        Annotation(trip.traveler.capitalized, coordinate: currentCoordinate) {
                            Image(systemName: "car.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.white, AccentTheme.ocean.color)
                                .shadow(radius: 6)
                        }
                    }

                    Marker(trip.destination, coordinate: destinationCoordinate)
                        .tint(TabAccent.home.color)
                }
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .task(id: mapRefreshID) {
                    await loadRoute()
                }
            } else {
                ContentUnavailableView(
                    "Live Map Unavailable",
                    systemImage: "map",
                    description: Text("Add a saved destination with coordinates to see the route and moving car.")
                )
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .background(WarmPalette.ink1.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var currentCoordinate: CLLocationCoordinate2D? {
        if let curLat = trip.current_lat, let curLng = trip.current_lng {
            return CLLocationCoordinate2D(latitude: curLat, longitude: curLng)
        }
        if let originLat = trip.origin_lat, let originLng = trip.origin_lng {
            return CLLocationCoordinate2D(latitude: originLat, longitude: originLng)
        }
        return nil
    }

    private var destinationCoordinate: CLLocationCoordinate2D? {
        guard let destLat = trip.destination_lat, let destLng = trip.destination_lng else { return nil }
        return CLLocationCoordinate2D(latitude: destLat, longitude: destLng)
    }

    private var mapRefreshID: String {
        "\(trip.id)-\(trip.current_lat ?? 0)-\(trip.current_lng ?? 0)-\(trip.destination_lat ?? 0)-\(trip.destination_lng ?? 0)"
    }

    private func loadRoute() async {
        guard let currentCoordinate, let destinationCoordinate else { return }

        let request = MKDirections.Request()
        request.transportType = .automobile
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: currentCoordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destinationCoordinate))

        do {
            let response = try await MKDirections(request: request).calculate()
            let bestRoute = response.routes.first
            await MainActor.run {
                route = bestRoute
                if let rect = bestRoute?.polyline.boundingMapRect {
                    position = .rect(rect)
                }
            }
        } catch {
            await MainActor.run {
                let latDelta = abs((currentCoordinate.latitude - destinationCoordinate.latitude) * 1.8)
                let lngDelta = abs((currentCoordinate.longitude - destinationCoordinate.longitude) * 1.8)
                let center = CLLocationCoordinate2D(
                    latitude: (currentCoordinate.latitude + destinationCoordinate.latitude) / 2,
                    longitude: (currentCoordinate.longitude + destinationCoordinate.longitude) / 2
                )
                position = .region(
                    MKCoordinateRegion(
                        center: center,
                        span: MKCoordinateSpan(
                            latitudeDelta: max(latDelta, 0.02),
                            longitudeDelta: max(lngDelta, 0.02)
                        )
                    )
                )
            }
        }
    }
}

// MARK: - Trip History Row

struct TripHistoryRow: View {
    let trip: TripResponse

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: trip.status == "arrived" ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(trip.status == "arrived" ? WarmPalette.good : WarmPalette.bad)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(trip.traveler.capitalized) → \(trip.destination)")
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 8) {
                    if let purpose = trip.purpose, !purpose.isEmpty {
                        Text(purpose)
                    }
                    if let date = trip.started_at {
                        Text(String(date.prefix(10)))
                    }
                }
                .font(.caption)
                .foregroundStyle(WarmPalette.ink3)
            }
            Spacer()
            if trip.status == "arrived", let started = trip.started_at, let arrived = trip.arrived_at {
                Text(formatDuration(from: started, to: arrived))
                    .font(.caption)
                    .foregroundStyle(WarmPalette.ink3)
            }
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .flCard(tint: TabAccent.trips.color)
    }

    private func formatDuration(from: String, to: String) -> String {
        guard let start = TripResponse.parseServerDate(from),
              let end = TripResponse.parseServerDate(to) else { return "" }
        let mins = Int(end.timeIntervalSince(start) / 60)
        if mins < 60 { return "\(mins)m" }
        return "\(mins / 60)h \(mins % 60)m"
    }
}

private extension TripResponse {
    var startedAtDate: Date? {
        guard let started_at else { return nil }
        return Self.parseServerDate(started_at)
    }

    static func parseServerDate(_ value: String) -> Date? {
        ISO8601DateFormatter.flexible.date(from: value)
        ?? ISO8601DateFormatter().date(from: value)
        ?? DateFormatter.sqliteDateTime.date(from: value)
    }
}

#Preview {
    NavigationStack {
        TripsView()
    }
    .environment(APIService())
    .environment(AuthService())
    .environment(HouseholdService())
}
