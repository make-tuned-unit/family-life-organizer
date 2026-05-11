import Foundation

@Observable
final class HomeViewModel {
    var summary: APIService.DailySummary?
    var todayAppointments: [AppointmentResponse] = []
    var activeTasks: [TaskResponse] = []
    var groceries: [GroceryResponse] = []
    var isLoading = false
    var error: String?

    func loadAll(api: APIService) async {
        isLoading = true
        error = nil
        clearStaleDismissals()

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadDashboard(api: api) }
            group.addTask { await self.loadTasks(api: api) }
            group.addTask { await self.loadTodayAppointments(api: api) }
        }

        isLoading = false
    }

    private func loadDashboard(api: APIService) async {
        do {
            let data = try await api.fetchDashboard()
            summary = data.summary
            groceries = data.groceries
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }

    private func loadTasks(api: APIService) async {
        do {
            activeTasks = try await api.fetchTasks(status: "active")
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }

    private func loadTodayAppointments(api: APIService) async {
        do {
            let today = Self.todayString()
            let all = try await api.fetchAppointments(dateFrom: today, dateTo: today)
            let now = Date()
            todayAppointments = all
                .filter { appt in
                    // Keep events with no time, or whose time hasn't passed yet
                    guard let timeStr = appt.appointment_time,
                          let eventTime = Self.todayDate(from: timeStr) else {
                        return true
                    }
                    // Give a 30-minute buffer after the event time
                    return now < eventTime.addingTimeInterval(30 * 60)
                }
                .filter { !dismissedHeroIds.contains($0.id) }
                .sorted { ($0.appointment_time ?? "") < ($1.appointment_time ?? "") }
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }

    private static func todayDate(from timeStr: String) -> Date? {
        let cal = Calendar.current
        guard let time = DateFormatter.hourMinute.date(from: timeStr) else { return nil }
        let timeComps = cal.dateComponents([.hour, .minute], from: time)
        return cal.date(bySettingHour: timeComps.hour ?? 0, minute: timeComps.minute ?? 0, second: 0, of: Date())
    }

    func completeTask(_ id: Int, api: APIService) async {
        do {
            try await api.completeTask(id: id)
            activeTasks.removeAll { $0.id == id }
            if let s = summary {
                summary = APIService.DailySummary(
                    tasks_today: max(0, s.tasks_today - 1),
                    appointments_today: s.appointments_today,
                    groceries_needed: s.groceries_needed,
                    overdue_tasks: s.overdue_tasks
                )
            }
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }

    func addTask(_ data: [String: Any], api: APIService) async {
        do {
            try await api.addTask(data)
            await loadAll(api: api)
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }

    private var dismissedHeroIds: Set<Int> {
        get {
            Set((UserDefaults.standard.array(forKey: "dismissed_hero_ids") as? [Int]) ?? [])
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: "dismissed_hero_ids")
        }
    }

    func dismissHeroCard() {
        if let first = todayAppointments.first {
            var ids = dismissedHeroIds
            ids.insert(first.id)
            dismissedHeroIds = ids
            todayAppointments.removeAll { ids.contains($0.id) }
        }
    }

    /// Clear stale dismissed IDs (called on new day)
    private func clearStaleDismissals() {
        let today = Self.todayString()
        let lastClear = UserDefaults.standard.string(forKey: "dismissed_hero_date")
        if lastClear != today {
            UserDefaults.standard.removeObject(forKey: "dismissed_hero_ids")
            UserDefaults.standard.set(today, forKey: "dismissed_hero_date")
        }
    }

    func completeGrocery(_ id: Int, api: APIService) async {
        do {
            try await api.completeGrocery(id: id)
            groceries.removeAll { $0.id == id }
            if let s = summary {
                summary = APIService.DailySummary(
                    tasks_today: s.tasks_today,
                    appointments_today: s.appointments_today,
                    groceries_needed: max(0, s.groceries_needed - 1),
                    overdue_tasks: s.overdue_tasks
                )
            }
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }

    private static func todayString() -> String {
        DateFormatter.isoDate.string(from: Date())
    }
}
