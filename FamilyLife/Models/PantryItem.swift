import Foundation
import SwiftData

@Model
final class PantryItem {
    var serverId: Int?
    var item: String
    var category: String?
    var location: String
    var quantity: String
    var unit: String?
    var expiryDate: String?
    var addedBy: String
    var createdAt: Date

    init(
        serverId: Int? = nil,
        item: String,
        category: String? = nil,
        location: String = "pantry",
        quantity: String = "1",
        unit: String? = nil,
        expiryDate: String? = nil,
        addedBy: String = "jesse"
    ) {
        self.serverId = serverId
        self.item = item
        self.category = category
        self.location = location
        self.quantity = quantity
        self.unit = unit
        self.expiryDate = expiryDate
        self.addedBy = addedBy
        self.createdAt = Date()
    }
}

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
