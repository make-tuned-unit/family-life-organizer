import Foundation

struct ItineraryResponse: Codable, Identifiable {
    let id: Int
    var title: String
    let traveler_id: Int
    let traveler_name: String
    var start_date: String
    var end_date: String
    var travelers: String?
    var notes: String?
    var status: String
    let group_id: Int?
    let created_at: String?

    var startDate: Date? {
        ISO8601DateFormatter.flexible.date(from: start_date)
        ?? DateFormatter.isoDate.date(from: start_date)
    }

    var endDate: Date? {
        ISO8601DateFormatter.flexible.date(from: end_date)
        ?? DateFormatter.isoDate.date(from: end_date)
    }

    var statusColor: String {
        switch status {
        case "planning": return "blue"
        case "active": return "green"
        case "completed": return "gray"
        default: return "blue"
        }
    }
}

struct ItineraryStayResponse: Codable, Identifiable {
    let id: Int
    let itinerary_id: Int
    var check_in: String
    var check_out: String
    var host_name: String?
    var host_user_id: Int?
    var host_contact_id: Int?
    var location_name: String?
    var address: String?
    var lat: Double?
    var lng: Double?
    var notes: String?
    var status: String
    var calendar_event_id: Int?
    var host_calendar_event_id: Int?
    let created_at: String?

    // For pending requests joined with itinerary data
    var itinerary_title: String?
    var traveler_name: String?

    var checkInDate: Date? {
        ISO8601DateFormatter.flexible.date(from: check_in)
        ?? DateFormatter.isoDate.date(from: check_in)
    }

    var checkOutDate: Date? {
        ISO8601DateFormatter.flexible.date(from: check_out)
        ?? DateFormatter.isoDate.date(from: check_out)
    }

    var nightCount: Int {
        guard let cin = checkInDate, let cout = checkOutDate else { return 1 }
        return max(1, Calendar.current.dateComponents([.day], from: cin, to: cout).day ?? 1)
    }

    var statusIcon: String {
        switch status {
        case "draft": return "pencil.circle"
        case "requested": return "clock"
        case "confirmed": return "checkmark.circle.fill"
        case "declined": return "xmark.circle.fill"
        default: return "circle"
        }
    }

    var statusColor: String {
        switch status {
        case "draft": return "gray"
        case "requested": return "orange"
        case "confirmed": return "green"
        case "declined": return "red"
        default: return "gray"
        }
    }
}

enum StayStatus: String {
    case draft, requested, confirmed, declined
}
