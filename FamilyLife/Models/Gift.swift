import Foundation

enum GiftIdeaStatus: String, Codable {
    case idea
    case purchased
    case wrapped
    case given
}

struct GiftPersonResponse: Codable, Identifiable {
    let id: Int
    let name: String
    let relationship: String
    let birthday: String?
    let anniversary: String?
    let notes: String?
    let created_at: String?
}

struct GiftIdeaResponse: Codable, Identifiable {
    let id: Int
    let person_id: Int
    let title: String
    let notes: String?
    let link_url: String?
    let estimated_price: Double?
    let status: String
    let for_event: String?
    let created_at: String?
}

struct SpecialEventResponse: Codable, Identifiable {
    let id: Int
    let person_id: Int?
    let title: String
    let date: String
    let is_recurring: Int?
    let event_type: String
    let notes: String?
    let created_at: String?
}
