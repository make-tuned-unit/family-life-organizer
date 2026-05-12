import Foundation
import UserNotifications

final class NotificationService {
    static let shared = NotificationService()

    private init() {}

    func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    func ensurePermissionIfNeeded() async -> Bool {
        if await isAuthorized() {
            return true
        }
        return await requestPermission()
    }

    // MARK: - Appointment reminders

    func scheduleAppointmentReminder(id: Int, title: String, date: String, time: String?) {
        let content = UNMutableNotificationContent()
        content.title = "Upcoming Appointment"
        content.body = title
        content.sound = .default
        content.categoryIdentifier = "APPOINTMENT"

        guard let triggerDate = parseDateTime(date: date, time: time, minutesBefore: 60) else { return }
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(identifier: "appt-\(id)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Pantry expiry alerts

    func schedulePantryExpiryAlert(id: Int, itemName: String, expiryDate: String) {
        let content = UNMutableNotificationContent()
        content.title = "Item Expiring Soon"
        content.body = "\(itemName) expires tomorrow"
        content.sound = .default
        content.categoryIdentifier = "PANTRY_EXPIRY"

        // Alert day before expiry at 9 AM
        guard let triggerDate = parseDateTime(date: expiryDate, time: "09:00", minutesBefore: 24 * 60) else { return }
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(identifier: "pantry-\(id)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Trip notifications

    func notifyTripStarted(traveler: String, destination: String) {
        let content = UNMutableNotificationContent()
        content.title = "Trip Started"
        content.body = "\(traveler) is on the way to \(destination)"
        content.sound = .default
        content.categoryIdentifier = "TRIP"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "trip-start-\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func notifyTripArrival(traveler: String, destination: String) {
        let content = UNMutableNotificationContent()
        content.title = "Arrived!"
        content.body = "\(traveler) has arrived at \(destination)"
        content.sound = .default
        content.categoryIdentifier = "TRIP"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "trip-arrive-\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func notifyTripETA(traveler: String, minutes: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Almost There"
        content.body = "\(traveler) is about \(minutes) minutes away"
        content.sound = .default
        content.categoryIdentifier = "TRIP"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "trip-eta-\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func shouldSendTripETAAlert(tripId: Int, minutes: Int) -> Bool {
        let key = tripETAKey(tripId: tripId, minutes: minutes)
        return !UserDefaults.standard.bool(forKey: key)
    }

    func markTripETAAlertSent(tripId: Int, minutes: Int) {
        let key = tripETAKey(tripId: tripId, minutes: minutes)
        UserDefaults.standard.set(true, forKey: key)
    }

    func clearTripAlertState(tripId: Int) {
        [15, 5].forEach { minutes in
            UserDefaults.standard.removeObject(forKey: tripETAKey(tripId: tripId, minutes: minutes))
        }
    }

    // MARK: - Coverage notifications

    func notifyCoverageApproved(helperName: String, date: String, startTime: String, endTime: String) {
        let content = UNMutableNotificationContent()
        content.title = "Coverage Confirmed"
        content.body = "\(helperName) confirmed \(date) from \(startTime) to \(endTime). You can now book your appointments."
        content.sound = .default
        content.categoryIdentifier = "COVERAGE"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "coverage-\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func scheduleCoverageBooked(title: String, date: String, time: String) {
        let content = UNMutableNotificationContent()
        content.title = "Appointment Booked"
        content.body = "\(title) on \(date) at \(time) — covered by your care team"
        content.sound = .default
        content.categoryIdentifier = "COVERAGE"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "coverage-booked-\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Social notifications (posts, comments, likes, mentions)

    func notifyNewPost(author: String, preview: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(author) shared a post"
        content.body = String(preview.prefix(80))
        content.sound = .default
        content.categoryIdentifier = "SOCIAL"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "post-\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func notifyNewComment(author: String, onPost: String, comment: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(author) commented"
        content.body = String(comment.prefix(80))
        content.sound = .default
        content.categoryIdentifier = "SOCIAL"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "comment-\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func notifyNewLike(author: String, onPost: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(author) liked your post"
        content.body = String(onPost.prefix(60))
        content.sound = .default
        content.categoryIdentifier = "SOCIAL"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "like-\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func notifyMention(author: String, inPost: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(author) mentioned you"
        content.body = String(inPost.prefix(80))
        content.sound = .default
        content.categoryIdentifier = "SOCIAL"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "mention-\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func notifyNewDecision(author: String, title: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(author) needs your input"
        content.body = title
        content.sound = .default
        content.categoryIdentifier = "SOCIAL"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "decision-\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func notifyNewRivalry(author: String, title: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(author) challenged you"
        content.body = title
        content.sound = .default
        content.categoryIdentifier = "SOCIAL"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "rivalry-\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func notifyNewEvent(author: String, title: String) {
        let content = UNMutableNotificationContent()
        content.title = "New event"
        content.body = title
        content.sound = .default
        content.categoryIdentifier = "CALENDAR"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "event-new-\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func notifyCoverageRequest(author: String, reason: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(author) needs coverage"
        content.body = reason
        content.sound = .default
        content.categoryIdentifier = "COVERAGE"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "coverage-new-\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    /// Check feed for new items since last check and fire notifications
    func checkForNewFeedItems(_ items: [APIService.ActivityItem], currentUser: String) {
        let lastSeenKey = "last_seen_feed_id"
        let lastSeenId = UserDefaults.standard.string(forKey: lastSeenKey) ?? ""

        // First launch — just mark current state, don't spam notifications
        if lastSeenId.isEmpty {
            if let first = items.first {
                UserDefaults.standard.set(first.stableKey, forKey: lastSeenKey)
            }
            return
        }

        // Max 3 notifications per refresh to avoid overwhelming the user
        var notified = 0
        for item in items {
            guard item.stableKey != lastSeenId else { break }
            guard notified < 3 else { break }
            // Skip own actions
            guard item.author?.localizedCaseInsensitiveCompare(currentUser) != .orderedSame else { continue }

            let author = item.author ?? "Someone"

            switch item.feed_type {
            case "post":
                notifyNewPost(author: author, preview: item.body ?? item.title ?? "")
                if let body = item.body, body.localizedStandardContains("@\(currentUser)") {
                    notifyMention(author: author, inPost: body)
                }
            case "decision":
                notifyNewDecision(author: author, title: item.title ?? "New decision")
            case "rivalry":
                notifyNewRivalry(author: author, title: item.title ?? "New challenge")
            case "event":
                notifyNewEvent(author: author, title: item.title ?? "New event")
            case "coverage":
                notifyCoverageRequest(author: author, reason: item.title ?? "Coverage needed")
            default:
                continue // don't count unknown types
            }
            notified += 1
        }

        if let first = items.first {
            UserDefaults.standard.set(first.stableKey, forKey: lastSeenKey)
        }
    }

    // MARK: - Helpers

    private func parseDateTime(date: String, time: String?, minutesBefore: Int) -> Date? {
        let formatter = time != nil ? DateFormatter.dateTimeMinute : DateFormatter.isoDate
        let dateStr = time != nil ? "\(date) \(time!)" : date
        guard let d = formatter.date(from: dateStr) else { return nil }
        return Calendar.current.date(byAdding: .minute, value: -minutesBefore, to: d)
    }

    func removeAllPending() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    private func tripETAKey(tripId: Int, minutes: Int) -> String {
        "trip_eta_alert_\(tripId)_\(minutes)"
    }
}
