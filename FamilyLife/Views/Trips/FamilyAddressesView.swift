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
        } catch is CancellationError {
            // View dismissed — ignore
            } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func addAddress(_ data: [String: Any]) async {
        do {
            try await api.addFamilyAddress(data)
            await load()
        } catch is CancellationError {
            // View dismissed — ignore
            } catch {
            self.error = error.localizedDescription
        }
    }

    private func deleteAddress(_ id: Int) async {
        do {
            try await api.deleteFamilyAddress(id: id)
            addresses.removeAll { $0.id == id }
        } catch is CancellationError {
            // View dismissed — ignore
            } catch {
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
    @State private var address = ""
    @State private var position = MapCameraPosition.automatic
    @State private var markerCoord = CLLocationCoordinate2D(latitude: 44.6488, longitude: -63.5752) // Halifax default

    let onSave: ([String: Any]) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Jesse's House)", text: $name)
                    TextField("Street address (optional)", text: $address)
                }

                Section("Location") {
                    Map(position: $position, interactionModes: .all) {
                        Marker(name.isEmpty ? "Location" : name, coordinate: markerCoord)
                            .tint(TabAccent.home.color)
                    }
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture { location in
                        // Map tap doesn't give coordinates in SwiftUI Map directly
                        // User would need to manually enter or use search
                    }

                    HStack {
                        Text("Lat")
                        TextField("Latitude", value: Binding(
                            get: { markerCoord.latitude },
                            set: { markerCoord = CLLocationCoordinate2D(latitude: $0, longitude: markerCoord.longitude) }
                        ), format: .number)
                        .keyboardType(.decimalPad)
                    }
                    HStack {
                        Text("Lng")
                        TextField("Longitude", value: Binding(
                            get: { markerCoord.longitude },
                            set: { markerCoord = CLLocationCoordinate2D(latitude: markerCoord.latitude, longitude: $0) }
                        ), format: .number)
                        .keyboardType(.decimalPad)
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
                        if !address.isEmpty { data["address"] = address }
                        onSave(data)
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        FamilyAddressesView()
    }
    .environment(APIService())
}
