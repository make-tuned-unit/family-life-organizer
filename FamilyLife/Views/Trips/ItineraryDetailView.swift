import SwiftUI

struct ItineraryDetailView: View {
    @Environment(APIService.self) private var api
    @Environment(AuthService.self) private var auth

    let itinerary: ItineraryResponse

    @State private var stays: [ItineraryStayResponse] = []
    @State private var isLoading = false
    @State private var showingAddStay = false
    @State private var editingStay: ItineraryStayResponse?
    @State private var error: String?
    @State private var isSendingAll = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Trip header
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dateRange)
                                .font(.subheadline)
                                .foregroundStyle(WarmPalette.ink2)
                            if let nights = totalNights {
                                Text("\(nights) nights \u{00B7} \(stays.count) stays")
                                    .font(.caption)
                                    .foregroundStyle(WarmPalette.ink3)
                            }
                        }
                        Spacer()
                        statusSummary
                    }
                }
                .padding(DesignTokens.Spacing.cardPadding)
                .flCard(tint: AccentTheme.ocean.color)
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)

                // Send all requests button
                if hasDraftStaysWithHosts {
                    Button {
                        Task { await sendAllRequests() }
                    } label: {
                        Label(isSendingAll ? "Sending..." : "Send All Requests", systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.flPrimary(tint: AccentTheme.ocean.color))
                    .disabled(isSendingAll)
                    .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                }

                // Timeline
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(timelineDays, id: \.date) { day in
                        TimelineDayRow(day: day, onTapOpen: {
                            editingStay = nil
                            showingAddStay = true
                        }, onDelete: { stay in
                            Task { await deleteStay(stay) }
                        })
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            }
            .padding(.vertical)
        }
        .background { AmbientBackground(style: .trips) }
        .navigationTitle(itinerary.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAddStay = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddStay) {
            AddStayView(itinerary: itinerary, existingStays: stays) {
                await loadStays()
            }
        }
        .refreshable { await loadStays() }
        .task { await loadStays() }
    }

    private func loadStays() async {
        isLoading = true
        do {
            stays = try await api.fetchItineraryStays(itineraryId: itinerary.id)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func deleteStay(_ stay: ItineraryStayResponse) async {
        do {
            try await api.deleteItineraryStay(itineraryId: itinerary.id, stayId: stay.id)
            await loadStays()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func sendAllRequests() async {
        isSendingAll = true
        for stay in stays where stay.status == "draft" && stay.host_user_id != nil {
            do {
                try await api.requestStay(stayId: stay.id)
            } catch {
                // Continue sending others even if one fails
            }
        }
        await loadStays()
        isSendingAll = false
    }

    // MARK: - Computed

    private var dateRange: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        guard let start = itinerary.startDate, let end = itinerary.endDate else {
            return "\(itinerary.start_date) \u{2013} \(itinerary.end_date)"
        }
        let yearFmt = DateFormatter()
        yearFmt.dateFormat = "MMM d, yyyy"
        return "\(formatter.string(from: start)) \u{2013} \(yearFmt.string(from: end))"
    }

    private var totalNights: Int? {
        guard let start = itinerary.startDate, let end = itinerary.endDate else { return nil }
        return Calendar.current.dateComponents([.day], from: start, to: end).day
    }

    private var hasDraftStaysWithHosts: Bool {
        stays.contains { $0.status == "draft" && $0.host_user_id != nil }
    }

    private var statusSummary: some View {
        let confirmed = stays.filter { $0.status == "confirmed" }.count
        let total = stays.count
        return HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(WarmPalette.good)
            Text("\(confirmed)/\(total)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WarmPalette.ink1)
        }
    }

    // MARK: - Timeline

    private var timelineDays: [TimelineDay] {
        guard let start = itinerary.startDate, let end = itinerary.endDate else { return [] }
        let calendar = Calendar.current
        var days: [TimelineDay] = []
        var current = start

        while current < end {
            let dateStr = DateFormatter.isoDate.string(from: current)
            let stay = stays.first { stayCoversDate(dateStr, stay: $0) }
            let isFirst = stay.map { $0.check_in == dateStr } ?? false
            days.append(TimelineDay(date: dateStr, displayDate: current, stay: stay, isFirstNight: isFirst))
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? end
        }
        return days
    }

    private func stayCoversDate(_ date: String, stay: ItineraryStayResponse) -> Bool {
        date >= stay.check_in && date < stay.check_out
    }
}

// MARK: - Timeline Day Model

struct TimelineDay {
    let date: String
    let displayDate: Date
    let stay: ItineraryStayResponse?
    let isFirstNight: Bool
}

// MARK: - Timeline Day Row

struct TimelineDayRow: View {
    let day: TimelineDay
    let onTapOpen: () -> Void
    let onDelete: (ItineraryStayResponse) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Date column
            VStack(spacing: 2) {
                Text(dayOfWeek)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(WarmPalette.ink3)
                Text(dayNumber)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(day.stay != nil ? WarmPalette.ink1 : WarmPalette.ink4)
            }
            .frame(width: 36)

            // Timeline line
            VStack(spacing: 0) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 10, height: 10)
                    .padding(.top, 6)
                Rectangle()
                    .fill(WarmPalette.ink4.opacity(0.3))
                    .frame(width: 2)
            }
            .frame(width: 10)

            // Content
            if let stay = day.stay, day.isFirstNight {
                StayCard(stay: stay, onDelete: { onDelete(stay) })
                    .padding(.bottom, 4)
            } else if day.stay == nil {
                Button(action: onTapOpen) {
                    HStack {
                        Image(systemName: "plus.circle.dashed")
                            .foregroundStyle(WarmPalette.ink4)
                        Text("Open")
                            .font(.subheadline)
                            .foregroundStyle(WarmPalette.ink3)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                .padding(.bottom, 4)
            } else {
                // Continuation of a stay — show thin bar
                HStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(stayStatusColor(day.stay!).opacity(0.2))
                        .frame(height: 4)
                }
                .padding(.vertical, 12)
            }
        }
    }

    private var dayOfWeek: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE"
        return fmt.string(from: day.displayDate)
    }

    private var dayNumber: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "d"
        return fmt.string(from: day.displayDate)
    }

    private var dotColor: Color {
        if let stay = day.stay {
            return stayStatusColor(stay)
        }
        return WarmPalette.ink4.opacity(0.3)
    }

    private func stayStatusColor(_ stay: ItineraryStayResponse) -> Color {
        switch stay.status {
        case "confirmed": WarmPalette.good
        case "requested": AccentTheme.saffron.color
        case "declined": .red
        default: WarmPalette.ink3
        }
    }
}

// MARK: - Stay Card

struct StayCard: View {
    let stay: ItineraryStayResponse
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let host = stay.host_name {
                    FamilyAvatar(initial: String(host.prefix(1)).uppercased(), size: 28)
                    Text(host)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WarmPalette.ink1)
                } else {
                    Image(systemName: "house.fill")
                        .foregroundStyle(AccentTheme.ocean.color)
                    Text(stay.location_name ?? "TBD")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WarmPalette.ink1)
                }
                Spacer()
                Image(systemName: stay.statusIcon)
                    .foregroundStyle(statusColor)
                    .font(.subheadline)
            }

            HStack {
                if let loc = stay.location_name ?? stay.address {
                    Label(loc, systemImage: "mappin")
                        .font(.caption)
                        .foregroundStyle(WarmPalette.ink3)
                        .lineLimit(1)
                }
                Spacer()
                Text("\(stay.nightCount) night\(stay.nightCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(WarmPalette.ink3)
            }

            if let notes = stay.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(WarmPalette.ink3)
                    .lineLimit(2)
            }

            // Status label
            Text(stay.status.capitalized)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(statusColor.opacity(0.15))
                .foregroundStyle(statusColor)
                .clipShape(Capsule())
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .flCard(tint: statusColor)
        .contextMenu {
            if stay.status == "draft" {
                Button(role: .destructive) { onDelete() } label: {
                    Label("Remove Stay", systemImage: "trash")
                }
            }
        }
    }

    private var statusColor: Color {
        switch stay.status {
        case "confirmed": WarmPalette.good
        case "requested": AccentTheme.saffron.color
        case "declined": .red
        default: WarmPalette.ink3
        }
    }
}
