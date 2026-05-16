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

    func notifyLocal(title: String, body: String, category: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = String(body.prefix(80))
        content.sound = .default
        content.categoryIdentifier = category

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "\(category.lowercased())-\(UUID().uuidString)", content: content, trigger: trigger)
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

    func notifyNewMessage(from sender: String, text: String, hasImage: Bool = false, userInfo: [String: Any] = [:]) {
        let content = UNMutableNotificationContent()
        content.title = sender
        content.body = hasImage ? "Sent a photo" : String(text.prefix(100))
        content.sound = .default
        content.categoryIdentifier = "MESSAGE"
        if !userInfo.isEmpty { content.userInfo = userInfo }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "dm-\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    /// Update DM watermark without firing notifications (used on app launch)
    func syncWatermark(_ conversations: [APIService.ConversationResponse]) {
        if let maxId = conversations.map(\.id).max() {
            UserDefaults.standard.set(maxId, forKey: "last_seen_dm_id")
        }
    }

    /// Update feed watermark without firing notifications (used on app launch)
    func syncFeedWatermark(_ items: [APIService.ActivityItem]) {
        var seen = notifiedFeedKeys
        for item in items { seen.insert(item.stableKey) }
        saveNotifiedFeedKeys(seen)
    }

    /// Check for new DMs since last check and fire notifications
    func checkForNewMessages(_ conversations: [APIService.ConversationResponse]) {
        var seen = Set(UserDefaults.standard.stringArray(forKey: "notified_dm_ids") ?? [])
        // First launch — mark all current
        if seen.isEmpty {
            seen = Set(conversations.map { String($0.id) })
            UserDefaults.standard.set(Array(seen), forKey: "notified_dm_ids")
            return
        }

        var notified = 0
        for convo in conversations {
            let key = String(convo.id)
            guard !seen.contains(key) else { continue }
            guard convo.unread_count > 0 else { continue }
            guard notified < 3 else { break }
            notifyNewMessage(
                from: convo.partner_name, text: convo.text,
                userInfo: ["type": "message", "ref_id": convo.partner_id, "name": convo.partner_name]
            )
            seen.insert(key)
            notified += 1
        }

        UserDefaults.standard.set(Array(seen), forKey: "notified_dm_ids")
    }

    /// Check feed for new items since last check and fire notifications
    func checkForNewFeedItems(_ items: [APIService.ActivityItem], currentUser: String) {
        var seen = notifiedFeedKeys
        // First launch — mark all current, don't spam
        if seen.isEmpty {
            for item in items { seen.insert(item.stableKey) }
            saveNotifiedFeedKeys(seen)
            return
        }

        var notified = 0
        for item in items {
            guard !seen.contains(item.stableKey) else { continue }
            guard notified < 3 else { break }
            guard item.author?.localizedCaseInsensitiveCompare(currentUser) != .orderedSame else {
                seen.insert(item.stableKey)
                continue
            }

            let author = item.author ?? "Someone"
            let info: [String: Any] = ["type": item.feed_type, "ref_id": item.ref_id]

            switch item.feed_type {
            case "post":
                postLocal(title: "\(author) shared a post", body: String((item.body ?? item.title ?? "").prefix(80)), category: "SOCIAL", userInfo: info)
            case "comment":
                postLocal(title: "\(author) commented", body: item.body ?? "on a post", category: "FEED", userInfo: info)
            case "decision":
                postLocal(title: "\(author) needs your input", body: item.title ?? "New decision", category: "SOCIAL", userInfo: info)
            case "rivalry":
                postLocal(title: "\(author) challenged you", body: item.title ?? "New challenge", category: "SOCIAL", userInfo: info)
            case "event":
                postLocal(title: "New event", body: item.title ?? "", category: "CALENDAR", userInfo: info)
            case "coverage":
                postLocal(title: "\(author) needs coverage", body: item.title ?? "Coverage needed", category: "COVERAGE", userInfo: info)
            default:
                seen.insert(item.stableKey)
                continue
            }
            seen.insert(item.stableKey)
            notified += 1
        }

        saveNotifiedFeedKeys(seen)
    }

    private var notifiedFeedKeys: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: "notified_feed_keys") ?? [])
    }

    private func saveNotifiedFeedKeys(_ keys: Set<String>) {
        // Keep last 200 to prevent unbounded growth
        let trimmed = keys.count > 200 ? Set(keys.suffix(200)) : keys
        UserDefaults.standard.set(Array(trimmed), forKey: "notified_feed_keys")
    }

    // MARK: - Helpers

    private func postLocal(title: String, body: String, category: String, userInfo: [String: Any] = [:]) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = String(body.prefix(100))
        content.sound = .default
        content.categoryIdentifier = category
        if !userInfo.isEmpty { content.userInfo = userInfo }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "\(category.lowercased())-\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

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
