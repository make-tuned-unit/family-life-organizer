import Foundation

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
