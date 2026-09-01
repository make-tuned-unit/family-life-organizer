import Foundation
import WidgetKit

/// What the home-screen widget knows about the day ahead. The app writes this
/// snapshot into the App Group whenever it refreshes Home; the widget only
/// renders it — no network, no keychain, no token races. Compiled into BOTH
/// the app and the widget extension.
struct WidgetDaySnapshot: Codable {
    var date: String                 // yyyy-MM-dd, local
    var briefTitle: String?
    var briefBody: String?
    var choresDone: Int
    var choresTotal: Int
    var eventsTodayCount: Int
    var nextEventTitle: String?
    var nextEventTime: String?       // "HH:MM" or display string
    var updatedAt: Date
}

enum WidgetDataStore {
    static let appGroupId = "group.com.kinrows.app"
    static let snapshotKey = "widget_day_snapshot"

    static func load() -> WidgetDaySnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupId),
              let data = defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetDaySnapshot.self, from: data)
    }

    static func save(_ snapshot: WidgetDaySnapshot) {
        guard let defaults = UserDefaults(suiteName: appGroupId),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Sign-out must empty the widget too — it would otherwise keep showing
    /// the previous account's family on the home screen.
    static func clear() {
        UserDefaults(suiteName: appGroupId)?.removeObject(forKey: snapshotKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
