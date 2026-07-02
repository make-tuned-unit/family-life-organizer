import Foundation
import SwiftUI
import EventKit

/// A single event read from the device's system calendars (iCloud, Exchange,
/// and — if the user has synced their Google account in Settings → Calendar —
/// Google Calendar). Read-only mirror; we never mutate the user's calendars here.
struct ExternalEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let location: String?
    let calendarTitle: String
    let calendarColor: Color

    /// "9:30 AM" for timed events, "All day" otherwise.
    var timeString: String {
        isAllDay ? "All day" : DateFormatter.shortTime.string(from: startDate)
    }
}

/// How Kinrows appointments are written into the device's Apple Calendar.
enum AppleCalendarSyncMode: String, CaseIterable, Identifiable {
    case off, ask, always
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .off: "Off"
        case .ask: "Ask each time"
        case .always: "Always sync"
        }
    }
    static let storageKey = "appleCalendarSyncMode"
}

/// EventKit-backed bridge to the system calendar. On-device only — these events
/// are not synced to the Kinrows backend or visible on the web app.
@MainActor
@Observable
final class CalendarService {
    enum Access: Equatable {
        case notDetermined, granted, denied
    }

    var access: Access = .notDetermined

    /// Bumped whenever iOS reports the system calendar database changed (an
    /// event added, edited or deleted in any app — Calendar, iCal via iCloud,
    /// Google sync). Views observe this to re-read the mirror, and the app
    /// re-syncs to the household so the backend reflects the change.
    private(set) var storeVersion = 0
    @ObservationIgnored private var storeChangeObserver: (any NSObjectProtocol)?

    private let store = EKEventStore()

    /// Local map: Kinrows appointment id -> the EKEvent identifier we created for
    /// it on THIS device. Write-back is inherently per-device, so this stays local.
    private static let mapKey = "kinrowsAppleEventMap"
    private var eventMap: [String: String] = [:]

    // MARK: - Calendar sharing settings (which device calendars sync to the household)

    private static let shareEnabledKey = "calendarShareEnabled"
    private static let sharedIDsKey = "calendarSharedIDs"

    /// Master switch for uploading this device's calendar to the household.
    var shareEnabled: Bool {
        didSet { UserDefaults.standard.set(shareEnabled, forKey: Self.shareEnabledKey) }
    }

    /// Calendar identifiers the user has opted to share.
    var sharedCalendarIDs: Set<String> {
        didSet { UserDefaults.standard.set(Array(sharedCalendarIDs), forKey: Self.sharedIDsKey) }
    }

    private static let syncDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"  // local time, no tz — matches backend month filtering
        return f
    }()

    init() {
        shareEnabled = UserDefaults.standard.bool(forKey: Self.shareEnabledKey)
        sharedCalendarIDs = Set(UserDefaults.standard.stringArray(forKey: Self.sharedIDsKey) ?? [])
        if let stored = UserDefaults.standard.dictionary(forKey: Self.mapKey) as? [String: String] {
            eventMap = stored
        }
        refreshAuthorizationStatus()
        // A long-lived EKEventStore serves a stale snapshot after external edits —
        // deleting one event in Apple Calendar could make unrelated events vanish
        // from our reads (and then from the household sync) for the rest of the
        // session. Refresh the store on every system change notification.
        storeChangeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.store.refreshSourcesIfNecessary()
                self.storeVersion += 1
            }
        }
    }

    private func persistMap() {
        UserDefaults.standard.set(eventMap, forKey: Self.mapKey)
    }

    /// Identifiers of events Kinrows itself wrote — used to keep them from
    /// appearing twice (once as a Kinrows appointment, once via the read mirror).
    private var managedIdentifiers: Set<String> { Set(eventMap.values) }

    func refreshAuthorizationStatus() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            access = .granted
        case .notDetermined:
            access = .notDetermined
        default:
            // .denied, .restricted, and write-only all mean we can't read events.
            access = .denied
        }
    }

    /// Prompts for full calendar access. Returns true if granted.
    func requestAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToEvents()
            access = granted ? .granted : .denied
            return granted
        } catch {
            access = .denied
            return false
        }
    }

    /// Events overlapping [start, end) across all readable calendars, excluding
    /// events Kinrows wrote itself (those already show as Kinrows appointments).
    /// Runs the query off the main actor — EKEventStore reads are thread-safe.
    func events(from start: Date, to end: Date) async -> [ExternalEvent] {
        guard access == .granted else { return [] }
        let store = self.store
        let managed = managedIdentifiers
        return await Task.detached {
            store.refreshSourcesIfNecessary()
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
            return store.events(matching: predicate).compactMap { ev -> ExternalEvent? in
                let identifier = ev.eventIdentifier ?? UUID().uuidString
                if managed.contains(identifier) { return nil }
                let cgColor = ev.calendar.cgColor
                return ExternalEvent(
                    id: identifier,
                    title: ev.title ?? "(No title)",
                    startDate: ev.startDate,
                    endDate: ev.endDate,
                    isAllDay: ev.isAllDay,
                    location: ev.location,
                    calendarTitle: ev.calendar.title,
                    calendarColor: cgColor != nil ? Color(cgColor: cgColor!) : .gray
                )
            }
        }.value
    }

    // MARK: - Write-back

    /// Creates an EKEvent in the user's default calendar for a Kinrows appointment
    /// and records the mapping. Requests access first if needed. No-op without access.
    func syncCreate(appointmentId: Int, fields: [String: Any]) async {
        guard await ensureAccess() else { return }
        guard let calendar = store.defaultCalendarForNewEvents else { return }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        apply(fields, to: event)
        do {
            // A new event always uses .thisEvent — the recurrence rule (if any)
            // creates the series; .futureEvents would make save throw.
            try store.save(event, span: .thisEvent, commit: true)
            if let id = event.eventIdentifier {
                eventMap[String(appointmentId)] = id
                persistMap()
            }
        } catch {
            // Best-effort: a failed write shouldn't block the Kinrows appointment.
        }
    }

    /// Updates the mapped EKEvent for an appointment. If `shouldSync` is true and
    /// no event exists yet, one is created; if false, any existing event is removed.
    func syncUpdate(appointmentId: Int, fields: [String: Any], shouldSync: Bool) async {
        let key = String(appointmentId)
        if !shouldSync {
            await syncDelete(appointmentId: appointmentId)
            return
        }
        guard await ensureAccess() else { return }
        guard let identifier = eventMap[key], let event = store.event(withIdentifier: identifier) else {
            await syncCreate(appointmentId: appointmentId, fields: fields)
            return
        }
        apply(fields, to: event)
        try? store.save(event, span: spanFor(fields), commit: true)
    }

    /// Removes the mapped EKEvent for an appointment, if any.
    func syncDelete(appointmentId: Int) async {
        let key = String(appointmentId)
        guard let identifier = eventMap[key] else { return }
        if await ensureAccess(), let event = store.event(withIdentifier: identifier) {
            try? store.remove(event, span: spanFor(forKey: identifier), commit: true)
        }
        eventMap[key] = nil
        persistMap()
    }

    /// True if this appointment currently has a mirrored Apple Calendar event.
    func isSynced(appointmentId: Int) -> Bool {
        eventMap[String(appointmentId)] != nil
    }

    private func ensureAccess() async -> Bool {
        if access == .granted { return true }
        if access == .notDetermined { return await requestAccess() }
        return false
    }

    // MARK: - Field mapping

    private func apply(_ fields: [String: Any], to event: EKEvent) {
        event.title = (fields["title"] as? String) ?? "(No title)"
        event.location = fields["location"] as? String
        event.notes = fields["description"] as? String
        let (start, end, allDay) = dates(from: fields)
        event.isAllDay = allDay
        event.startDate = start
        event.endDate = end
        event.recurrenceRules = recurrenceRules(from: fields)
    }

    private func dates(from fields: [String: Any]) -> (Date, Date, Bool) {
        let calendar = Calendar.current
        let dateStr = (fields["appointment_date"] as? String) ?? ""
        let day = DateFormatter.isoDate.date(from: dateStr) ?? Date()
        if let timeStr = fields["appointment_time"] as? String, !timeStr.isEmpty,
           let time = DateFormatter.hourMinute.date(from: timeStr) {
            let tc = calendar.dateComponents([.hour, .minute], from: time)
            let start = calendar.date(bySettingHour: tc.hour ?? 9, minute: tc.minute ?? 0, second: 0, of: day) ?? day
            let end = calendar.date(byAdding: .hour, value: 1, to: start) ?? start
            return (start, end, false)
        }
        let start = calendar.startOfDay(for: day)
        return (start, start, true)
    }

    private func recurrenceRules(from fields: [String: Any]) -> [EKRecurrenceRule]? {
        guard let raw = fields["recurrence_rule"] as? String,
              let rule = RecurrenceRule(rawValue: raw), rule != .none else { return nil }
        let frequency: EKRecurrenceFrequency
        var interval = 1
        switch rule {
        case .daily: frequency = .daily
        case .weekly: frequency = .weekly
        case .biweekly: frequency = .weekly; interval = 2
        case .monthly: frequency = .monthly
        case .yearly: frequency = .yearly
        case .none: return nil
        }
        var end: EKRecurrenceEnd?
        if let endStr = fields["recurrence_end"] as? String, let endDate = DateFormatter.isoDate.date(from: endStr) {
            end = EKRecurrenceEnd(end: endDate)
        }
        return [EKRecurrenceRule(recurrenceWith: frequency, interval: interval, end: end)]
    }

    private func spanFor(_ fields: [String: Any]) -> EKSpan {
        recurrenceRules(from: fields) != nil ? .futureEvents : .thisEvent
    }

    private func spanFor(forKey identifier: String) -> EKSpan {
        guard let event = store.event(withIdentifier: identifier) else { return .thisEvent }
        return (event.recurrenceRules?.isEmpty == false) ? .futureEvents : .thisEvent
    }

    // MARK: - Sharing to household

    struct DeviceCalendar: Identifiable {
        let id: String
        let title: String
        let color: Color
    }

    /// All event calendars on the device — for the share picker.
    func availableCalendars() -> [DeviceCalendar] {
        guard access == .granted else { return [] }
        return store.calendars(for: .event)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .map { cal in
                let cg = cal.cgColor
                return DeviceCalendar(id: cal.calendarIdentifier, title: cal.title,
                                      color: cg != nil ? Color(cgColor: cg!) : .gray)
            }
    }

    /// Uploads the user's selected calendars to the household for a rolling window
    /// (1 month back → 3 months ahead). No-op unless sharing is on and granted.
    func syncToHousehold(api: APIService) async {
        guard shareEnabled, access == .granted, !sharedCalendarIDs.isEmpty else { return }
        let cal = Calendar.current
        let now = Date()
        let start = cal.date(byAdding: .month, value: -1, to: cal.startOfDay(for: now)) ?? now
        let end = cal.date(byAdding: .month, value: 3, to: cal.startOfDay(for: now)) ?? now
        let events = await collectEventsForSync(from: start, to: end)
        let fmt = Self.syncDateFormatter
        try? await api.syncCalendarEvents(events: events,
                                          windowStart: fmt.string(from: start),
                                          windowEnd: fmt.string(from: end))
    }

    /// Reads events from the shared calendars and builds the JSON payload off-main.
    private func collectEventsForSync(from start: Date, to end: Date) async -> [[String: Any]] {
        guard !sharedCalendarIDs.isEmpty else { return [] }
        let store = self.store
        let ids = sharedCalendarIDs
        return await Task.detached {
            store.refreshSourcesIfNecessary()
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "en_US_POSIX")
            fmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            let cals = store.calendars(for: .event).filter { ids.contains($0.calendarIdentifier) }
            guard !cals.isEmpty else { return [] }
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: cals)
            return store.events(matching: predicate).map { ev -> [String: Any] in
                [
                    "external_id": ev.eventIdentifier ?? UUID().uuidString,
                    "calendar_name": ev.calendar.title,
                    "title": ev.title ?? "(No title)",
                    "location": ev.location ?? "",
                    "starts_at": fmt.string(from: ev.startDate),
                    "ends_at": fmt.string(from: ev.endDate),
                    "all_day": ev.isAllDay
                ]
            }
        }.value
    }
}
