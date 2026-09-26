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
    // Nullable in the DB — a single NULL row must not brick the whole list decode.
    let relationship: String?
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
    var status: String
    let for_event: String?
    let created_at: String?
    // Privacy (absent on rows saved before gift privacy existed → household).
    var created_by: Int? = nil
    var visibility: String? = nil
    var shared_with_user_id: Int? = nil
    var purchased_by: Int? = nil
    var purchased_at: String? = nil

    var visibilityValue: GiftVisibility { GiftVisibility(rawValue: visibility ?? "") ?? .household }
}

/// Who can see a gift idea. Whatever the choice, the person it's for never
/// sees ideas someone else saved for them (enforced server-side).
enum GiftVisibility: String, Codable {
    /// Everyone at home (except the recipient).
    case household
    /// Only whoever saved it.
    case `private`
    /// Whoever saved it plus one household member (`shared_with_user_id`).
    case shared
}

struct GiftPurchasedResponse: Decodable {
    let success: Bool
    let notified: Bool
}

struct SpecialEventResponse: Codable, Identifiable {
    let id: Int
    let person_id: Int?
    let title: String
    let date: String
    let is_recurring: Int?
    let event_type: String
    let notes: String?
    /// "household" (everyone at home) or "private" (only whoever added it).
    /// Absent on rows written before key dates had a visibility.
    let shared_scope: String?
    let created_by: Int?
    let created_at: String?

    var isPrivate: Bool { shared_scope == "private" }
}
