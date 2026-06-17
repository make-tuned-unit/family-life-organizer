import Foundation

/// The daily concierge brief returned by `GET /api/concierge/brief`.
struct ConciergeBrief: Codable {
    let date: String
    let summary: String
    let counts: ConciergeCounts
    let cards: [ConciergeCard]
    let aiEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case date, summary, counts, cards
        case aiEnabled = "ai_enabled"
    }

    var isAllClear: Bool { cards.isEmpty }
}

struct ConciergeCounts: Codable {
    let overdueTasks: Int
    let upcomingAppointments: Int
    let openDecisions: Int
    let expiringPantry: Int
    let upcomingEvents: Int
    let pendingCoverage: Int
    let budgetAlerts: Int
}

/// Household premium entitlement status from the backend.
struct SubscriptionStatus: Codable {
    let premium: Bool
    let productId: String?
    let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case premium
        case productId = "product_id"
        case expiresAt = "expires_at"
    }
}

/// Response from `POST /api/concierge/chat`.
struct ConciergeChatResponse: Codable {
    let conversationId: Int
    let reply: String
    let actions: [ConciergeAction]

    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case reply, actions
    }
}

/// A concrete action the butler took during a turn (e.g. added a task).
struct ConciergeAction: Codable, Hashable {
    let tool: String
    let summary: String
}

/// One "needs you" item. `kind` and `route` are stable strings from the server;
/// the view maps them to icon tint and navigation target.
struct ConciergeCard: Codable, Identifiable {
    let id: String
    let kind: String
    let icon: String
    let title: String
    let subtitle: String
    let route: String

    /// The tab to switch to when tapped. Falls back to Home for unknown routes.
    var destinationTab: MainTab {
        switch route {
        case "calendar": .calendar
        case "lists":    .lists
        case "budget":   .budget
        case "more":     .more
        default:         .home
        }
    }
}
