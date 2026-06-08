import SwiftUI

struct ItineraryListView: View {
    @Environment(APIService.self) private var api
    @Environment(AuthService.self) private var auth

    @State private var itineraries: [ItineraryResponse] = []
    @State private var pendingRequests: [ItineraryStayResponse] = []
    @State private var isLoading = false
    @State private var showingNewItinerary = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Pending stay requests from others
                if !pendingRequests.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        WarmSectionHeader(title: "Stay Requests")
                        ForEach(pendingRequests) { request in
                            StayRequestCard(stay: request) {
                                await loadAll()
                            }
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                }

                // Itineraries
                if itineraries.isEmpty && !isLoading {
                    VStack(spacing: 12) {
                        Image(systemName: "map.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(AccentTheme.ocean.color.opacity(0.5))
                        Text("No Itineraries Yet")
                            .font(.headline)
                            .foregroundStyle(WarmPalette.ink2)
                        Text("Plan your next trip — add stays with family and friends")
                            .font(.subheadline)
                            .foregroundStyle(WarmPalette.ink3)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        if !itineraries.isEmpty {
                            WarmSectionHeader(title: "My Itineraries")
                        }
                        ForEach(itineraries) { itinerary in
                            NavigationLink(destination: ItineraryDetailView(itinerary: itinerary)) {
                                ItineraryCard(itinerary: itinerary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                }
            }
            .padding(.vertical)
        }
        .background { AmbientBackground(style: .trips) }
        .navigationTitle("Itineraries")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingNewItinerary = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewItinerary) {
            NewItinerarySheet { await loadAll() }
        }
        .refreshable { await loadAll() }
        .task { await loadAll() }
    }

    private func loadAll() async {
        isLoading = true
        do {
            async let itin = api.fetchItineraries()
            async let pending = api.fetchPendingStayRequests()
            itineraries = try await itin
            pendingRequests = try await pending
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Itinerary Card

struct ItineraryCard: View {
    let itinerary: ItineraryResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "map.fill")
                    .foregroundStyle(AccentTheme.ocean.color)
                Text(itinerary.title)
                    .font(.headline)
                    .foregroundStyle(WarmPalette.ink1)
                Spacer()
                Text(itinerary.status.capitalized)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.15))
                    .foregroundStyle(statusColor)
                    .clipShape(Capsule())
            }

            HStack {
                Image(systemName: "calendar")
                    .font(.caption)
                    .foregroundStyle(WarmPalette.ink3)
                Text(dateRange)
                    .font(.subheadline)
                    .foregroundStyle(WarmPalette.ink2)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(WarmPalette.ink4)
            }

            if let travelers = itinerary.travelers, !travelers.isEmpty {
                HStack {
                    Image(systemName: "person.2.fill")
                        .font(.caption)
                        .foregroundStyle(WarmPalette.ink3)
                    Text(travelers)
                        .font(.caption)
                        .foregroundStyle(WarmPalette.ink3)
                        .lineLimit(1)
                }
            }
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .flCard(tint: AccentTheme.ocean.color)
    }

    private var dateRange: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        guard let start = itinerary.startDate, let end = itinerary.endDate else {
            return "\(itinerary.start_date) – \(itinerary.end_date)"
        }
        let yearFmt = DateFormatter()
        yearFmt.dateFormat = "MMM d, yyyy"
        return "\(formatter.string(from: start)) – \(yearFmt.string(from: end))"
    }

    private var statusColor: Color {
        switch itinerary.status {
        case "planning": AccentTheme.ocean.color
        case "active": WarmPalette.good
        case "completed": WarmPalette.ink3
        default: AccentTheme.ocean.color
        }
    }
}

// MARK: - New Itinerary Sheet

struct NewItinerarySheet: View {
    @Environment(APIService.self) private var api
    @Environment(HouseholdService.self) private var household
    @Environment(\.dismiss) private var dismiss

    let onSaved: () async -> Void

    @State private var title = ""
    @State private var startDate = Date()
    @State private var endDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var selectedTravelers: Set<String> = []
    @State private var notes = ""
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Trip name", text: $title)
                }
                Section("Dates") {
                    DatePicker("Start", selection: $startDate, displayedComponents: .date)
                    DatePicker("End", selection: $endDate, in: startDate..., displayedComponents: .date)
                }
                Section("Traveling with") {
                    ForEach(household.members) { member in
                        Button {
                            if selectedTravelers.contains(member.name) {
                                selectedTravelers.remove(member.name)
                            } else {
                                selectedTravelers.insert(member.name)
                            }
                        } label: {
                            HStack {
                                FamilyAvatar(initial: member.avatar_initial ?? String(member.name.prefix(1)).uppercased(), size: 28)
                                Text(member.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedTravelers.contains(member.name) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(AccentTheme.ocean.color)
                                }
                            }
                        }
                    }
                }
                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(3)
                }
            }
            .navigationTitle("New Itinerary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await create() }
                    }
                    .disabled(title.isEmpty || isSaving)
                }
            }
        }
    }

    private func create() async {
        isSaving = true
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        do {
            var data: [String: Any] = [
                "title": title,
                "start_date": fmt.string(from: startDate),
                "end_date": fmt.string(from: endDate)
            ]
            if !selectedTravelers.isEmpty {
                data["travelers"] = selectedTravelers.sorted().joined(separator: ", ")
            }
            if !notes.isEmpty { data["notes"] = notes }
            _ = try await api.createItinerary(data)
            await onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
            isSaving = false
        }
    }
}

// MARK: - Stay Request Card (for hosts)

struct StayRequestCard: View {
    @Environment(APIService.self) private var api
    let stay: ItineraryStayResponse
    let onResponded: () async -> Void

    @State private var isResponding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                FamilyAvatar(initial: String((stay.traveler_name ?? "?").prefix(1)).uppercased(), size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(stay.traveler_name ?? "Someone") wants to stay")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WarmPalette.ink1)
                    Text("\(stay.check_in) to \(stay.check_out)")
                        .font(.caption)
                        .foregroundStyle(WarmPalette.ink2)
                }
                Spacer()
            }

            if let notes = stay.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(WarmPalette.ink3)
            }

            HStack(spacing: 12) {
                Button {
                    Task { await respond(approved: true) }
                } label: {
                    Label("Approve", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.flPrimary(tint: WarmPalette.good))
                .disabled(isResponding)

                Button {
                    Task { await respond(approved: false) }
                } label: {
                    Label("Decline", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.flPrimary(tint: .red))
                .disabled(isResponding)
            }
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .flCard(tint: AccentTheme.saffron.color)
    }

    private func respond(approved: Bool) async {
        isResponding = true
        do {
            try await api.respondToStay(stayId: stay.id, approved: approved)
            await onResponded()
        } catch {
            isResponding = false
        }
    }
}
