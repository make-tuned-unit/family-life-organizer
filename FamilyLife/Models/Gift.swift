import Foundation
import SwiftData

@Model
final class GiftPerson {
    @Attribute(.unique) var id: UUID
    var name: String
    var relationship: String // spouse, child, parent, sibling, friend, other
    var birthday: String? // MM-dd
    var anniversary: String? // MM-dd
    var notes: String?
    var createdAt: Date

    init(name: String, relationship: String = "other", birthday: String? = nil, anniversary: String? = nil, notes: String? = nil) {
        self.id = UUID()
        self.name = name
        self.relationship = relationship
        self.birthday = birthday
        self.anniversary = anniversary
        self.notes = notes
        self.createdAt = Date()
    }

    var upcomingEvent: (String, Date)? {
        let cal = Calendar.current
        let now = Date()
        let year = cal.component(.year, from: now)

        var events: [(String, Date)] = []
        if let bday = birthday, let parsed = DateFormatter.monthDay.date(from: bday) {
            var comps = cal.dateComponents([.month, .day], from: parsed)
            comps.year = year
            if let date = cal.date(from: comps) {
                let adjusted = date < now ? (cal.date(byAdding: .year, value: 1, to: date) ?? date) : date
                events.append(("Birthday", adjusted))
            }
        }
        if let ann = anniversary, let parsed = DateFormatter.monthDay.date(from: ann) {
            var comps = cal.dateComponents([.month, .day], from: parsed)
            comps.year = year
            if let date = cal.date(from: comps) {
                let adjusted = date < now ? (cal.date(byAdding: .year, value: 1, to: date) ?? date) : date
                events.append(("Anniversary", adjusted))
            }
        }
        return events.min { $0.1 < $1.1 }
    }
}

enum GiftIdeaStatus: String, Codable {
    case idea
    case purchased
    case wrapped
    case given
}

@Model
final class GiftIdea {
    @Attribute(.unique) var id: UUID
    var personID: UUID
    var title: String
    var notes: String?
    var linkURL: String?
    var estimatedPrice: Double?
    var status: GiftIdeaStatus
    var forEvent: String? // birthday, anniversary, christmas, etc.
    var createdAt: Date

    init(
        personID: UUID,
        title: String,
        notes: String? = nil,
        linkURL: String? = nil,
        estimatedPrice: Double? = nil,
        forEvent: String? = nil
    ) {
        self.id = UUID()
        self.personID = personID
        self.title = title
        self.notes = notes
        self.linkURL = linkURL
        self.estimatedPrice = estimatedPrice
        self.status = .idea
        self.forEvent = forEvent
        self.createdAt = Date()
    }
}

@Model
final class SpecialEvent {
    @Attribute(.unique) var id: UUID
    var personID: UUID?
    var title: String
    var date: String // MM-dd for recurring
    var isRecurring: Bool
    var eventType: String // birthday, anniversary, holiday, custom
    var notes: String?
    var createdAt: Date

    init(
        personID: UUID? = nil,
        title: String,
        date: String,
        isRecurring: Bool = true,
        eventType: String = "custom",
        notes: String? = nil
    ) {
        self.id = UUID()
        self.personID = personID
        self.title = title
        self.date = date
        self.isRecurring = isRecurring
        self.eventType = eventType
        self.notes = notes
        self.createdAt = Date()
    }

    var nextOccurrence: Date? {
        let cal = Calendar.current
        let now = Date()
        let year = cal.component(.year, from: now)
        guard let parsed = DateFormatter.monthDay.date(from: date) else { return nil }
        var comps = cal.dateComponents([.month, .day], from: parsed)
        comps.year = year
        guard let d = cal.date(from: comps) else { return nil }
        return d < now ? cal.date(byAdding: .year, value: 1, to: d) : d
    }

    var daysUntil: Int? {
        guard let next = nextOccurrence else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: next).day
    }
}
