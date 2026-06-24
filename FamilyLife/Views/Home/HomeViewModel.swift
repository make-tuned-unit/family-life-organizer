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

    var id: UUID { item.id }
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

        let (dashboard, tasks, appointments, weekAppts, monthAppts, feed, trips) = await (d, t, a, aWeek, aMonth, f, tr)

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
        do {
            try await api.completeTask(id: id)
            activeTasks.removeAll { $0.id == id }
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
        do {
            try await api.completeGrocery(id: id)
            groceries.removeAll { $0.id == id }
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
        } catch {
            guard !error.isCancellation else { return }
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
