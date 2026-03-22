import SwiftUI

enum CalendarDisplayMode: String, CaseIterable {
    case month = "Month"
    case week = "Week"
}

struct CalendarView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(APIService.self) private var api
    @State private var viewModel = CalendarViewModel()
    @State private var showingAddAppointment = false
    @State private var appointmentToEdit: AppointmentResponse?
    @State private var displayMode: CalendarDisplayMode = .month

    private let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        VStack(spacing: 0) {
            // Header: nav + mode picker
            headerBar

            Picker("View", selection: $displayMode) {
                ForEach(CalendarDisplayMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, DesignTokens.Spacing.rowVertical)

            switch displayMode {
            case .month:
                monthView
            case .week:
                WeekView(
                    weekStart: currentWeekStart,
                    selectedDate: $viewModel.selectedDate,
                    appointments: viewModel.monthAppointments
                )
            }
        }
        .background { AmbientBackground(style: .calendar) }
        .navigationTitle("Calendar")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAddAppointment = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddAppointment) {
            AddAppointmentView { appointment in
                Task { await viewModel.addAppointment(appointment, api: api) }
            }
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
        .task {
            await viewModel.loadMonth(api: api)
        }
        .onChange(of: viewModel.displayedMonth) {
            Task { await viewModel.loadMonth(api: api) }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Button { viewModel.previousMonth() } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
            }
            Spacer()
            Text(viewModel.monthYearString)
                .font(.title2.bold())
            Spacer()
            Button { viewModel.nextMonth() } label: {
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.semibold))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, DesignTokens.Spacing.cardGap)
    }

    // MARK: - Month View

    private var monthView: some View {
        VStack(spacing: 0) {
            // Weekday headers
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 0) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, DesignTokens.Spacing.rowVertical)

            // Calendar grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) {
                ForEach(viewModel.calendarDays, id: \.id) { day in
                    CalendarDayCell(
                        day: day,
                        isSelected: viewModel.selectedDate == day.date,
                        appointmentCount: viewModel.appointmentCount(for: day.date)
                    )
                    .onTapGesture {
                        if day.isCurrentMonth {
                            viewModel.selectedDate = day.date
                        }
                    }
                }
            }
            .padding(.horizontal)

            Divider()
                .padding(.top, DesignTokens.Spacing.cardGap)

            // Selected day appointments
            selectedDayDetail
        }
    }

    @ViewBuilder
    private var selectedDayDetail: some View {
        if let selected = viewModel.selectedDate {
            let dayAppointments = viewModel.appointments(for: selected)
            if dayAppointments.isEmpty {
                ContentUnavailableView {
                    Label("No Appointments", systemImage: "calendar.badge.plus")
                } description: {
                    Text(viewModel.selectedDateString)
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    Section(viewModel.selectedDateString) {
                        ForEach(dayAppointments) { appt in
                            Button {
                                appointmentToEdit = appt
                            } label: {
                                AppointmentListRow(appointment: appt)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { await viewModel.deleteAppointment(appt.id, api: api) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    appointmentToEdit = appt
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    await viewModel.loadMonth(api: api)
                }
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

    var body: some View {
        VStack(spacing: 4) {
            if let date = day.date {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.subheadline.weight(day.isToday ? .bold : .regular))
                    .foregroundStyle(foregroundColor)

                HStack(spacing: 2) {
                    ForEach(0..<min(appointmentCount, 3), id: \.self) { _ in
                        Circle()
                            .fill(.purple)
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(height: 6)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 10)
                    .fill(TabAccent.calendar.color.opacity(DesignTokens.Opacity.badgeFill)) // DS-05: replaced raw opacity fill
            } else if day.isToday {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.teal, lineWidth: 1.5)
            }
        }
        .opacity(day.isCurrentMonth ? 1 : 0.3)
    }

    private var foregroundColor: Color {
        if isSelected { return .teal }
        if day.isToday { return .teal }
        return .primary
    }
}

// MARK: - Appointment Row

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
                    if let tags = appointment.person_tags, !tags.isEmpty {
                        Label(tags, systemImage: "person")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var categoryColor: Color {
        switch appointment.category {
        case "medical": .red
        case "school": .blue
        case "daycare": .orange
        case "personal": .purple
        default: .teal
        }
    }
}

#Preview {
    NavigationStack {
        CalendarView()
    }
    .environment(APIService())
}
