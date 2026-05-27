import Foundation

struct PantryItemResponse: Codable, Identifiable {
    let id: Int
    let item: String
    let category: String?
    let location: String?
    let quantity: String?
    let unit: String?
    let expiry_date: String?
    let added_by: String?
    let created_at: String?
}
