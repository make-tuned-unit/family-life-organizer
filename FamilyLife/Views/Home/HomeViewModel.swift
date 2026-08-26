import Foundation
import SwiftUI

/// Pre-computed display data for a feed card — eliminates per-card work
struct PreparedFeedItem: Identifiable {
    let item: APIService.ActivityItem
    let body: AttributedString?
    let time: String
    let isPost: Bool
    let accentColor: Color
    let isOwnPost: Bool

    var id: String { item.id }
}

@MainActor
@Observable
final class HomeViewModel {
    var summary: APIService.DailySummary?
    var todayAppointments: [AppointmentResponse] = []
    var nextAppointment: AppointmentResponse?
    var weekEventCount: Int = 0
    var monthEventCount: Int = 0
    var activeTasks: [TaskResponse] = []
    var groceries: [GroceryResponse] = []
    var activityFeed: [PreparedFeedItem] = []
    var activeTrips: [TripResponse] = []
    /// Live sleep status for the Home sleep bar. Usually one row; empty for
    /// households with no sleep routine, which is the common case.
    var sleepNow: [SleepNowSummary] = []
    /// Today's chore slots per child, for the Home chore bar. Empty unless the
    /// household keeps a chores routine.
    var choresToday: [ChoresTodaySummary] = []
    var isLoading = false
    var error: String?
    var visibleFeedCount = 15

    static let statColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
    static let mentionRegex = try! NSRegularExpression(pattern: "@[A-Z][a-zA-Z'-]+(?:\\s[A-Z][a-zA-Z'-]+)*")

    private var currentUserName: String?
    private var currentUsername: String?

    func loadAll(api: APIService, userName: String? = nil, username: String? = nil) async {
        currentUserName = userName ?? currentUserName
        currentUsername = username ?? currentUsername
        isLoading = true
        error = nil
        clearStaleDismissals()

        // Cache dismissed IDs once instead of reading UserDefaults per appointment
        let dismissed = dismissedHeroIds

        var firstError: String?
        async let d = Self.safeFetch { try await api.fetchDashboard() }
        async let t = Self.safeFetch { try await api.fetchTasks(status: "active") }
        async let a = Self.safeFetch { try await api.fetchAppointments(dateFrom: Self.todayString(), dateTo: Self.todayString()) }
        async let aWeek = Self.safeFetch { try await api.fetchAppointments(dateFrom: Self.todayString(), dateTo: Self.dateString(daysFromNow: 7)) }
        async let aMonth = Self.safeFetch { try await api.fetchAppointments(dateFrom: Self.todayString(), dateTo: Self.dateString(daysFromNow: 30)) }
        async let f = Self.safeFetch { try await api.fetchActivity() }
        async let tr = Self.safeFetch { try await api.fetchTrips(status: "active") }
        async let sn = Self.safeFetch { try await api.fetchSleepNow() }
        async let ch = Self.safeFetch { try await api.fetchChoresToday() }

        let (dashboard, tasks, appointments, weekAppts, monthAppts, feed, trips, sleep, chores) = await (d, t, a, aWeek, aMonth, f, tr, sn, ch)

        // Batch apply — single re-render
        if let data = dashboard.value {
            summary = data.summary
            groceries = data.groceries
        } else if let e = dashboard.error { firstError = firstError ?? e }

        if let tasks = tasks.value { activeTasks = tasks }
        else if let e = tasks.error { firstError = firstError ?? e }

        if let appointments = appointments.value {
            let now = Date()
            todayAppointments = appointments
                .filter { appt in
                    guard let timeStr = appt.appointment_time,
                          let eventTime = Self.todayDate(from: timeStr) else { return true }
                    return now < eventTime.addingTimeInterval(30 * 60)
                }
                .filter { !dismissed.contains($0.id) }
                .sorted { ($0.appointment_time ?? "") < ($1.appointment_time ?? "") }
        } else if let e = appointments.error { firstError = firstError ?? e }

        weekEventCount = weekAppts.value?.count ?? 0
        monthEventCount = monthAppts.value?.count ?? 0

        // When no events today, surface the next upcoming event from the month
        if todayAppointments.isEmpty {
            let today = Self.todayString()
            let allUpcoming = (monthAppts.value ?? weekAppts.value ?? [])
                .filter { $0.appointment_date > today }
                .sorted { ($0.appointment_date, $0.appointment_time ?? "") < ($1.appointment_date, $1.appointment_time ?? "") }
            nextAppointment = allUpcoming.first
        } else {
            nextAppointment = nil
        }

        if let feed = feed.value { activityFeed = Self.prepareFeed(feed, currentUserName: currentUserName, currentUsername: currentUsername) }
        else if let e = feed.error { firstError = firstError ?? e }

        if let trips = trips.value { activeTrips = trips }

        // A missing sleep routine is not an error worth showing — the bar just
        // doesn't appear. Only replace what we have on a successful fetch, so a
        // dropped request doesn't blank a bar that was correct a moment ago.
        if let sleep = sleep.value { sleepNow = sleep }
        if let chores = chores.value { choresToday = chores }

        error = firstError
        isLoading = false
    }

    func reloadTrips(api: APIService) async {
        do {
            activeTrips = try await api.fetchTrips(status: "active")
        } catch {
            guard !error.isCancellation else { return }
        }
    }

    /// Tick a chore slot from Home. Optimistic flip first so the dot responds
    /// under the finger; the server's answer then settles the row.
    func toggleChore(routineId: Int, choreId: String, slot: String, api: APIService) async {
        guard let rIdx = choresToday.firstIndex(where: { $0.routine_id == routineId }),
              let cIdx = choresToday[rIdx].chores.firstIndex(where: { $0.id == choreId }),
              let sIdx = choresToday[rIdx].chores[cIdx].slots.firstIndex(where: { $0.slot == slot })
        else { return }
        let snapshot = choresToday
        let title = choresToday[rIdx].chores[cIdx].title
        let wasDone = choresToday[rIdx].chores[cIdx].slots[sIdx].done
        choresToday[rIdx].chores[cIdx].slots[sIdx].done = !wasDone
        choresToday[rIdx].open_slots = max(0, choresToday[rIdx].open_slots + (wasDone ? 1 : -1))
        do {
            _ = try await api.toggleChore(routineId: routineId, choreId: choreId, slot: slot)
            choresToday = try await api.fetchChoresToday()
        } catch {
            guard !error.isCancellation else { return }
            choresToday = snapshot
            self.error = "Couldn't update \(title)."
        }
    }

    func reloadChoresToday(api: APIService) async {
        do {
            choresToday = try await api.fetchChoresToday()
        } catch {
            guard !error.isCancellation else { return }
        }
    }

    /// Cheap refresh for the sleep bar — logging a nap in the routine sheet
    /// must show up here without a full Home reload or a pull-to-refresh.
    func reloadSleepNow(api: APIService) async {
        do {
            sleepNow = try await api.fetchSleepNow()
        } catch {
            guard !error.isCancellation else { return }
        }
    }

    /// Cancel an active trip straight from the Home presence chip. Optimistically
    /// drops it from the list; reloads to restore truth on failure.
    func cancelTrip(_ id: Int, api: APIService) async {
        activeTrips.removeAll { $0.id == id }
        NotificationService.shared.clearTripAlertState(tripId: id)
        do {
            try await api.cancelTrip(id: id)
        } catch {
            guard !error.isCancellation else { return }
            await reloadTrips(api: api)
            self.error = error.localizedDescription
        }
    }

    /// Mark an active trip arrived from the Home presence chip.
    func arriveTrip(_ id: Int, api: APIService) async {
        activeTrips.removeAll { $0.id == id }
        NotificationService.shared.clearTripAlertState(tripId: id)
        do {
            try await api.arriveTrip(id: id)
        } catch {
            guard !error.isCancellation else { return }
            await reloadTrips(api: api)
            self.error = error.localizedDescription
        }
    }

    // MARK: - Feed preparation

    static func prepareFeed(_ items: [APIService.ActivityItem], currentUserName: String? = nil, currentUsername: String? = nil) -> [PreparedFeedItem] {
        // Filter out comment/reaction events — those are for notifications only
        items.filter { $0.feed_type != "comment" && $0.feed_type != "reaction" }.map { item in
            let isPost = item.feed_type == "post"
            let accent = accentColor(for: item.feed_type, postType: item.status)
            let body: AttributedString? = if isPost, let text = item.body, !text.isEmpty {
                buildAttributedBody(text, accent: accent)
            } else {
                nil
            }
            let isOwn: Bool = {
                guard let author = item.author else { return false }
                return author.localizedCaseInsensitiveCompare(currentUserName ?? "") == .orderedSame
                    || author.localizedCaseInsensitiveCompare(currentUsername ?? "") == .orderedSame
            }()
            return PreparedFeedItem(
                item: item,
                body: body,
                time: formatRelativeTime(item.created_at),
                isPost: isPost,
                accentColor: accent,
                isOwnPost: isOwn
            )
        }
    }

    private static func buildAttributedBody(_ text: String, accent: Color) -> AttributedString {
        var result = AttributedString(text)
        let nsText = text as NSString
        let matches = mentionRegex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            guard let swiftRange = Range(match.range, in: text),
                  let attrRange = result.range(of: String(text[swiftRange])) else { continue }
            result[attrRange].foregroundColor = UIColor(accent)
            result[attrRange].font = .systemFont(ofSize: 14, weight: .semibold)
        }
        return result
    }

    static func formatRelativeTime(_ dateStr: String?) -> String {
        guard let dateStr,
              let date = ISO8601DateFormatter.flexible.date(from: dateStr) else { return "" }
        return date.formatted(.relative(presentation: .named))
    }

    static func accentColor(for feedType: String, postType: String? = nil) -> Color {
        switch feedType {
        case "decision": TabAccent.decisions.color
        case "event":    TabAccent.calendar.color
        case "coverage": TabAccent.care.color
        case "rivalry":  AccentTheme.saffron.color
        case "post":
            switch postType {
            case "event":             TabAccent.calendar.color
            case "rivalry":           AccentTheme.saffron.color
            case "decision", "poll":  TabAccent.decisions.color
            default:                  AccentTheme.ocean.color
            }
        default:         WarmPalette.ink3
        }
    }

    // MARK: - Data helpers

    struct FetchResult<T> {
        let value: T?
        let error: String?
    }

    private static func safeFetch<T>(_ block: () async throws -> T) async -> FetchResult<T> {
        do { return FetchResult(value: try await block(), error: nil) }
        catch {
            if error.isCancellation { return FetchResult(value: nil, error: nil) }
            return FetchResult(value: nil, error: error.localizedDescription)
        }
    }

    private static func todayDate(from timeStr: String) -> Date? {
        let cal = Calendar.current
        guard let time = DateFormatter.hourMinute.date(from: timeStr) else { return nil }
        let timeComps = cal.dateComponents([.hour, .minute], from: time)
        return cal.date(bySettingHour: timeComps.hour ?? 0, minute: timeComps.minute ?? 0, second: 0, of: Date())
    }

    func completeTask(_ id: Int, api: APIService) async {
        guard let idx = activeTasks.firstIndex(where: { $0.id == id }) else { return }
        let removed = activeTasks.remove(at: idx)
        let previousSummary = summary
        if let s = summary {
            summary = APIService.DailySummary(
                tasks_today: max(0, s.tasks_today - 1),
                active_tasks: s.active_tasks.map { max(0, $0 - 1) },
                appointments_today: s.appointments_today,
                groceries_needed: s.groceries_needed,
                overdue_tasks: s.overdue_tasks,
                pinned_list_name: s.pinned_list_name
            )
        }
        do {
            try await api.completeTask(id: id)
        } catch {
            guard !error.isCancellation else { return }
            activeTasks.insert(removed, at: min(idx, activeTasks.count))
            summary = previousSummary
            self.error = error.localizedDescription
        }
    }

    func addTask(_ data: [String: Any], api: APIService) async {
        // Optimistic: show the task immediately with a temporary id. loadAll()
        // reconciles it with the server row on success; remove it on failure.
        let temp = TaskResponse(
            id: Int.random(in: Int.min ..< 0),
            category: data["category"] as? String ?? "general",
            title: data["title"] as? String ?? "",
            description: data["description"] as? String,
            status: "pending",
            priority: data["priority"] as? String ?? "normal",
            due_date: data["due_date"] as? String,
            due_time: data["due_time"] as? String,
            assigned_to: data["assigned_to"] as? String,
            created_by: nil, recurrence_pattern: nil, tags: nil,
            created_at: nil, updated_at: nil, completed_at: nil
        )
        activeTasks.insert(temp, at: 0)
        do {
            try await api.addTask(data)
            await loadAll(api: api)
        } catch {
            guard !error.isCancellation else { return }
            activeTasks.removeAll { $0.id == temp.id }
            self.error = error.localizedDescription
        }
    }

    private var dismissedHeroIds: Set<Int> {
        get { Set((UserDefaults.standard.array(forKey: "dismissed_hero_ids") as? [Int]) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "dismissed_hero_ids") }
    }

    func dismissHeroCard() {
        if let first = todayAppointments.first {
            var ids = dismissedHeroIds
            ids.insert(first.id)
            dismissedHeroIds = ids
            todayAppointments.removeAll { ids.contains($0.id) }
        }
    }

    private func clearStaleDismissals() {
        let today = Self.todayString()
        let lastClear = UserDefaults.standard.string(forKey: "dismissed_hero_date")
        if lastClear != today {
            UserDefaults.standard.removeObject(forKey: "dismissed_hero_ids")
            UserDefaults.standard.set(today, forKey: "dismissed_hero_date")
        }
    }

    func completeGrocery(_ id: Int, api: APIService) async {
        guard let idx = groceries.firstIndex(where: { $0.id == id }) else { return }
        let removed = groceries.remove(at: idx)
        let previousSummary = summary
        if let s = summary {
            summary = APIService.DailySummary(
                tasks_today: s.tasks_today,
                active_tasks: s.active_tasks,
                appointments_today: s.appointments_today,
                groceries_needed: max(0, s.groceries_needed - 1),
                overdue_tasks: s.overdue_tasks,
                pinned_list_name: s.pinned_list_name
            )
        }
        do {
            try await api.completeGrocery(id: id)
        } catch {
            guard !error.isCancellation else { return }
            groceries.insert(removed, at: min(idx, groceries.count))
            summary = previousSummary
            self.error = error.localizedDescription
        }
    }

    func reloadFeed(api: APIService) async {
        do {
            let items = try await api.fetchActivity()
            activityFeed = Self.prepareFeed(items, currentUserName: currentUserName, currentUsername: currentUsername)
        } catch {
            guard !error.isCancellation else { return }
        }
    }

    private static func todayString() -> String {
        DateFormatter.isoDate.string(from: Date())
    }

    static func dateString(daysFromNow days: Int) -> String {
        DateFormatter.isoDate.string(from: Calendar.current.date(byAdding: .day, value: days, to: Date())!)
    }
}
