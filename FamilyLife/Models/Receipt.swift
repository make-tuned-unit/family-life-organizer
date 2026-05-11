import Foundation
import SwiftData

@Model
final class Receipt {
    var serverId: Int?
    var amount: Double
    var merchant: String
    var date: String
    var category: String?
    var paymentMethod: String?
    var imagePath: String?
    var notes: String?
    var processedBy: String?
    var addedBy: String
    var createdAt: Date

    init(
        serverId: Int? = nil,
        amount: Double,
        merchant: String,
        date: String,
        category: String? = nil,
        paymentMethod: String? = nil,
        addedBy: String = "jesse"
    ) {
        self.serverId = serverId
        self.amount = amount
        self.merchant = merchant
        self.date = date
        self.category = category
        self.paymentMethod = paymentMethod
        self.addedBy = addedBy
        self.createdAt = Date()
    }
}

struct ReceiptResponse: Codable, Identifiable {
    let id: Int
    let amount: Double
    let merchant: String
    let date: String
    let category: String?
    let payment_method: String?
    let image_path: String?
    let notes: String?
    let processed_by: String?
    let added_by: String?
    let created_at: String?
}
