import SwiftUI
import MapKit

struct FamilyAddressesView: View {
    @Environment(APIService.self) private var api
    @State private var addresses: [FamilyAddressResponse] = []
    @State private var showingAdd = false
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        List {
            if addresses.isEmpty && !isLoading {
                ContentUnavailableView(
                    "No Saved Addresses",
                    systemImage: "mappin.slash",
                    description: Text("Add family addresses for quick trip destinations")
                )
            }
            ForEach(addresses) { addr in
                VStack(alignment: .leading, spacing: 4) {
                    Text(addr.name)
                        .font(.subheadline.weight(.medium))
                    if let address = addr.address {
                        Text(address)
                            .font(.caption)
                            .foregroundStyle(WarmPalette.ink3)
                    }
                    Text("\(addr.lat, specifier: "%.4f"), \(addr.lng, specifier: "%.4f")")
                        .font(.caption2)
                        .foregroundStyle(WarmPalette.ink4)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { await deleteAddress(addr.id) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background { AmbientBackground(style: .trips) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAdd = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add place")
            }
        }
        .alert("Couldn’t update addresses", isPresented: errorAlertIsPresented) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "An unexpected error occurred.")
        }
        .sheet(isPresented: $showingAdd) {
            AddAddressView { address in
                Task { await addAddress(address) }
            }
        }
        .task {
            await load()
        }
    }

    private func load() async {
        isLoading = true
        do {
            addresses = try await api.fetchFamilyAddresses()
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func addAddress(_ data: [String: Any]) async {
        do {
            try await api.addFamilyAddress(data)
            await load()
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }

    private func deleteAddress(_ id: Int) async {
        do {
            try await api.deleteFamilyAddress(id: id)
            addresses.removeAll { $0.id == id }
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }

    private var errorAlertIsPresented: Binding<Bool> {
        Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )
    }
}

struct AddAddressView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var addressQuery = ""
    @State private var resolvedAddress = ""
    @State private var position = MapCameraPosition.automatic
    @State private var markerCoord = CLLocationCoordinate2D(latitude: 44.6488, longitude: -63.5752)
    @State private var locationCompleter = LocationCompleter()
    @State private var showingSuggestions = false
    @State private var hasSelectedLocation = false

    let onSave: ([String: Any]) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Jesse's House)", text: $name)
                }

                Section("Address") {
                    TextField("Search for an address...", text: $addressQuery)
                        .onChange(of: addressQuery) {
                            locationCompleter.search(query: addressQuery)
                            showingSuggestions = !addressQuery.isEmpty
                            hasSelectedLocation = false
                        }

                    if showingSuggestions && !locationCompleter.results.isEmpty {
                        ForEach(locationCompleter.results, id: \.self) { result in
                            Button {
                                let fullAddress = [result.title, result.subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
                                addressQuery = fullAddress
                                resolvedAddress = fullAddress
                                showingSuggestions = false
                                resolveCoordinates(for: result)
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

                if hasSelectedLocation {
                    Section("Location") {
                        Map(position: $position, interactionModes: .all) {
                            Marker(name.isEmpty ? "Location" : name, coordinate: markerCoord)
                                .tint(TabAccent.home.color)
                        }
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .navigationTitle("Add Address")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var data: [String: Any] = [
                            "name": name,
                            "lat": markerCoord.latitude,
                            "lng": markerCoord.longitude
                        ]
                        if !resolvedAddress.isEmpty { data["address"] = resolvedAddress }
                        onSave(data)
                        dismiss()
                    }
                    .disabled(name.isEmpty || !hasSelectedLocation)
                }
            }
        }
    }

    private func resolveCoordinates(for completion: MKLocalSearchCompletion) {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        search.start { response, _ in
            guard let item = response?.mapItems.first else { return }
            markerCoord = item.placemark.coordinate
            position = .region(MKCoordinateRegion(
                center: markerCoord,
                latitudinalMeters: 500,
                longitudinalMeters: 500
            ))
            hasSelectedLocation = true
        }
    }
}

#Preview {
    NavigationStack {
        FamilyAddressesView()
    }
    .environment(APIService())
}
