import SwiftUI

struct WeekView: View {
    @Environment(APIService.self) private var api
    let weekStart: Date
    @Binding var selectedDate: Date?
    let appointments: [AppointmentResponse]

    private let calendar = Calendar.current

    private var weekDays: [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Day strip
            HStack(spacing: 4) {
                ForEach(weekDays, id: \.self) { day in
                    let isToday = calendar.isDateInToday(day)
                    let isSelected = selectedDate.map { calendar.isDate($0, inSameDayAs: day) } ?? false
                    Button {
                        selectedDate = day
                    } label: {
                        VStack(spacing: 2) {
                            Text(dayName(day))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(isSelected ? WarmPalette.cream1.opacity(0.7) : WarmPalette.ink3)
                            Text("\(calendar.component(.day, from: day))")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(isSelected ? WarmPalette.cream1 : isToday ? AccentTheme.terracotta.color : WarmPalette.ink1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(WarmPalette.ink1)
                            } else if isToday {
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(AccentTheme.terracotta.color, lineWidth: 1.5)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            .padding(.vertical, 8)

            // Agenda for selected day
            if let selected = selectedDate {
                let dayAppts = appointmentsFor(selected)
                if dayAppts.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "calendar.badge.checkmark")
                            .font(.system(size: 28))
                            .foregroundStyle(WarmPalette.ink4)
                        Text("Nothing scheduled")
                            .font(.system(size: 15))
                            .foregroundStyle(WarmPalette.ink3)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(dayAppts.enumerated()), id: \.element.id) { index, appt in
                                if index > 0 { GlassDivider() }
                                WeekAgendaRow(appointment: appt)
                            }
                        }
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                        .padding(.top, 8)
                    }
                }
            }
        }
    }

    private func dayName(_ date: Date) -> String {
        DateFormatter.shortWeekday.string(from: date)
    }

    private func appointmentsFor(_ date: Date) -> [AppointmentResponse] {
        let dateStr = DateFormatter.isoDate.string(from: date)
        return appointments
            .filter { $0.appointment_date == dateStr }
            .sorted { ($0.appointment_time ?? "") < ($1.appointment_time ?? "") }
    }
}

// Renamed to avoid conflict with HomeView's AgendaRow
struct WeekAgendaRow: View {
    let appointment: AppointmentResponse

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 999)
                .fill(categoryColor)
                .frame(width: 4, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(appointment.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WarmPalette.ink1)
                HStack(spacing: 6) {
                    if let time = appointment.appointment_time, !time.isEmpty {
                        Label(time, systemImage: "clock")
                    }
                    if let loc = appointment.location, !loc.isEmpty {
                        Label(loc, systemImage: "mappin")
                    }
                    if let tags = appointment.person_tags, !tags.isEmpty {
                        Label(tags, systemImage: "person")
                    }
                }
                .font(.system(size: 13))
                .foregroundStyle(WarmPalette.ink3)
            }
            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
    }

    private var categoryColor: Color {
        switch appointment.category {
        case "medical": WarmPalette.bad
        case "school": AccentTheme.ocean.color
        case "daycare": AccentTheme.saffron.color
        case "personal": AccentTheme.mauve.color
        default: AccentTheme.terracotta.color
        }
    }
}

// Keep old AgendaRow name for backward compatibility with any remaining references
struct AgendaRow: View {
    let appointment: AppointmentResponse
    var body: some View {
        WeekAgendaRow(appointment: appointment)
    }
}

#Preview {
    ZStack {
        AmbientBackground(style: .calendar)
        WeekView(
            weekStart: Date(),
            selectedDate: .constant(Date()),
            appointments: []
        )
    }
    .environment(APIService())
}
