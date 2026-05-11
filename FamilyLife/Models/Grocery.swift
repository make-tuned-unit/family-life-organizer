import Foundation
import SwiftData

@Model
final class Grocery {
    var serverId: Int?
    var item: String
    var category: String?
    var quantity: String
    var status: String
    var addedBy: String
    var addedAt: Date
    var purchasedAt: Date?

    init(
        serverId: Int? = nil,
        item: String,
        category: String? = nil,
        quantity: String = "1",
        status: String = "needed",
        addedBy: String = "jesse"
    ) {
        self.serverId = serverId
        self.item = item
        self.category = category
        self.quantity = quantity
        self.status = status
        self.addedBy = addedBy
        self.addedAt = Date()
    }
}

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
