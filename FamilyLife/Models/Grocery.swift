import Foundation

struct GroceryResponse: Codable, Identifiable {
    let id: Int
    let item: String
    let category: String?
    let quantity: String?
    let status: String
    let added_by: String?
    let added_at: String?
    let purchased_at: String?
}
