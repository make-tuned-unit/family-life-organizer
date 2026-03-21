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
            self.error = error.localizedDescription
        }
    }

    private func loadTasks(api: APIService) async {
        do {
            activeTasks = try await api.fetchTasks(status: "active")
        } catch {
            // Tasks endpoint may not have data yet
        }
    }

    private func loadTodayAppointments(api: APIService) async {
        do {
            let today = Self.todayString()
            todayAppointments = try await api.fetchAppointments(dateFrom: today, dateTo: today)
        } catch {
            // Appointments endpoint may not have data yet
        }
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
            self.error = error.localizedDescription
        }
    }

    func addTask(_ data: [String: Any], api: APIService) async {
        do {
            try await api.addTask(data)
            await loadAll(api: api)
        } catch {
            self.error = error.localizedDescription
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
            self.error = error.localizedDescription
        }
    }

    private static func todayString() -> String {
        DateFormatter.isoDate.string(from: Date())
    }
}
