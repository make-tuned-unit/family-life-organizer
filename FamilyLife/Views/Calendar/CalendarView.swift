import SwiftUI

enum CalendarDisplayMode: String, CaseIterable {
    case month = "Month"
    case week = "Week"
    case day = "Day"
}

struct CalendarView: View {
    var showsDismissButton = false
    @Environment(\.dismiss) private var dismiss
    @Environment(APIService.self) private var api
    @State private var viewModel = CalendarViewModel()
    @State private var showingAddAppointment = false
    @State private var appointmentToEdit: AppointmentResponse?
    @State private var displayMode: CalendarDisplayMode = .month
    @State private var showingCareCascade = false

    private let weekdays = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                headerSection
                careRequestBanner
                segmentedControl

                switch displayMode {
                case .month:
                    monthGrid
                    selectedDayEvents
                case .week:
                    WeekView(
                        weekStart: currentWeekStart,
                        selectedDate: $viewModel.selectedDate,
                        appointments: viewModel.monthAppointments
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
        .toolbar {
            if showsDismissButton {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(WarmPalette.ink2)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 8) {
                    GlassIconButton(systemName: "arrow.triangle.swap") {
                        showingCareCascade = true
                    }
                    GlassIconButton(systemName: "plus") {
                        showingAddAppointment = true
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddAppointment) {
            AddAppointmentView { appointment in
                Task { await viewModel.addAppointment(appointment, api: api) }
            }
        }
        .sheet(isPresented: $showingCareCascade) {
            NavigationStack { CareCascadeView() }
        }
        .sheet(item: $appointmentToEdit) { appt in
            EditAppointmentView(appointment: appt) {
                Task { await viewModel.loadMonth(api: api) }
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
        .task { await viewModel.loadMonth(api: api) }
        .onChange(of: viewModel.displayedMonth) {
            Task { await viewModel.loadMonth(api: api) }
        }
    }

    private var errorAlertIsPresented: Binding<Bool> {
        Binding(get: { viewModel.error != nil }, set: { if !$0 { viewModel.error = nil } })
    }

    // MARK: - Care Request Banner

    private var careRequestBanner: some View {
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
            .glassEffect(.regular.tint(TabAccent.care.color.opacity(0.04)), in: .rect(cornerRadius: DesignTokens.CornerRadius.card))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
        .padding(.bottom, 8)
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
        .glassEffect(.regular.tint(.white.opacity(0.05)), in: .capsule)
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
                        appointmentCount: viewModel.appointmentCount(for: day.date)
                    )
                    .onTapGesture {
                        if day.isCurrentMonth { viewModel.selectedDate = day.date }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 24))
        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
        .padding(.bottom, 14)
    }

    // MARK: - Selected Day Events

    @ViewBuilder
    private var selectedDayEvents: some View {
        if let selected = viewModel.selectedDate {
            let dayAppointments = viewModel.appointments(for: selected)

            WarmSectionHeader(
                title: viewModel.selectedDateString,
                trailing: dayAppointments.isEmpty ? nil : "\(dayAppointments.count) event\(dayAppointments.count == 1 ? "" : "s")"
            )
            .padding(.bottom, 6)

            if dayAppointments.isEmpty {
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
                        Button { appointmentToEdit = appt } label: {
                            CalendarEventCard(appointment: appt)
                        }
                        .buttonStyle(.plain)
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
                trailing: dayAppointments.isEmpty ? nil : "\(dayAppointments.count) event\(dayAppointments.count == 1 ? "" : "s")"
            )
            .padding(.bottom, 6)

            if dayAppointments.isEmpty {
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
                        Button { appointmentToEdit = appt } label: {
                            CalendarEventCard(appointment: appt)
                        }
                        .buttonStyle(.plain)
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
                        }
                    }

                HStack(spacing: 2) {
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
                        if let tags = appointment.person_tags, !tags.isEmpty {
                            Text(tags)
                        }
                        if appointment.category == "recurring" {
                            Text("recurring")
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
            if let tags = appointment.person_tags, !tags.isEmpty {
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
        .glassEffect(.regular.tint(categoryColor.opacity(0.05)), in: .rect(cornerRadius: 20))
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

#Preview {
    NavigationStack {
        CalendarView()
    }
    .environment(APIService())
}
