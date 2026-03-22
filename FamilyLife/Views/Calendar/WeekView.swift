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
            // Day headers
            HStack(spacing: 0) {
                ForEach(weekDays, id: \.self) { day in
                    let isToday = calendar.isDateInToday(day)
                    let isSelected = selectedDate.map { calendar.isDate($0, inSameDayAs: day) } ?? false
                    Button {
                        selectedDate = day
                    } label: {
                        VStack(spacing: 4) {
                            Text(dayName(day))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                            Text("\(calendar.component(.day, from: day))")
                                .font(.subheadline.weight(isToday ? .bold : .regular))
                                .foregroundStyle(isSelected ? .white : isToday ? .teal : .primary)
                                .frame(width: 30, height: 30)
                                .background {
                                    if isSelected {
                                        Circle().fill(.teal)
                                    } else if isToday {
                                        Circle().stroke(.teal, lineWidth: 1.5)
                                    }
                                }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, DesignTokens.Spacing.rowVertical)

            Divider()

            // Agenda for selected day
            if let selected = selectedDate {
                let dayAppts = appointmentsFor(selected)
                if dayAppts.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "calendar.badge.checkmark")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("Nothing scheduled")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(dayAppts) { appt in
                            AgendaRow(appointment: appt)
                        }
                    }
                    .listStyle(.plain)
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

struct AgendaRow: View {
    let appointment: AppointmentResponse

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(categoryColor)
                .frame(width: 4, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(appointment.title)
                    .font(.subheadline.weight(.medium))
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
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, DesignTokens.Spacing.chipVerticalPadding)
    }

    private var categoryColor: Color {
        switch appointment.category {
        case "medical": .red
        case "school": .blue
        case "daycare": .orange
        default: .teal
        }
    }
}

#Preview {
    WeekView(
        weekStart: Date(),
        selectedDate: .constant(Date()),
        appointments: []
    )
    .environment(APIService())
}
