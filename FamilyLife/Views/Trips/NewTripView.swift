import SwiftUI
import MapKit

struct NewTripView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(APIService.self) private var api
    @Environment(AuthService.self) private var auth
    @Environment(HouseholdService.self) private var household
    @Environment(LocationService.self) private var locationService

    @State private var destination = ""
    @State private var purpose = ""
    @State private var selectedAddress: FamilyAddressResponse?
    @State private var familyAddresses: [FamilyAddressResponse] = []
    @State private var etaMinutes: Int?
    @State private var isCalculatingETA = false
    @State private var notifyPercent = 10
    @State private var error: String?
    @State private var locationCompleter = LocationCompleter()
    @State private var showingLocationSuggestions = false
    @State private var isSelectingSavedAddress = false
    @State private var shareGroupId: Int?

    let onSave: ([String: Any]) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        ProfileAvatar(size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(auth.currentUser?.name ?? "Me")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Starting a trip")
                                .font(.system(size: 12))
                                .foregroundStyle(WarmPalette.ink3)
                        }
                    }
                }

                Section("Where to?") {
                    if !familyAddresses.isEmpty {
                        ForEach(familyAddresses) { addr in
                            Button { selectSavedAddress(addr) } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(addr.name)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(selectedAddress?.id == addr.id ? TabAccent.home.color : .primary)
                                        if let address = addr.address {
                                            Text(address)
                                                .font(.caption)
                                                .foregroundStyle(WarmPalette.ink3)
                                        }
                                    }
                                    Spacer()
                                    if selectedAddress?.id == addr.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(TabAccent.home.color)
                                    }
                                }
                            }
                        }
                    }

                    if selectedAddress == nil {
                        TextField("Search for a place...", text: $destination)
                            .onChange(of: destination) {
                                guard !isSelectingSavedAddress else { return }
                                locationCompleter.search(query: destination)
                                showingLocationSuggestions = !destination.isEmpty
                            }

                        if showingLocationSuggestions && !locationCompleter.results.isEmpty {
                            ForEach(locationCompleter.results, id: \.self) { result in
                                Button {
                                    let full = [result.title, result.subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
                                    destination = full
                                    showingLocationSuggestions = false
                                    resolveAndCalculateETA(for: result)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(result.title)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                        if !result.subtitle.isEmpty {
                                            Text(result.subtitle)
                                                .font(.caption)
                                                .foregroundStyle(WarmPalette.ink3)
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        Button {
                            selectedAddress = nil
                            destination = ""
                            etaMinutes = nil
                        } label: {
                            Label("Change destination", systemImage: "arrow.triangle.2.circlepath")
                                .font(.caption)
                                .foregroundStyle(WarmPalette.ink3)
                        }
                    }
                }

                Section("ETA") {
                    if isCalculatingETA {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Calculating route...")
                                .font(.system(size: 14))
                                .foregroundStyle(WarmPalette.ink3)
                        }
                    } else if let eta = etaMinutes {
                        HStack {
                            Image(systemName: "car.fill")
                                .foregroundStyle(TabAccent.home.color)
                            Text("\(TripDisplayHelpers.etaText(eta)) drive")
                                .font(.system(size: 15, weight: .semibold))
                            Spacer()
                            Text("via Apple Maps")
                                .font(.system(size: 11))
                                .foregroundStyle(WarmPalette.ink4)
                        }
                    } else {
                        Text("Select a destination to calculate ETA")
                            .font(.system(size: 13))
                            .foregroundStyle(WarmPalette.ink4)
                    }

                    Picker("Notify when", selection: $notifyPercent) {
                        Text("10% away").tag(10)
                        Text("25% away").tag(25)
                        Text("50% away").tag(50)
                        Text("5 min away").tag(-5)
                        Text("15 min away").tag(-15)
                    }
                }

                Section("Details") {
                    TextField("Purpose (optional)", text: $purpose)
                }

                ShareWithSection(selectedGroupId: $shareGroupId)
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground(style: .trips) }
            .navigationTitle("Start Trip")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Something went wrong", isPresented: errorAlertIsPresented) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Go") {
                        startTrip()
                        dismiss()
                    }
                    .disabled(destination.isEmpty && selectedAddress == nil)
                }
            }
            .task {
                await loadAddresses()
                locationService.requestTripTrackingPermission()
            }
        }
    }

    private func selectSavedAddress(_ addr: FamilyAddressResponse) {
        isSelectingSavedAddress = true
        selectedAddress = addr
        destination = addr.name
        showingLocationSuggestions = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isSelectingSavedAddress = false
        }
        calculateETA(to: CLLocationCoordinate2D(latitude: addr.lat, longitude: addr.lng))
    }

    private func resolveAndCalculateETA(for completion: MKLocalSearchCompletion) {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        search.start { response, _ in
            guard let item = response?.mapItems.first else { return }
            calculateETA(to: item.placemark.coordinate)
        }
    }

    private func calculateETA(to destCoord: CLLocationCoordinate2D) {
        isCalculatingETA = true
        let request = MKDirections.Request()

        if let loc = locationService.currentLocation {
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: loc))
        } else {
            request.source = MKMapItem.forCurrentLocation()
        }

        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destCoord))
        request.transportType = .automobile

        let directions = MKDirections(request: request)
        directions.calculateETA { response, _ in
            isCalculatingETA = false
            if let eta = response {
                etaMinutes = max(1, Int(eta.expectedTravelTime / 60))
            }
        }
    }

    private func loadAddresses() async {
        do {
            familyAddresses = try await api.fetchFamilyAddresses()
        } catch {
            guard !error.isCancellation, !(error is APIError) else { return }
            self.error = error.localizedDescription
        }
    }

    private func startTrip() {
        var data: [String: Any] = [
            "traveler": (auth.currentUser?.name ?? "Me").lowercased(),
            "destination": selectedAddress?.name ?? destination,
            "eta_minutes": etaMinutes ?? 30,
            "notify_percent": notifyPercent
        ]
        if !purpose.isEmpty { data["purpose"] = purpose }
        if let addr = selectedAddress {
            data["destination_lat"] = addr.lat
            data["destination_lng"] = addr.lng
        }
        if let loc = locationService.currentLocation {
            data["origin_lat"] = loc.latitude
            data["origin_lng"] = loc.longitude
        }
        onSave(data)

        // Cross-post to group if selected
        if let groupId = shareGroupId {
            let dest = selectedAddress?.name ?? destination
            let etaStr = etaMinutes.map { TripDisplayHelpers.etaText($0) } ?? ""
            Task {
                _ = try? await api.addFeedPost(groupId: groupId, data: [
                    "post_type": "event",
                    "title": "On my way to \(dest)",
                    "body": "\(auth.currentUser?.name ?? "Someone") is heading to \(dest)\(!etaStr.isEmpty ? " — ETA \(etaStr)" : "")"
                ])
            }
        }
    }

    private var errorAlertIsPresented: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    }
}

#Preview {
    NewTripView { _ in }
        .environment(APIService())
        .environment(AuthService())
        .environment(HouseholdService())
        .environment(LocationService())
}
