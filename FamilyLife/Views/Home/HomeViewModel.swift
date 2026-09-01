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
    var groups: [APIService.GroupResponse] = []
    var presenceMembers: [APIService.PresenceMember] = []
    /// Today's Concierge brief for the dedicated Home section (nil when the
    /// household hasn't opted in or no brief has been written yet).
    var dailyBrief: APIService.DailyBriefPost?
    var isLoading = false
    var error: String?
    var visibleFeedCount = 15

    static let statColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
    static let mentionRegex = try! NSRegularExpression(pattern: "@[A-Z][a-zA-Z'-]+(?:\\s[A-Z][a-zA-Z'-]+)*")

    private var currentUserName: String?
    private var currentUsername: String?

    func loadAll(api: APIService, userId: Int? = nil, userName: String? = nil, username: String? = nil) async {
        currentUserName = userName ?? currentUserName
        currentUsername = username ?? currentUsername
        error = nil
        clearStaleDismissals()

        let dismissed = dismissedHeroIds
        if let userId, let cached = HomeDiskCache.load(userId: userId) {
            applyBootstrap(cached, dismissed: dismissed)
            isLoading = false
        } else {
            isLoading = true
        }

        do {
            let home = try await api.fetchHome()
            applyBootstrap(home, dismissed: dismissed)
            if let userId { HomeDiskCache.save(home, userId: userId) }
        } catch let fetchError {
            if fetchError.isNotModified {
                // ETag matched — keep the disk snapshot already on screen.
            } else if !fetchError.isCancellation {
                if summary == nil { self.error = fetchError.localizedDescription }
            }
        }
        isLoading = false
    }

    private func applyBootstrap(_ home: APIService.HomeBootstrap, dismissed: Set<Int>) {
        summary = home.summary
        groceries = home.groceries
        activeTasks = home.tasks
        groups = home.groups
        presenceMembers = home.presence

        let now = Date()
        todayAppointments = home.appointments_today
            .filter { appt in
                guard let timeStr = appt.appointment_time,
                      let eventTime = Self.todayDate(from: timeStr) else { return true }
                return now < eventTime.addingTimeInterval(30 * 60)
            }
            .filter { !dismissed.contains($0.id) }
            .sorted { ($0.appointment_time ?? "") < ($1.appointment_time ?? "") }

        weekEventCount = home.week_event_count
        monthEventCount = home.month_event_count
        nextAppointment = todayAppointments.isEmpty ? home.next_appointment : nil

        activityFeed = Self.prepareFeed(home.feed, currentUserName: currentUserName, currentUsername: currentUsername)
        activeTrips = home.trips
        sleepNow = home.sleep
        choresToday = home.chores
        dailyBrief = home.daily_brief
        publishWidgetSnapshot(home)
    }

    /// Every Home refresh republishes the day-ahead snapshot the home-screen
    /// widget renders — the widget itself never talks to the network.
    private func publishWidgetSnapshot(_ home: APIService.HomeBootstrap) {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let choresTotal = home.chores.reduce(0) { $0 + $1.total_slots }
        let choresOpen = home.chores.reduce(0) { $0 + $1.open_slots }
        let next = home.appointments_today
            .sorted { ($0.appointment_time ?? "") < ($1.appointment_time ?? "") }
            .first
        WidgetDataStore.save(WidgetDaySnapshot(
            date: fmt.string(from: Date()),
            briefTitle: home.daily_brief?.title,
            briefBody: home.daily_brief?.body,
            choresDone: max(0, choresTotal - choresOpen),
            choresTotal: choresTotal,
            eventsTodayCount: home.appointments_today.count,
            nextEventTitle: next?.title,
            nextEventTime: next?.appointment_time.map { String($0.prefix(5)) },
            updatedAt: Date()
        ))
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
            case "brief":             AccentTheme.saffron.color
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
}

// Stale-while-revalidate Home payload — namespaced per signed-in user so a
// second account on the same device never reads the first account's feed.
enum HomeDiskCache {
    private static let schemaVersion = 1

    private struct Envelope: Codable {
        let schema_version: Int
        let saved_at: String
        let payload: APIService.HomeBootstrap
    }

    static func load(userId: Int) -> APIService.HomeBootstrap? {
        guard let url = fileURL(userId: userId),
              let data = try? Data(contentsOf: url),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.schema_version == schemaVersion else { return nil }
        return envelope.payload
    }

    static func save(_ payload: APIService.HomeBootstrap, userId: Int) {
        guard let url = fileURL(userId: userId) else { return }
        let envelope = Envelope(
            schema_version: schemaVersion,
            saved_at: ISO8601DateFormatter().string(from: Date()),
            payload: payload
        )
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func clearAll() {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("home", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
    }

    private static func fileURL(userId: Int) -> URL? {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("home", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(userId).json")
    }
}
