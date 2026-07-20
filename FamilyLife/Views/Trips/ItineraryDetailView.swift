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
    @State private var tripExpenseTotal: Double = 0
    @State private var tripExpenseCount: Int = 0
    @State private var showingAddTripExpense = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Trip header
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dateRange)
                                .font(.flSubheadline)
                                .foregroundStyle(WarmPalette.ink2)
                            if let nights = totalNights {
                                Text("\(nights) nights \u{00B7} \(stays.count) stays")
                                    .font(.flCaption)
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

                // Trip expenses summary
                if tripExpenseTotal > 0 || tripExpenseCount > 0 {
                    HStack {
                        Image(systemName: "creditcard.fill")
                            .foregroundStyle(AccentTheme.saffron.color)
                        Text("Trip Expenses")
                            .font(.flSubheadline.weight(.semibold))
                        Spacer()
                        Text("$\(tripExpenseTotal, specifier: "%.2f")")
                            .font(.flSubheadline.weight(.bold))
                            .foregroundStyle(WarmPalette.ink1)
                        Text("(\(tripExpenseCount) receipts)")
                            .font(.flCaption)
                            .foregroundStyle(WarmPalette.ink3)
                    }
                    .padding(DesignTokens.Spacing.cardPadding)
                    .flCard(tint: AccentTheme.saffron.color)
                    .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                }

                Button {
                    showingAddTripExpense = true
                } label: {
                    Label("Add Trip Expense", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.flPrimary(tint: AccentTheme.saffron.color))
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
                        }, onEdit: { stay in
                            editingStay = stay
                        }, onDelete: { stay in
                            Task { await deleteStay(stay) }
                        })
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            }
            .padding(.vertical)
            .padding(.bottom, 80)
        }
        .background { AmbientBackground(style: .trips) }
        .navigationTitle(itinerary.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAddStay = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add accommodation")
            }
        }
        .sheet(isPresented: $showingAddStay) {
            AddStayView(itinerary: itinerary, existingStays: stays) {
                await loadStays()
            }
        }
        .sheet(isPresented: $showingAddTripExpense) {
            AddReceiptView(preselectedCategory: "Trip", preselectedItinerary: itinerary)
        }
        .sheet(item: $editingStay) { stay in
            EditStayView(itinerary: itinerary, stay: stay) {
                await loadStays()
            }
        }
        .refreshable {
            await loadStays()
            await loadTripExpenses()
        }
        .task {
            await loadStays()
            await loadTripExpenses()
        }
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

    private func loadTripExpenses() async {
        if let expenseData = try? await api.fetchItineraryExpenses(itineraryId: itinerary.id) {
            tripExpenseTotal = expenseData.total
            tripExpenseCount = expenseData.count
        }
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
        var failCount = 0
        for stay in stays where stay.status == "draft" && stay.host_user_id != nil {
            do {
                try await api.requestStay(stayId: stay.id)
            } catch {
                failCount += 1
            }
        }
        await loadStays()
        if failCount > 0 {
            self.error = "Failed to send \(failCount) request(s). Please try again."
        }
        isSendingAll = false
    }

    // MARK: - Computed

    private static let monthDayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()
    private static let monthDayYearFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"; return f
    }()

    private var dateRange: String {
        guard let start = itinerary.startDate, let end = itinerary.endDate else {
            return "\(itinerary.start_date) \u{2013} \(itinerary.end_date)"
        }
        return "\(Self.monthDayFmt.string(from: start)) \u{2013} \(Self.monthDayYearFmt.string(from: end))"
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
                .font(.flSubheadline.weight(.semibold))
                .foregroundStyle(WarmPalette.ink1)
        }
    }

    // MARK: - Timeline

    private var timelineDays: [TimelineDay] {
        guard let start = itinerary.startDate, let end = itinerary.endDate else { return [] }
        let calendar = Calendar.current
        var days: [TimelineDay] = []
        var current = start

        while current <= end {
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
    let onEdit: (ItineraryStayResponse) -> Void
    let onDelete: (ItineraryStayResponse) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Date column
            VStack(spacing: 2) {
                Text(dayOfWeek)
                    .font(.flCaption2.weight(.medium))
                    .foregroundStyle(WarmPalette.ink3)
                Text(dayNumber)
                    .font(.flTitle)
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
                StayCard(stay: stay, onEdit: { onEdit(stay) }, onDelete: { onDelete(stay) })
                    .padding(.bottom, 4)
            } else if day.stay == nil {
                Button(action: onTapOpen) {
                    HStack {
                        Image(systemName: "plus.circle.dashed")
                            .foregroundStyle(WarmPalette.ink4)
                        Text("Open")
                            .font(.flSubheadline)
                            .foregroundStyle(WarmPalette.ink3)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                .padding(.bottom, 4)
            } else if let stay = day.stay {
                // Continuation day — show compact host row
                HStack(spacing: 8) {
                    if let host = stay.host_name {
                        FamilyAvatar(initial: String(host.prefix(1)).uppercased(), size: 22, name: host)
                        Text(host)
                            .font(.flCaption.weight(.medium))
                            .foregroundStyle(WarmPalette.ink2)
                    } else {
                        Image(systemName: "house.fill")
                            .font(.flCaption)
                            .foregroundStyle(stayStatusColor(stay))
                        Text(stay.location_name ?? "Stay")
                            .font(.flCaption.weight(.medium))
                            .foregroundStyle(WarmPalette.ink2)
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(stayStatusColor(stay).opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small))
                .padding(.bottom, 2)
            }
        }
    }

    private static let weekdayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE"; return f
    }()
    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d"; return f
    }()

    private var dayOfWeek: String {
        Self.weekdayFmt.string(from: day.displayDate)
    }

    private var dayNumber: String {
        Self.dayFmt.string(from: day.displayDate)
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
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let host = stay.host_name {
                    FamilyAvatar(initial: String(host.prefix(1)).uppercased(), size: 28, name: host)
                    Text(host)
                        .font(.flSubheadline.weight(.semibold))
                        .foregroundStyle(WarmPalette.ink1)
                } else {
                    Image(systemName: "house.fill")
                        .foregroundStyle(AccentTheme.ocean.color)
                    Text(stay.location_name ?? "TBD")
                        .font(.flSubheadline.weight(.semibold))
                        .foregroundStyle(WarmPalette.ink1)
                }
                Spacer()
                Image(systemName: stay.statusIcon)
                    .foregroundStyle(statusColor)
                    .font(.flSubheadline)
            }

            HStack {
                if let loc = stay.location_name ?? stay.address {
                    Label(loc, systemImage: "mappin")
                        .font(.flCaption)
                        .foregroundStyle(WarmPalette.ink3)
                        .lineLimit(1)
                }
                Spacer()
                Text("\(stay.nightCount) night\(stay.nightCount == 1 ? "" : "s")")
                    .font(.flCaption)
                    .foregroundStyle(WarmPalette.ink3)
            }

            if let notes = stay.notes, !notes.isEmpty {
                Text(notes)
                    .font(.flCaption)
                    .foregroundStyle(WarmPalette.ink3)
                    .lineLimit(2)
            }

            // Status label
            Text(stay.status.capitalized)
                .font(.flCaption2.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(statusColor.opacity(0.15))
                .foregroundStyle(statusColor)
                .clipShape(Capsule())
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .flCard(tint: statusColor)
        .contextMenu {
            Button { onEdit() } label: {
                Label("Edit Stay", systemImage: "pencil")
            }
            Button(role: .destructive) { onDelete() } label: {
                Label("Remove Stay", systemImage: "trash")
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

#Preview {
    NavigationStack {
        ItineraryDetailView(itinerary: ItineraryResponse(
            id: 1,
            title: "Summer in Halifax",
            traveler_id: 1,
            traveler_name: "Jesse",
            start_date: "2026-08-01",
            end_date: "2026-08-08",
            travelers: "Jesse, Sophie",
            notes: nil,
            status: "planning",
            group_id: nil,
            created_at: nil
        ))
    }
    .environment(APIService())
    .environment(AuthService())
    .environment(HouseholdService())
}
