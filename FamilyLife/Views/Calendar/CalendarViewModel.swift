import Foundation

@Observable
final class CalendarViewModel {
    var displayedMonth: Date = Date()
    var selectedDate: Date?
    var monthAppointments: [AppointmentResponse] = []
    var isLoading = false
    var error: String?

    private let calendar = Calendar.current

    init() {
        selectedDate = calendar.startOfDay(for: Date())
    }

    // MARK: - Computed

    var monthYearString: String {
        DateFormatter.monthYear.string(from: displayedMonth)
    }

    var selectedDateString: String {
        guard let date = selectedDate else { return "" }
        return DateFormatter.longDate.string(from: date)
    }

    var calendarDays: [CalendarDay] {
        let comps = calendar.dateComponents([.year, .month], from: displayedMonth)
        guard let firstOfMonth = calendar.date(from: comps),
              let range = calendar.range(of: .day, in: .month, for: firstOfMonth) else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let leadingEmpty = firstWeekday - 1
        let today = calendar.startOfDay(for: Date())

        var days: [CalendarDay] = []

        // Previous month padding
        if leadingEmpty > 0, let prevMonth = calendar.date(byAdding: .month, value: -1, to: firstOfMonth),
           let prevRange = calendar.range(of: .day, in: .month, for: prevMonth) {
            let prevDays = Array(prevRange)
            for i in (prevDays.count - leadingEmpty)..<prevDays.count {
                let date = calendar.date(bySetting: .day, value: prevDays[i], of: prevMonth)
                days.append(CalendarDay(date: date, isCurrentMonth: false, isToday: false))
            }
        }

        // Current month days
        for day in range {
            guard let date = calendar.date(bySetting: .day, value: day, of: firstOfMonth) else { continue }
            let startOfDate = calendar.startOfDay(for: date)
            days.append(CalendarDay(date: startOfDate, isCurrentMonth: true, isToday: startOfDate == today))
        }

        // Trailing padding to complete the grid
        let trailing = (7 - days.count % 7) % 7
        if trailing > 0, let nextMonth = calendar.date(byAdding: .month, value: 1, to: firstOfMonth) {
            for day in 1...trailing {
                let date = calendar.date(bySetting: .day, value: day, of: nextMonth)
                days.append(CalendarDay(date: date, isCurrentMonth: false, isToday: false))
            }
        }

        return days
    }

    // MARK: - Data

    func appointmentCount(for date: Date?) -> Int {
        guard let date else { return 0 }
        let dateStr = Self.dateString(from: date)
        return monthAppointments.filter { $0.appointment_date == dateStr }.count
    }

    func appointments(for date: Date) -> [AppointmentResponse] {
        let dateStr = Self.dateString(from: date)
        return monthAppointments
            .filter { $0.appointment_date == dateStr }
            .sorted { ($0.appointment_time ?? "") < ($1.appointment_time ?? "") }
    }

    // MARK: - Navigation

    func previousMonth() {
        displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
    }

    func nextMonth() {
        displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
    }

    // MARK: - API

    func loadMonth(api: APIService) async {
        isLoading = true
        error = nil
        let year = calendar.component(.year, from: displayedMonth)
        let month = calendar.component(.month, from: displayedMonth)
        do {
            monthAppointments = try await api.fetchAppointmentsByMonth(year: year, month: month)
        } catch is CancellationError {
        } catch {
            monthAppointments = []
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func addAppointment(_ data: [String: Any], api: APIService) async {
        do {
            try await api.addAppointment(data)
            await loadMonth(api: api)
        } catch is CancellationError {
            // View dismissed — ignore
            } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteAppointment(_ id: Int, api: APIService) async {
        do {
            try await api.deleteAppointment(id: id)
            monthAppointments.removeAll { $0.id == id }
        } catch is CancellationError {
            // View dismissed — ignore
            } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Helpers

    static func dateString(from date: Date) -> String {
        DateFormatter.isoDate.string(from: date)
    }
}

struct CalendarDay: Identifiable {
    let id = UUID()
    let date: Date?
    let isCurrentMonth: Bool
    let isToday: Bool
}
