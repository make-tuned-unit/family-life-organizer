import Foundation
import SwiftData

@Model
final class BudgetCategory {
    var serverId: Int?
    var name: String
    var monthlyLimit: Double?
    var color: String?

    init(
        serverId: Int? = nil,
        name: String,
        monthlyLimit: Double? = nil,
        color: String? = nil
    ) {
        self.serverId = serverId
        self.name = name
        self.monthlyLimit = monthlyLimit
        self.color = color
    }
}

struct BudgetSummaryResponse: Codable {
    let category: String
    let monthly_limit: Double?
    let color: String?
    let spent: Double
}
