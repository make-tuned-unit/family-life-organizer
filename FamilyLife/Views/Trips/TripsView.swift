import SwiftUI
import MapKit

struct TripsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(APIService.self) private var api
    @State private var viewModel = TripsViewModel()
    @State private var showingNewTrip = false
    @State private var showingAddresses = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Active trip card
                if let active = viewModel.activeTrip {
                    ActiveTripCard(trip: active, viewModel: viewModel)
                }

                // Start trip button (only if no active trip)
                if viewModel.activeTrip == nil {
                    Button { showingNewTrip = true } label: {
                        HStack {
                            Image(systemName: "car.fill")
                            Text("Start a Trip")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.teal.gradient)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(.horizontal)
                }

                // Trip history
                if !viewModel.pastTrips.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Trip History")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(viewModel.pastTrips) { trip in
                            TripHistoryRow(trip: trip)
                                .padding(.horizontal)
                        }
                    }
                }

                if viewModel.activeTrip == nil && viewModel.pastTrips.isEmpty && !viewModel.isLoading {
                    ContentUnavailableView(
                        "No Trips Yet",
                        systemImage: "car.fill",
                        description: Text("Start a trip to share your ETA with family")
                    )
                }
            }
            .padding(.vertical)
        }
        .background { AmbientBackground(style: .trips) }
        .navigationTitle("Trips")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAddresses = true } label: {
                    Image(systemName: "mappin.and.ellipse")
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
        .refreshable {
            await viewModel.loadAll(api: api)
        }
        .task {
            await viewModel.loadAll(api: api)
        }
    }
}

// MARK: - Active Trip Card

struct ActiveTripCard: View {
    let trip: TripResponse
    let viewModel: TripsViewModel
    @Environment(APIService.self) var api

    var body: some View {
        VStack(spacing: 16) {
            // Map
            if let destLat = trip.destination_lat, let destLng = trip.destination_lng {
                Map {
                    if let curLat = trip.current_lat, let curLng = trip.current_lng {
                        Marker(trip.traveler, coordinate: CLLocationCoordinate2D(latitude: curLat, longitude: curLng))
                            .tint(.blue)
                    }
                    Marker(trip.destination, coordinate: CLLocationCoordinate2D(latitude: destLat, longitude: destLng))
                        .tint(.teal)
                }
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Trip info
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "car.fill")
                            .foregroundStyle(.teal)
                        Text(trip.traveler.capitalized)
                            .font(.headline)
                        Text("is traveling")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(.red)
                        Text(trip.destination)
                            .font(.subheadline)
                    }
                }
                Spacer()
                if let eta = trip.eta_minutes {
                    VStack {
                        Text("\(eta)")
                            .font(.title.bold())
                            .foregroundStyle(.teal)
                        Text("min")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Progress bar
            if let eta = trip.eta_minutes {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.fill.tertiary)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.teal.gradient)
                            .frame(width: geo.size.width * max(0, 1 - Double(eta) / 60.0))
                    }
                }
                .frame(height: 8)
            }

            // Actions
            HStack(spacing: 12) {
                Button {
                    Task { await viewModel.arriveTrip(trip.id, api: api) }
                } label: {
                    Label("Arrived", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.flPrimary(tint: .green))

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

// MARK: - Trip History Row

struct TripHistoryRow: View {
    let trip: TripResponse

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: trip.status == "arrived" ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(trip.status == "arrived" ? .green : .red)

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
                .foregroundStyle(.secondary)
            }
            Spacer()
            if trip.status == "arrived", let started = trip.started_at, let arrived = trip.arrived_at {
                Text(formatDuration(from: started, to: arrived))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .flCard(tint: TabAccent.trips.color)
    }

    private func formatDuration(from: String, to: String) -> String {
        guard let start = DateFormatter.sqliteDateTime.date(from: from),
              let end = DateFormatter.sqliteDateTime.date(from: to) else { return "" }
        let mins = Int(end.timeIntervalSince(start) / 60)
        if mins < 60 { return "\(mins)m" }
        return "\(mins / 60)h \(mins % 60)m"
    }
}

#Preview {
    NavigationStack {
        TripsView()
    }
    .environment(APIService())
}
