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
}
