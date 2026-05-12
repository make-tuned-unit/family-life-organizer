import Foundation
import SwiftUI

/// Pre-computed display data for a feed card — eliminates per-card .task work
struct PreparedFeedItem: Identifiable {
    let item: APIService.ActivityItem
    let body: AttributedString?
    let time: String
    let isPost: Bool
    let accentColor: Color

    var id: UUID { item.id }
}

@MainActor
@Observable
final class HomeViewModel {
    var summary: APIService.DailySummary?
    var todayAppointments: [AppointmentResponse] = []
    var activeTasks: [TaskResponse] = []
    var groceries: [GroceryResponse] = []
    var activityFeed: [PreparedFeedItem] = []
    var activeTrips: [TripResponse] = []
    var isLoading = false
    var error: String?

    static let statColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    func loadAll(api: APIService) async {
        isLoading = true
        error = nil
        clearStaleDismissals()

        async let d = Self.safeFetch { try await api.fetchDashboard() }
        async let t = Self.safeFetch { try await api.fetchTasks(status: "active") }
        async let a = Self.safeFetch { try await api.fetchAppointments(dateFrom: Self.todayString(), dateTo: Self.todayString()) }
        async let f = Self.safeFetch { try await api.fetchActivity() }
        async let tr = Self.safeFetch { try await api.fetchTrips(status: "active") }

        let (dashboard, tasks, appointments, feed, trips) = await (d, t, a, f, tr)

        if let data = dashboard {
            summary = data.summary
            groceries = data.groceries
        }
        if let tasks { activeTasks = tasks }
        if let appointments {
            let now = Date()
            todayAppointments = appointments
                .filter { appt in
                    guard let timeStr = appt.appointment_time,
                          let eventTime = Self.todayDate(from: timeStr) else { return true }
                    return now < eventTime.addingTimeInterval(30 * 60)
                }
                .filter { !dismissedHeroIds.contains($0.id) }
                .sorted { ($0.appointment_time ?? "") < ($1.appointment_time ?? "") }
        }
        if let feed { activityFeed = Self.prepareFeed(feed) }
        if let trips { activeTrips = trips }

        isLoading = false
    }

    // MARK: - Feed preparation

    private static let mentionRegex = try! NSRegularExpression(pattern: "@[A-Z][a-zA-Z'-]+(?:\\s[A-Z][a-zA-Z'-]+)*")

    static func prepareFeed(_ items: [APIService.ActivityItem]) -> [PreparedFeedItem] {
        items.prefix(10).map { item in
            let isPost = item.feed_type == "post"
            let accent = accentColor(for: item.feed_type)
            let body: AttributedString? = if isPost, let text = item.body, !text.isEmpty {
                buildAttributedBody(text, accent: accent)
            } else {
                nil
            }
            return PreparedFeedItem(
                item: item,
                body: body,
                time: formatRelativeTime(item.created_at),
                isPost: isPost,
                accentColor: accent
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

    private static func accentColor(for feedType: String) -> Color {
        switch feedType {
        case "decision": TabAccent.decisions.color
        case "event":    TabAccent.calendar.color
        case "coverage": TabAccent.care.color
        case "rivalry":  AccentTheme.saffron.color
        case "post":     AccentTheme.ocean.color
        default:         WarmPalette.ink3
        }
    }

    // MARK: - Data helpers

    private static func safeFetch<T>(_ block: () async throws -> T) async -> T? {
        do { return try await block() }
        catch { return nil }
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

    func reloadFeed(api: APIService) async {
        do {
            let items = try await api.fetchActivity()
            activityFeed = Self.prepareFeed(items)
        } catch {
            guard !error.isCancellation else { return }
        }
    }

    private static func todayString() -> String {
        DateFormatter.isoDate.string(from: Date())
    }
}
