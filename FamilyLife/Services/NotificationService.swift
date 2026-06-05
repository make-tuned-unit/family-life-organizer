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
        content.title = "In 1 hour: \(title)"
        content.body = time != nil ? "Your appointment is at \(time!). Time to get ready." : "Your appointment is coming up soon."
        content.sound = .default
        content.categoryIdentifier = "APPOINTMENT"

        guard let triggerDate = parseDateTime(date: date, time: time, minutesBefore: 60) else { return }
        guard triggerDate > Date() else {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["appt-\(id)"])
            return
        }
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(identifier: "appt-\(id)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Pantry expiry alerts

    func schedulePantryExpiryAlert(id: Int, itemName: String, expiryDate: String) {
        let content = UNMutableNotificationContent()
        content.title = "Heads up — \(itemName) expires tomorrow"
        content.body = "Use it tonight or pop it in the freezer before it goes to waste."
        content.sound = .default
        content.categoryIdentifier = "PANTRY_EXPIRY"

        // Alert day before expiry at 9 AM
        guard let triggerDate = parseDateTime(date: expiryDate, time: "09:00", minutesBefore: 24 * 60) else { return }
        guard triggerDate > Date() else {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["pantry-\(id)"])
            return
        }
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(identifier: "pantry-\(id)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Trip notifications

    func notifyTripStarted(traveler: String, destination: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(traveler) is heading out"
        content.body = "On the way to \(destination). You'll get updates along the way."
        content.sound = .default
        content.categoryIdentifier = "TRIP"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "trip-start-\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func notifyTripArrival(traveler: String, destination: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(traveler) made it safely"
        content.body = "Arrived at \(destination)."
        content.sound = .default
        content.categoryIdentifier = "TRIP"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "trip-arrive-\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func notifyTripETA(traveler: String, minutes: Int) {
        let content = UNMutableNotificationContent()
        content.title = "\(traveler) is almost there"
        content.body = "About \(minutes) minutes away."
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
        content.title = "You're all set — \(helperName) has you covered"
        content.body = "Confirmed for \(date), \(startTime) to \(endTime). Go ahead and book your appointments."
        content.sound = .default
        content.categoryIdentifier = "COVERAGE"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "coverage-\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func scheduleCoverageBooked(title: String, date: String, time: String) {
        let content = UNMutableNotificationContent()
        content.title = "All booked — \(title)"
        content.body = "\(date) at \(time). Your care team has you covered."
        content.sound = .default
        content.categoryIdentifier = "COVERAGE"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "coverage-booked-\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Social notifications (posts, comments, likes, mentions)

    func notifyNewPost(author: String, preview: String) {
        let content = UNMutableNotificationContent()
        content.title = "New from \(author)"
        content.body = String(preview.prefix(80))
        content.sound = .default
        content.categoryIdentifier = "SOCIAL"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "post-\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func notifyNewComment(author: String, onPost: String, comment: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(author) replied"
        content.body = "\"\(String(comment.prefix(70)))\""
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
        content.title = "\(author) added an event"
        content.body = "\(title) has been added to your calendar."
        content.sound = .default
        content.categoryIdentifier = "CALENDAR"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "event-new-\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func notifyCoverageRequest(author: String, reason: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(author) could use your help"
        content.body = reason.isEmpty ? "Can you help cover?" : reason
        content.sound = .default
        content.categoryIdentifier = "COVERAGE"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "coverage-new-\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func notifyNewMessage(from sender: String, text: String, hasImage: Bool = false, userInfo: [String: Any] = [:]) {
        let content = UNMutableNotificationContent()
        content.title = "Message from \(sender)"
        content.body = hasImage ? "Sent you a photo" : String(text.prefix(100))
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
                postLocal(title: "New from \(author)", body: String((item.body ?? item.title ?? "").prefix(80)), category: "SOCIAL", userInfo: info)
            case "comment":
                postLocal(title: "\(author) replied", body: "\"\(item.body ?? "left a comment")\"", category: "FEED", userInfo: info)
            case "decision":
                postLocal(title: "\(author) needs your input", body: item.title ?? "Weigh in on a new decision.", category: "SOCIAL", userInfo: info)
            case "rivalry":
                postLocal(title: "\(author) challenged you", body: item.title ?? "A new challenge is waiting.", category: "SOCIAL", userInfo: info)
            case "event":
                postLocal(title: "\(author) added an event", body: "\(item.title ?? "A new event") has been added to your calendar.", category: "CALENDAR", userInfo: info)
            case "coverage":
                postLocal(title: "\(author) could use your help", body: item.title ?? "Can you help cover?", category: "COVERAGE", userInfo: info)
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

    // MARK: - Rivalry milestone reminders

    /// Schedule local notifications for active rivalry milestones (halfway, 1-day-left, daily nudge at 9am).
    /// Call whenever rivalries are loaded/refreshed. Idempotent — removes stale rivalry notifications first.
    func scheduleRivalryMilestones(_ rivalries: [RivalryResponse], myName: String, entriesByRivalry: [Int: [RivalryEntryResponse]]) {
        // Remove any previously scheduled rivalry reminders
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests.filter { $0.identifier.hasPrefix("rivalry-milestone-") }.map(\.identifier)
            if !ids.isEmpty {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
            }
        }

        let now = Date()
        let calendar = Calendar.current

        for rivalry in rivalries {
            guard rivalry.status == RivalryStatus.active.rawValue || rivalry.status == RivalryStatus.pending.rawValue else { continue }
            guard let endDate = rivalry.endDate, endDate > now else { continue }
            let startDate = ISO8601DateFormatter.flexible.date(from: rivalry.start_date)
                ?? DateFormatter.isoDate.date(from: rivalry.start_date)
                ?? now

            let entries = entriesByRivalry[rivalry.id] ?? []
            let myTotal = entries.filter { $0.member_name.localizedCaseInsensitiveCompare(myName) == .orderedSame }.reduce(0.0) { $0 + $1.value }
            let opponents = rivalry.participantNames.filter { $0.localizedCaseInsensitiveCompare(myName) != .orderedSame }
            let topOpponent = opponents.max { a, b in
                let aTotal = entries.filter { $0.member_name.localizedCaseInsensitiveCompare(a) == .orderedSame }.reduce(0.0) { $0 + $1.value }
                let bTotal = entries.filter { $0.member_name.localizedCaseInsensitiveCompare(b) == .orderedSame }.reduce(0.0) { $0 + $1.value }
                return aTotal < bTotal
            }
            let opTotal = topOpponent.map { name in
                entries.filter { $0.member_name.localizedCaseInsensitiveCompare(name) == .orderedSame }.reduce(0.0) { $0 + $1.value }
            } ?? 0
            let opName = topOpponent ?? "your opponent"

            let scoreStatus: String
            let diff = Int(abs(myTotal - opTotal))
            if myTotal > opTotal {
                scoreStatus = "You're ahead by \(diff)!"
            } else if opTotal > myTotal {
                scoreStatus = "\(opName) leads by \(diff) — time to catch up!"
            } else if myTotal > 0 {
                scoreStatus = "You're tied with \(opName)!"
            } else {
                scoreStatus = "Get moving and take the lead!"
            }

            // 1) Halfway reminder
            let totalDuration = endDate.timeIntervalSince(startDate)
            let halfwayDate = startDate.addingTimeInterval(totalDuration / 2)
            if halfwayDate > now {
                scheduleRivalryNotification(
                    id: "rivalry-milestone-half-\(rivalry.id)",
                    title: "Halfway through \(rivalry.title)!",
                    body: scoreStatus,
                    date: halfwayDate,
                    rivalryId: rivalry.id
                )
            }

            // 2) Last day morning reminder (9am on final day)
            let lastDayStart = calendar.startOfDay(for: endDate)
            if let lastMorning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: lastDayStart),
               lastMorning > now {
                scheduleRivalryNotification(
                    id: "rivalry-milestone-lastday-\(rivalry.id)",
                    title: "Last day of \(rivalry.title)!",
                    body: "Final push! \(scoreStatus)",
                    date: lastMorning,
                    rivalryId: rivalry.id
                )
            }

            // 3) Daily encouragement at 9am (skip today if already past 9am, max 7 days out)
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
            var nudgeDay = tomorrow
            var nudgeCount = 0
            while nudgeDay < endDate && nudgeCount < 7 {
                // Skip the last day (already has its own notification)
                if calendar.isDate(nudgeDay, inSameDayAs: lastDayStart) {
                    nudgeDay = calendar.date(byAdding: .day, value: 1, to: nudgeDay) ?? endDate
                    continue
                }
                if let nudgeTime = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: nudgeDay),
                   nudgeTime > now {
                    let daysLeft = calendar.dateComponents([.day], from: nudgeDay, to: endDate).day ?? 0
                    let messages = [
                        "\(daysLeft) days left — \(scoreStatus)",
                        "Keep it up! \(daysLeft) days remaining. \(scoreStatus)",
                        "Don't let \(opName) get comfortable! \(daysLeft) days to go",
                        "\(scoreStatus) \(daysLeft) days left to make your move!",
                    ]
                    scheduleRivalryNotification(
                        id: "rivalry-milestone-daily-\(rivalry.id)-\(nudgeCount)",
                        title: rivalry.title,
                        body: messages[nudgeCount % messages.count],
                        date: nudgeTime,
                        rivalryId: rivalry.id
                    )
                }
                nudgeDay = calendar.date(byAdding: .day, value: 1, to: nudgeDay) ?? endDate
                nudgeCount += 1
            }
        }
    }

    private func scheduleRivalryNotification(id: String, title: String, body: String, date: Date, rivalryId: Int) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = "SOCIAL"
        content.userInfo = ["type": "rivalry", "ref_id": rivalryId]

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
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

    func removeStalePendingCalendarNotifications() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let now = Date()
            let staleIds = requests.compactMap { request -> String? in
                guard request.content.categoryIdentifier == "APPOINTMENT"
                        || request.content.categoryIdentifier == "PANTRY_EXPIRY" else {
                    return nil
                }

                guard let trigger = request.trigger as? UNCalendarNotificationTrigger else {
                    return nil
                }

                guard let nextTriggerDate = trigger.nextTriggerDate() else {
                    return request.identifier
                }

                return nextTriggerDate <= now ? request.identifier : nil
            }

            guard !staleIds.isEmpty else { return }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: staleIds)
        }
    }

    private func tripETAKey(tripId: Int, minutes: Int) -> String {
        "trip_eta_alert_\(tripId)_\(minutes)"
    }
}
