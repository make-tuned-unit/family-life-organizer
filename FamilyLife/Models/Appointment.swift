import Foundation
import SwiftData

@Model
final class Appointment {
    var serverId: Int?
    var title: String
    var appointmentDescription: String?
    var appointmentDate: String
    var appointmentTime: String?
    var location: String?
    var withPerson: String?
    var category: String?
    var personTags: String?
    var createdAt: Date

    init(
        serverId: Int? = nil,
        title: String,
        appointmentDescription: String? = nil,
        appointmentDate: String,
        appointmentTime: String? = nil,
        location: String? = nil,
        withPerson: String? = nil,
        category: String? = nil,
        personTags: String? = nil
    ) {
        self.serverId = serverId
        self.title = title
        self.appointmentDescription = appointmentDescription
        self.appointmentDate = appointmentDate
        self.appointmentTime = appointmentTime
        self.location = location
        self.withPerson = withPerson
        self.category = category
        self.personTags = personTags
        self.createdAt = Date()
    }
}

struct AppointmentResponse: Codable, Identifiable {
    let id: Int
    let title: String
    let description: String?
    let appointment_date: String
    let appointment_time: String?
    let location: String?
    let with_person: String?
    let category: String?
    let person_tags: String?
    let reminder_sent: Int?
    let created_at: String?
}
