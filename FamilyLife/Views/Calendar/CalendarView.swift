import SwiftUI
import CoreLocation

enum CalendarDisplayMode: String, CaseIterable {
    case month = "Month"
    case week = "Week"
    case day = "Day"
}

struct CalendarView: View {
    var showsDismissButton = false
    @Environment(\.dismiss) private var dismiss
    @Environment(APIService.self) private var api
    @Environment(CalendarService.self) private var calendarService
    @Environment(AuthService.self) private var auth
    @Environment(LocationService.self) private var locationService
    @Environment(HouseholdService.self) private var household
    @State private var viewModel = CalendarViewModel()
    @State private var showingAddAppointment = false
    @State private var selectedEvent: AppointmentResponse?
    @State private var displayMode: CalendarDisplayMode = .month
    @State private var showingCareCascade = false
    // showingIncomingCoverage removed — incoming handled in combined MyCoverageRequestsView
    @State private var showingMyRequests = false
    @State private var incomingCount = 0
    @State private var myRequestCount = 0

    private let weekdays = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                headerSection
                careRequestBanner
                incomingCoverageBanner
                calendarConnectBanner
                segmentedControl
                ownerFilterBar

                switch displayMode {
                case .month:
                    monthGrid
                    selectedDayEvents
                case .week:
                    WeekView(
                        weekStart: currentWeekStart,
                        viewModel: viewModel
                    )
                    .frame(minHeight: 400)
                case .day:
                    dayView
                }
            }
            .padding(.bottom, DesignTokens.Spacing.bottomBuffer)
        }
        .background { AmbientBackground(style: .calendar) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                AskButlerButton(prompt: "What's coming up this week?")
            }
            if showsDismissButton {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(WarmPalette.ink2)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 8) {
                    GlassIconButton(systemName: "arrow.triangle.swap", accessibilityLabel: "Request coverage") {
                        showingCareCascade = true
                    }
                    GlassIconButton(systemName: "plus", accessibilityLabel: "Add event") {
                        showingAddAppointment = true
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddAppointment) {
            AddAppointmentView(initialDate: viewModel.selectedDate) { appointment, syncToApple in
                Task { await viewModel.addAppointment(appointment, syncToApple: syncToApple, api: api, calendarService: calendarService) }
            }
        }
        .sheet(isPresented: $showingCareCascade) {
            NavigationStack { CareCascadeView() }
        }
        #if DEBUG
        .onAppear { if ScreenshotHarness.openCare { showingCareCascade = true } }
        #endif
        .sheet(isPresented: $showingMyRequests) {
            NavigationStack { MyCoverageRequestsView() }
        }
        .sheet(item: $selectedEvent) { appt in
            NavigationStack {
                EventDetailView(appointment: appt) {
                    await viewModel.loadMonth(api: api)
                }
            }
        }
        .overlay {
            if viewModel.isLoading && viewModel.monthAppointments.isEmpty {
                ProgressView()
            }
        }
        .alert("Something went wrong", isPresented: errorAlertIsPresented) {
            Button("OK") { viewModel.error = nil }
        } message: {
            Text(viewModel.error ?? "An unexpected error occurred.")
        }
        .task {
            calendarService.refreshAuthorizationStatus()
            viewModel.currentUserId = auth.currentUser?.id
            await viewModel.loadMonth(api: api, calendarService: calendarService)
            // Leave-soon travel reminders for upcoming located events (best-effort;
            // only when location is already granted, so we never prompt from here).
            if locationService.authorizationStatus == .authorizedWhenInUse || locationService.authorizationStatus == .authorizedAlways,
               let origin = await locationService.getCurrentLocation() {
                await NotificationService.shared.scheduleTravelReminders(viewModel.monthAppointments, origin: origin)
            }
            incomingCount = ((try? await api.fetchIncomingCoverage()) ?? []).filter { $0.recipient_status == "pending" }.count
            myRequestCount = ((try? await api.fetchCoverageRequests()) ?? []).filter { $0.status == "pending" || $0.status == "approved" }.count
        }
        .onChange(of: viewModel.displayedMonth) {
            Task { await viewModel.loadMonth(api: api, calendarService: calendarService) }
        }
        // The system calendar changed (event added/edited/deleted in another app)
        // — re-read the on-device mirror so this screen reflects it immediately.
        .onChange(of: calendarService.storeVersion) {
            Task { await viewModel.loadExternalEvents(calendarService: calendarService) }
        }
    }

    // MARK: - Owner Filter (Everyone / Just me / per-person)

    /// Other people whose calendars can appear here — driven by the household
    /// group's actual user roster (stable across every month and year), plus
    /// anyone seen in this month's synced events. The roster comes straight
    /// from group membership (`householdUsers`), NOT from contacts filtered by
    /// name — a contact called "Sophie" never matching the group member
    /// "Sophie Chiasson" is what used to make this menu vanish on months
    /// without synced events.
    private var householdOwners: [(id: Int, name: String)] {
        var seen = Set<Int>()
        var out: [(id: Int, name: String)] = []
        for user in household.householdUsers {
            if !seen.contains(user.id) {
                seen.insert(user.id); out.append((id: user.id, name: user.name))
            }
        }
        for ev in viewModel.householdEvents {
            if let id = ev.owner_id, !seen.contains(id) {
                seen.insert(id); out.append((id: id, name: ev.owner_name ?? "Member"))
            }
        }
        return out.sorted { $0.name < $1.name }
    }

    @ViewBuilder
    private var ownerFilterBar: some View {
        if !householdOwners.isEmpty {
            Menu {
                Button { viewModel.ownerFilter = .everyone } label: {
                    Label("Everyone", systemImage: viewModel.ownerFilter == .everyone ? "checkmark" : "person.2")
                }
                Button { viewModel.ownerFilter = .me } label: {
                    Label("Just me", systemImage: viewModel.ownerFilter == .me ? "checkmark" : "person")
                }
                ForEach(householdOwners, id: \.id) { owner in
                    Button { viewModel.ownerFilter = .person(owner.id) } label: {
                        Label(owner.name, systemImage: viewModel.ownerFilter == .person(owner.id) ? "checkmark" : "person")
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 13, weight: .semibold))
                    Text(ownerFilterLabel)
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(WarmPalette.ink2)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(WarmPalette.cream1, in: Capsule())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            .padding(.bottom, 8)
        }
    }

    private var ownerFilterLabel: String {
        switch viewModel.ownerFilter {
        case .everyone: return "Everyone"
        case .me: return "Just me"
        case .person(let id): return householdOwners.first { $0.id == id }?.name ?? "Member"
        }
    }

    // MARK: - Connect Calendar Banner

    @ViewBuilder
    private var calendarConnectBanner: some View {
        switch calendarService.access {
        case .notDetermined:
            Button {
                Task {
                    let granted = await calendarService.requestAccess()
                    if granted { await viewModel.loadMonth(api: api, calendarService: calendarService) }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(AccentTheme.sage.color)
                        .frame(width: 36, height: 36)
                        .background(AccentTheme.sage.color.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show your other calendars")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(WarmPalette.ink1)
                        Text("Bring iCloud and synced Google events into Kinrows")
                            .font(.system(size: 12))
                            .foregroundStyle(WarmPalette.ink3)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WarmPalette.ink4)
                }
                .padding(12)
                .background(WarmPalette.cream1)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            .padding(.bottom, 8)
        case .denied:
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 14))
                    .foregroundStyle(WarmPalette.ink3)
                Text("Enable Calendar access in Settings to see your other calendars here.")
                    .font(.system(size: 12))
                    .foregroundStyle(WarmPalette.ink3)
                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            .padding(.bottom, 8)
        case .granted:
            EmptyView()
        }
    }

    private var errorAlertIsPresented: Binding<Bool> {
        Binding(get: { viewModel.error != nil }, set: { if !$0 { viewModel.error = nil } })
    }

    // MARK: - Care Request Banner

    @ViewBuilder
    private var careRequestBanner: some View {
        if myRequestCount > 0 {
            Button { showingMyRequests = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.swap")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(TabAccent.care.color)
                        .frame(width: 36, height: 36)
                        .background(TabAccent.care.color.opacity(0.15))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your coverage requests")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(WarmPalette.ink1)
                        Text("\(myRequestCount) active request\(myRequestCount == 1 ? "" : "s")")
                            .font(.system(size: 13))
                            .foregroundStyle(WarmPalette.ink3)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WarmPalette.ink4)
                }
                .padding(14)
                .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            .padding(.bottom, 8)
        } else {
            Button { showingCareCascade = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.swap")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(TabAccent.care.color)
                        .frame(width: 36, height: 36)
                        .background(TabAccent.care.color.opacity(0.15))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Need coverage?")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(WarmPalette.ink1)
                        Text("Ask someone to cover a time slot")
                            .font(.system(size: 13))
                            .foregroundStyle(WarmPalette.ink3)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WarmPalette.ink4)
                }
                .padding(14)
                .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private var incomingCoverageBanner: some View {
        if incomingCount > 0 {
            Button { showingMyRequests = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(AccentTheme.sage.color)
                        .frame(width: 36, height: 36)
                        .background(AccentTheme.sage.color.opacity(0.15))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Someone needs your help")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(WarmPalette.ink1)
                        Text("\(incomingCount) pending request\(incomingCount == 1 ? "" : "s")")
                            .font(.system(size: 13))
                            .foregroundStyle(WarmPalette.ink3)
                    }

                    Spacer()

                    Text("Review")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AccentTheme.sage.color)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(AccentTheme.sage.color.opacity(0.12), in: Capsule())
                }
                .padding(14)
                .background(AccentTheme.sage.color.opacity(0.06), in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card).stroke(AccentTheme.sage.color.opacity(0.15), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.monthYearString.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WarmPalette.ink3)
                    .tracking(0.4)
                Text("Calendar")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(WarmPalette.ink1)
            }
            Spacer()
            HStack(spacing: 8) {
                Button { viewModel.previousMonth() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WarmPalette.ink2)
                }
                Button { viewModel.nextMonth() } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WarmPalette.ink2)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 14)
    }

    // MARK: - Segmented Control

    private var segmentedControl: some View {
        HStack(spacing: 0) {
            ForEach(CalendarDisplayMode.allCases, id: \.self) { mode in
                Text(mode.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(displayMode == mode ? WarmPalette.cream1 : WarmPalette.ink2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(displayMode == mode ? WarmPalette.ink1 : .clear)
                    .clipShape(Capsule())
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { displayMode = mode } }
            }
        }
        .padding(4)
        .background(WarmPalette.cardSurface, in: Capsule())
        .padding(.horizontal, 22)
        .padding(.bottom, 8)
    }

    // MARK: - Month Grid

    private var monthGrid: some View {
        VStack(spacing: 0) {
            // Day headers
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 0) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WarmPalette.ink3)
                        .textCase(.uppercase)
                        .tracking(0.4)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 8)

            // Calendar cells
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) {
                ForEach(viewModel.calendarDays, id: \.id) { day in
                    CalendarDayCell(
                        day: day,
                        isSelected: viewModel.selectedDate == day.date,
                        appointmentCount: viewModel.markerCount(for: day.date),
                        hasCoverage: viewModel.hasCoverage(for: day.date)
                    )
                    .onTapGesture {
                        if day.isCurrentMonth { viewModel.selectedDate = day.date }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
        .padding(.bottom, 14)
    }

    // MARK: - Selected Day Events

    @ViewBuilder
    private var selectedDayEvents: some View {
        if let selected = viewModel.selectedDate {
            let dayAppointments = viewModel.appointments(for: selected)
            let dayCoverage = viewModel.coverageBlocks(for: selected)
            let dayExternal = viewModel.externalEvents(for: selected)
            let dayHousehold = viewModel.householdEvents(for: selected)
            let eventCount = dayAppointments.count + dayExternal.count + dayHousehold.count

            WarmSectionHeader(
                title: viewModel.selectedDateString,
                trailing: eventCount == 0 ? nil : "\(eventCount) event\(eventCount == 1 ? "" : "s")"
            )
            .padding(.bottom, 6)

            if !dayCoverage.isEmpty {
                VStack(spacing: 6) {
                    ForEach(dayCoverage) { block in
                        CoverageBlockCard(block: block)
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                .padding(.bottom, 8)
            }

            if dayAppointments.isEmpty && dayCoverage.isEmpty && dayExternal.isEmpty && dayHousehold.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 32))
                        .foregroundStyle(WarmPalette.ink4)
                    Text("No events")
                        .font(.system(size: 15))
                        .foregroundStyle(WarmPalette.ink3)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                VStack(spacing: 10) {
                    ForEach(dayAppointments) { appt in
                        Button { selectedEvent = appt } label: {
                            CalendarEventCard(appointment: appt)
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(dayExternal) { event in
                        ExternalEventCard(event: event)
                    }
                    ForEach(dayHousehold) { event in
                        HouseholdEventCard(event: event, color: colorForOwner(event.owner_id))
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            }
        }
    }

    // MARK: - Day View

    @ViewBuilder
    private var dayView: some View {
        if let selected = viewModel.selectedDate {
            let dayAppointments = viewModel.appointments(for: selected)
            let dayCoverage = viewModel.coverageBlocks(for: selected)
            let dayExternal = viewModel.externalEvents(for: selected)
            let dayHousehold = viewModel.householdEvents(for: selected)
            let eventCount = dayAppointments.count + dayExternal.count + dayHousehold.count

            // Date picker strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(-3..<4, id: \.self) { offset in
                        let date = Calendar.current.date(byAdding: .day, value: offset, to: selected) ?? selected
                        let isThis = Calendar.current.isDate(date, inSameDayAs: selected)
                        Button {
                            viewModel.selectedDate = date
                        } label: {
                            VStack(spacing: 2) {
                                Text(DateFormatter.shortWeekday.string(from: date))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(isThis ? WarmPalette.cream1.opacity(0.7) : WarmPalette.ink3)
                                Text("\(Calendar.current.component(.day, from: date))")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundStyle(isThis ? WarmPalette.cream1 : WarmPalette.ink1)
                            }
                            .frame(width: 44)
                            .padding(.vertical, 10)
                            .background {
                                if isThis {
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(WarmPalette.ink1)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 22)
            }
            .padding(.bottom, 12)

            // Full day header
            WarmSectionHeader(
                title: viewModel.selectedDateString,
                trailing: eventCount == 0 ? nil : "\(eventCount) event\(eventCount == 1 ? "" : "s")"
            )
            .padding(.bottom, 6)

            if !dayCoverage.isEmpty {
                VStack(spacing: 6) {
                    ForEach(dayCoverage) { block in
                        CoverageBlockCard(block: block)
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                .padding(.bottom, 8)
            }

            if dayAppointments.isEmpty && dayCoverage.isEmpty && dayExternal.isEmpty && dayHousehold.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 32))
                        .foregroundStyle(WarmPalette.ink4)
                    Text("No events")
                        .font(.system(size: 15))
                        .foregroundStyle(WarmPalette.ink3)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                VStack(spacing: 10) {
                    ForEach(dayAppointments) { appt in
                        Button { selectedEvent = appt } label: {
                            CalendarEventCard(appointment: appt)
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(dayExternal) { event in
                        ExternalEventCard(event: event)
                    }
                    ForEach(dayHousehold) { event in
                        HouseholdEventCard(event: event, color: colorForOwner(event.owner_id))
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            }
        }
    }

    private var currentWeekStart: Date {
        let cal = Calendar.current
        let date = viewModel.selectedDate ?? Date()
        let weekday = cal.component(.weekday, from: date)
        return cal.date(byAdding: .day, value: -(weekday - 1), to: date) ?? date
    }
}

// MARK: - Day Cell

struct CalendarDayCell: View {
    let day: CalendarDay
    let isSelected: Bool
    let appointmentCount: Int
    var hasCoverage: Bool = false

    private let dotColors: [Color] = [
        AccentTheme.terracotta.color,
        AccentTheme.sage.color,
        Color(hex: "#b97090")
    ]

    private let cellSize: CGFloat = 40

    var body: some View {
        VStack(spacing: 2) {
            if let date = day.date {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(size: 15, weight: day.isToday ? .bold : .medium, design: .default))
                    .foregroundStyle(isSelected ? .white : (day.isToday ? AccentTheme.terracotta.color : WarmPalette.ink1))
                    .frame(width: cellSize, height: cellSize)
                    .background {
                        if isSelected {
                            Circle()
                                .fill(AccentTheme.terracotta.color)
                                .frame(width: cellSize, height: cellSize)
                        } else if hasCoverage {
                            Circle()
                                .fill(AccentTheme.sage.color.opacity(0.15))
                                .frame(width: cellSize, height: cellSize)
                        }
                    }

                HStack(spacing: 2) {
                    if hasCoverage && appointmentCount == 0 {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(AccentTheme.sage.color)
                            .frame(width: 10, height: 4)
                    }
                    ForEach(0..<min(appointmentCount, 3), id: \.self) { i in
                        Circle()
                            .fill(isSelected ? AccentTheme.terracotta.color : dotColors[i % dotColors.count])
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(height: 5)
            } else {
                Spacer().frame(height: cellSize + 7)
            }
        }
        .frame(maxWidth: .infinity)
        .opacity(day.isCurrentMonth ? 1 : 0.3)
    }
}

// MARK: - Event Card

struct CalendarEventCard: View {
    let appointment: AppointmentResponse

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 999)
                .fill(categoryColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(appointment.appointment_time ?? "")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(WarmPalette.ink1)
                    Spacer()
                    HStack(spacing: 4) {
                        if let tags = appointment.person_tags, !tags.isEmpty,
                           !tags.contains("[object") {
                            Text(tags)
                        }
                        if let rule = appointment.recurrence_rule, !rule.isEmpty {
                            Image(systemName: "repeat")
                                .font(.system(size: 11))
                        }
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(WarmPalette.ink3)
                }
                Text(appointment.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WarmPalette.ink1)
                if let location = appointment.location, !location.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin")
                            .font(.system(size: 11))
                        Text(location)
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(WarmPalette.ink3)
                }
            }

            // Attendee avatars (overlapping)
            if let tags = appointment.person_tags, !tags.isEmpty, !tags.contains("[object") {
                let initials = tags.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased() }
                HStack(spacing: -8) {
                    ForEach(Array(initials.enumerated()), id: \.offset) { _, initial in
                        FamilyAvatar(initial: initial, size: 22)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: 20))
    }

    private var categoryColor: Color {
        switch appointment.category {
        case "medical": WarmPalette.bad
        case "school": AccentTheme.ocean.color
        case "daycare": AccentTheme.saffron.color
        case "personal": AccentTheme.mauve.color
        default: TabAccent.calendar.color
        }
    }
}

// MARK: - External Event Card (read-only system calendar event)

struct ExternalEventCard: View {
    let event: ExternalEvent

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 999)
                .fill(event.calendarColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(event.timeString)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(WarmPalette.ink1)
                    Spacer()
                    Text(event.calendarTitle)
                        .font(.system(size: 12))
                        .foregroundStyle(WarmPalette.ink3)
                        .lineLimit(1)
                }
                Text(event.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WarmPalette.ink1)
                if let location = event.location, !location.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin")
                            .font(.system(size: 11))
                        Text(location)
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(WarmPalette.ink3)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(event.calendarColor.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
    }
}

// MARK: - Household Event Card (another member's shared device-calendar event)

private let householdOwnerColors: [Color] = [
    AccentTheme.ocean.color, AccentTheme.mauve.color, AccentTheme.saffron.color,
    AccentTheme.sage.color, Color(hex: "#b97090")
]

func colorForOwner(_ id: Int?) -> Color {
    guard let id else { return WarmPalette.ink3 }
    return householdOwnerColors[abs(id) % householdOwnerColors.count]
}

struct HouseholdEventCard: View {
    let event: APIService.SyncedEventResponse
    let color: Color

    private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    private var timeString: String {
        if (event.all_day ?? 0) == 1 { return "All day" }
        if let d = Self.parser.date(from: event.starts_at) { return DateFormatter.shortTime.string(from: d) }
        return ""
    }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 999)
                .fill(color)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(timeString)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(WarmPalette.ink1)
                    Spacer()
                    HStack(spacing: 5) {
                        FamilyAvatar(initial: String((event.owner_name ?? "?").prefix(1)).uppercased(), size: 18)
                        Text(event.owner_name ?? "")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(color)
                    }
                }
                Text(event.title ?? "(No title)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WarmPalette.ink1)
                if let loc = event.location, !loc.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin").font(.system(size: 11))
                        Text(loc)
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(WarmPalette.ink3)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(color.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Appointment Row (kept for WeekView compatibility)

struct AppointmentListRow: View {
    let appointment: AppointmentResponse

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(categoryColor)
                .frame(width: 4, height: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(appointment.title)
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 8) {
                    if let time = appointment.appointment_time, !time.isEmpty {
                        Label(time, systemImage: "clock")
                    }
                    if let location = appointment.location, !location.isEmpty {
                        Label(location, systemImage: "mappin")
                    }
                }
                .font(.caption)
                .foregroundStyle(WarmPalette.ink3)
            }
            Spacer()
        }
    }

    private var categoryColor: Color {
        switch appointment.category {
        case "medical": WarmPalette.bad
        case "school": AccentTheme.ocean.color
        case "daycare": AccentTheme.saffron.color
        case "personal": AccentTheme.mauve.color
        default: TabAccent.calendar.color
        }
    }
}

// MARK: - Coverage Block Card

struct CoverageBlockCard: View {
    let block: APIService.CoverageBlockResponse

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 999)
                .fill(AccentTheme.sage.color)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(block.approved_start) – \(block.approved_end)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AccentTheme.sage.color)
                    Spacer()
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(AccentTheme.sage.color)
                }
                Text("\(block.helper_name) · \(block.reason) confirmed")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WarmPalette.ink1)
                if let note = block.helper_note, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 13))
                        .foregroundStyle(WarmPalette.ink3)
                }
            }
        }
        .padding(14)
        .background(AccentTheme.sage.color.opacity(0.08), in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                .strokeBorder(AccentTheme.sage.color.opacity(0.2), lineWidth: 1)
        )
    }
}

#Preview {
    NavigationStack {
        CalendarView()
    }
    .environment(APIService())
    .environment(CalendarService())
    .environment(AuthService())
    .environment(LocationService())
    .environment(HouseholdService())
}
