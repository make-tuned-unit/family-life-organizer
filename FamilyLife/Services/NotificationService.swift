import Foundation
import UserNotifications
import CoreLocation
import MapKit

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
        // Tapping opens the specific event (was: no payload, tap did nothing).
        content.userInfo = ["type": "event", "ref_id": id]
        content.interruptionLevel = .timeSensitive

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

    // MARK: - Leave-soon travel reminders

    /// For upcoming located events, estimate drive time from `origin` and schedule
    /// a "time to head out" notification 15 min before you'd need to leave.
    /// Only considers events in the next ~36h that have a location and a time.
    func scheduleTravelReminders(_ appointments: [AppointmentResponse], origin: CLLocationCoordinate2D) async {
        guard await isAuthorized() else { return }
        let now = Date()
        let horizon = now.addingTimeInterval(36 * 60 * 60)
        for appt in appointments {
            guard let location = appt.location, !location.isEmpty,
                  let time = appt.appointment_time, !time.isEmpty,
                  let start = parseDateTime(date: appt.appointment_date, time: time, minutesBefore: 0),
                  start > now, start < horizon else { continue }
            guard let dest = await geocode(location),
                  let travel = await estimateTravelSeconds(from: origin, to: dest) else { continue }
            scheduleTravelReminder(id: appt.id, title: appt.title, location: location, eventStart: start, travelSeconds: travel)
        }
    }

    private func scheduleTravelReminder(id: Int, title: String, location: String, eventStart: Date, travelSeconds: TimeInterval) {
        let identifier = "travel-\(id)"
        // Notify 15 min before you'd have to leave (leave-by = start − drive time).
        let fireDate = eventStart.addingTimeInterval(-travelSeconds - 15 * 60)
        guard fireDate > Date() else {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
            return
        }
        let minutes = max(1, Int((travelSeconds / 60).rounded()))
        let content = UNMutableNotificationContent()
        content.title = "Time to head out soon"
        content.body = "Leave in about 15 min for \(title) — ~\(minutes) min drive to \(location)."
        content.sound = .default
        content.categoryIdentifier = "TRAVEL"

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private func geocode(_ address: String) async -> CLLocationCoordinate2D? {
        let placemarks = try? await CLGeocoder().geocodeAddressString(address)
        return placemarks?.first?.location?.coordinate
    }

    private func estimateTravelSeconds(from origin: CLLocationCoordinate2D, to dest: CLLocationCoordinate2D) async -> TimeInterval? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: dest))
        request.transportType = .automobile
        let eta = try? await MKDirections(request: request).calculateETA()
        return eta?.expectedTravelTime
    }

    // MARK: - Activity routine confirmations

    /// Best-effort local nudge to confirm an activity session after its calendar
    /// event (e.g. "Did you go to violin?"), deep-linking to the routine. The
    /// identifier is stable per (routine, date) so re-scheduling can't duplicate.
    func scheduleActivityConfirmation(routineId: Int, activity: String, date: String, hour: Int = 19) {
        let content = UNMutableNotificationContent()
        content.title = "Did you go to \(activity)?"
        content.body = "Tap to confirm — it counts toward your milestones."
        content.sound = .default
        content.categoryIdentifier = "ROUTINE_CONFIRM"
        content.userInfo = ["type": "routine", "ref_id": routineId]

        let hh = String(format: "%02d:00", max(0, min(23, hour)))
        guard let fire = parseDateTime(date: date, time: hh, minutesBefore: 0), fire > Date() else { return }
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: "routine-confirm-\(routineId)-\(date)", content: content, trigger: trigger)
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
        content.title = sender
        content.body = hasImage ? "Sent you a photo" : String(text.prefix(140))
        content.sound = .default
        content.categoryIdentifier = "MESSAGE"
        if !userInfo.isEmpty { content.userInfo = userInfo }
        // Group a conversation's notifications together (per partner/group id).
        if let refId = userInfo["ref_id"] as? Int {
            content.threadIdentifier = "chat-\(refId)"
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "dm-\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    /// Update DM watermark without firing notifications (used on app launch).
    /// Must seed the SAME set `checkForNewMessages` consults ("notified_dm_ids");
    /// writing a separate "last_seen_dm_id" key left every already-delivered
    /// (APNs-pushed) conversation unseen, so it re-fired as a local notification.
    func syncWatermark(_ conversations: [APIService.ConversationResponse]) {
        var list = UserDefaults.standard.stringArray(forKey: "notified_dm_ids") ?? []
        var seen = Set(list)
        for convo in conversations {
            let key = String(convo.id)
            if !seen.contains(key) {
                seen.insert(key)
                list.append(key)
            }
        }
        UserDefaults.standard.set(Array(list.suffix(500)), forKey: "notified_dm_ids")
    }

    /// Update feed watermark without firing notifications (used on app launch)
    func syncFeedWatermark(_ items: [APIService.ActivityItem]) {
        var list = notifiedFeedKeyList
        var seen = Set(list)
        for item in items where !seen.contains(item.stableKey) {
            seen.insert(item.stableKey)
            list.append(item.stableKey)
        }
        saveNotifiedFeedKeys(list)
    }

    /// Check for new DMs since last check and fire notifications
    func checkForNewMessages(_ conversations: [APIService.ConversationResponse], currentUserId: Int? = nil) {
        var list = UserDefaults.standard.stringArray(forKey: "notified_dm_ids") ?? []
        var seen = Set(list)
        // First launch — mark all current
        if seen.isEmpty {
            UserDefaults.standard.set(conversations.map { String($0.id) }, forKey: "notified_dm_ids")
            return
        }

        var notified = 0
        for convo in conversations {
            let key = String(convo.id)
            guard !seen.contains(key) else { continue }
            // Never notify for a thread whose newest message is one WE sent
            // (e.g. share-to-DM without opening the thread while an older unread
            // exists): the row is the latest message regardless of direction, so
            // an outgoing message would otherwise fire with the partner's name
            // but our own text. Advance the watermark past it so a later partner
            // reply (a new row/id) still notifies.
            if let currentUserId, convo.sender_id == currentUserId {
                seen.insert(key); list.append(key); continue
            }
            guard convo.unread_count > 0 else { continue }
            guard notified < 3 else { break }
            notifyNewMessage(
                from: convo.partner_name, text: convo.text,
                userInfo: ["type": "message", "ref_id": convo.partner_id, "name": convo.partner_name]
            )
            seen.insert(key)
            list.append(key)
            notified += 1
        }

        // Ordered append + suffix keeps the NEWEST 500; trimming a Set trimmed
        // arbitrary keys, which could re-notify old messages.
        UserDefaults.standard.set(Array(list.suffix(500)), forKey: "notified_dm_ids")
    }

    /// Check feed for new items since last check and fire notifications
    func checkForNewFeedItems(_ items: [APIService.ActivityItem], currentUser: String) {
        var list = notifiedFeedKeyList
        var seen = Set(list)
        // First launch — mark all current, don't spam
        if seen.isEmpty {
            saveNotifiedFeedKeys(items.map(\.stableKey))
            return
        }

        var notified = 0
        for item in items {
            guard !seen.contains(item.stableKey) else { continue }
            guard notified < 3 else { break }
            guard item.author?.localizedCaseInsensitiveCompare(currentUser) != .orderedSame else {
                seen.insert(item.stableKey)
                list.append(item.stableKey)
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
                list.append(item.stableKey)
                continue
            }
            seen.insert(item.stableKey)
            list.append(item.stableKey)
            notified += 1
        }

        saveNotifiedFeedKeys(list)
    }

    private var notifiedFeedKeyList: [String] {
        UserDefaults.standard.stringArray(forKey: "notified_feed_keys") ?? []
    }

    private func saveNotifiedFeedKeys(_ keys: [String]) {
        // Ordered list, newest appended last — suffix keeps the newest 200.
        // (Trimming a Set dropped ARBITRARY keys and could re-notify old items.)
        UserDefaults.standard.set(Array(keys.suffix(200)), forKey: "notified_feed_keys")
    }

    // MARK: - Rivalry milestone reminders

    /// Fuzzy participant/entry name match: exact (case-insensitive), or one is a
    /// first-name prefix of the other ("Jesse" ↔ "Jesse Fairbanks"). Mirrors the
    /// matching used server-side and in ContentView so totals never silently
    /// drop the device owner's own entries.
    private static func nameMatches(_ a: String, _ b: String) -> Bool {
        let aL = a.lowercased(), bL = b.lowercased()
        return aL == bL || aL.hasPrefix(bL + " ") || bL.hasPrefix(aL + " ")
    }

    /// Schedule local notifications for active rivalry milestones (halfway, 1-day-left, daily nudge at 9am).
    /// Call whenever rivalries are loaded/refreshed. Idempotent — removes stale rivalry notifications first.
    func scheduleRivalryMilestones(_ rivalries: [RivalryResponse], myName: String, myUsername: String = "", entriesByRivalry: [Int: [RivalryEntryResponse]]) {
        // Remove any previously scheduled rivalry reminders
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests.filter { $0.identifier.hasPrefix("rivalry-milestone-") }.map(\.identifier)
            if !ids.isEmpty {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
            }
        }

        let now = Date()
        let calendar = Calendar.current

        // Match the user's account name/username to the name used inside the
        // rivalry. Entries are stored under the in-rivalry name (e.g. "Jesse"),
        // which may differ from the account display name ("Jesse Fairbanks") —
        // so resolve it the same way ContentView.myRivalryName does.
        let candidates = [myName, myUsername].filter { !$0.isEmpty }

        for rivalry in rivalries {
            guard rivalry.status == RivalryStatus.active.rawValue || rivalry.status == RivalryStatus.pending.rawValue else { continue }
            guard let endDate = rivalry.endDate, endDate > now else { continue }
            // Only schedule for rivalries the user is actually in. Capture the
            // user's name AS IT APPEARS in this rivalry so all totals below
            // resolve against the same string the entries are stored under.
            guard let myParticipantName = rivalry.participantNames.first(where: { p in
                candidates.contains { Self.nameMatches(p, $0) }
            }) else { continue }
            let startDate = ISO8601DateFormatter.flexible.date(from: rivalry.start_date)
                ?? DateFormatter.isoDate.date(from: rivalry.start_date)
                ?? now

            let entries = entriesByRivalry[rivalry.id] ?? []
            let totalFor: (String) -> Double = { name in
                entries.filter { Self.nameMatches($0.member_name, name) }.reduce(0.0) { $0 + $1.value }
            }
            let myTotal = totalFor(myParticipantName)
            let opponents = rivalry.participantNames.filter { !Self.nameMatches($0, myParticipantName) }
            let topOpponent = opponents.max { totalFor($0) < totalFor($1) }
            let opTotal = topOpponent.map(totalFor) ?? 0
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
