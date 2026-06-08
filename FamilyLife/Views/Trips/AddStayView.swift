import SwiftUI

struct AddStayView: View {
    @Environment(APIService.self) private var api
    @Environment(HouseholdService.self) private var household
    @Environment(\.dismiss) private var dismiss

    let itinerary: ItineraryResponse
    let existingStays: [ItineraryStayResponse]
    let onSaved: () async -> Void

    @State private var selectedHost: APIService.ContactResponse?
    @State private var checkIn: Date
    @State private var checkOut: Date
    @State private var locationName = ""
    @State private var address = ""
    @State private var notes = ""
    @State private var isSaving = false
    @State private var error: String?

    init(itinerary: ItineraryResponse, existingStays: [ItineraryStayResponse], onSaved: @escaping () async -> Void) {
        self.itinerary = itinerary
        self.existingStays = existingStays
        self.onSaved = onSaved
        let start = itinerary.startDate ?? Date()
        _checkIn = State(initialValue: start)
        _checkOut = State(initialValue: Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Staying with") {
                    ForEach(household.members) { member in
                        Button {
                            if selectedHost?.id == member.id {
                                selectedHost = nil
                            } else {
                                selectedHost = member
                                if locationName.isEmpty {
                                    locationName = "\(member.name)'s place"
                                }
                            }
                        } label: {
                            HStack {
                                FamilyAvatar(initial: member.avatar_initial ?? String(member.name.prefix(1)).uppercased(), size: 28)
                                VStack(alignment: .leading) {
                                    Text(member.name)
                                        .foregroundStyle(.primary)
                                    if household.userId(for: member.name) != nil {
                                        Text("App user — can approve")
                                            .font(.caption2)
                                            .foregroundStyle(WarmPalette.good)
                                    }
                                }
                                Spacer()
                                if selectedHost?.id == member.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(AccentTheme.ocean.color)
                                }
                            }
                        }
                    }
                }

                Section("Dates") {
                    DatePicker("Check in", selection: $checkIn, in: dateRange, displayedComponents: .date)
                    DatePicker("Check out", selection: $checkOut, in: checkIn...(itinerary.endDate ?? Date.distantFuture), displayedComponents: .date)
                        .onChange(of: checkIn) { _, newVal in
                            if checkOut <= newVal {
                                checkOut = Calendar.current.date(byAdding: .day, value: 1, to: newVal) ?? newVal
                            }
                        }
                }

                Section("Location") {
                    TextField("Place name", text: $locationName)
                    TextField("Address (optional)", text: $address)
                }

                Section("Notes") {
                    TextField("Any details for your host", text: $notes, axis: .vertical)
                        .lineLimit(3)
                }
            }
            .navigationTitle("Add Stay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private var dateRange: ClosedRange<Date> {
        let start = itinerary.startDate ?? Date.distantPast
        let end = itinerary.endDate ?? Date.distantFuture
        return start...end
    }

    private func save() async {
        isSaving = true
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"

        var body: [String: Any] = [
            "check_in": fmt.string(from: checkIn),
            "check_out": fmt.string(from: checkOut)
        ]
        if !locationName.isEmpty { body["location_name"] = locationName }
        if !address.isEmpty { body["address"] = address }
        if !notes.isEmpty { body["notes"] = notes }

        if let host = selectedHost {
            body["host_name"] = host.name
            if let userId = household.userId(for: host.name) {
                body["host_user_id"] = userId
            }
        }

        do {
            _ = try await api.addItineraryStay(itineraryId: itinerary.id, data: body)
            await onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
            isSaving = false
        }
    }
}
