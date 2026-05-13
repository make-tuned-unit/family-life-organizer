import SwiftUI
import MapKit

struct NewTripView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(APIService.self) private var api
    @Environment(AuthService.self) private var auth
    @Environment(HouseholdService.self) private var household
    @State private var locationService = LocationService()

    @State private var traveler = ""
    @State private var destination = ""
    @State private var purpose = ""
    @State private var selectedAddress: FamilyAddressResponse?
    @State private var familyAddresses: [FamilyAddressResponse] = []
    @State private var etaMinutes = 30
    @State private var error: String?
    @State private var locationCompleter = LocationCompleter()
    @State private var showingLocationSuggestions = false

    let onSave: ([String: Any]) -> Void

    private var travelerNames: [String] {
        var names = [auth.currentUser?.name ?? "Me"]
        names += household.members.map(\.name)
        return names
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Who's traveling?") {
                    Picker("Traveler", selection: $traveler) {
                        ForEach(travelerNames, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Destination") {
                    if !familyAddresses.isEmpty {
                        ForEach(familyAddresses) { addr in
                            Button {
                                selectedAddress = addr
                                destination = addr.name
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(addr.name)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                        if let address = addr.address {
                                            Text(address)
                                                .font(.caption)
                                                .foregroundStyle(WarmPalette.ink3)
                                        }
                                    }
                                    Spacer()
                                    if selectedAddress?.id == addr.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(TabAccent.home.color)
                                    }
                                }
                            }
                        }
                    }

                    TextField("Or search for a place...", text: $destination)
                        .onChange(of: destination) {
                            selectedAddress = nil
                            locationCompleter.search(query: destination)
                            showingLocationSuggestions = !destination.isEmpty
                        }

                    if showingLocationSuggestions && !locationCompleter.results.isEmpty {
                        ForEach(locationCompleter.results, id: \.self) { result in
                            Button {
                                destination = [result.title, result.subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
                                showingLocationSuggestions = false
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
                }

                Section("Details") {
                    TextField("Purpose (optional)", text: $purpose)

                    Stepper("ETA: \(etaMinutes) min", value: $etaMinutes, in: 5...480, step: 5)
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground(style: .trips) }
            .navigationTitle("Start Trip")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Couldn’t load trip setup", isPresented: errorAlertIsPresented) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "An unexpected error occurred.")
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
                    .disabled(destination.isEmpty)
                }
            }
            .task {
                await loadAddresses()
                locationService.requestPermission()
                if traveler.isEmpty {
                    traveler = auth.currentUser?.name ?? "Me"
                }
            }
        }
    }

    private func loadAddresses() async {
        do {
            familyAddresses = try await api.fetchFamilyAddresses()
        } catch let loadError {
            error = loadError.localizedDescription
        }
    }

    private func startTrip() {
        var data: [String: Any] = [
            "traveler": traveler.lowercased(),
            "destination": destination,
            "eta_minutes": etaMinutes
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
    }

    private var errorAlertIsPresented: Binding<Bool> {
        Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )
    }
}

#Preview {
    NewTripView { _ in }
        .environment(APIService())
        .environment(AuthService())
        .environment(HouseholdService())
}
