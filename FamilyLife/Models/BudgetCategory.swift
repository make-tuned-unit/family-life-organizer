import Foundation

struct BudgetSummaryResponse: Codable {
    let category: String
    let monthly_limit: Double?
    let color: String?
    let spent: Double
}
