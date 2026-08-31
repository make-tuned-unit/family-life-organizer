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
    let tier: String?        // "premium" | "lite" | nil
    let productId: String?
    let expiresAt: String?
    let source: String?
    let stripeManaged: Bool?
    let chatsPerDay: Int?

    enum CodingKeys: String, CodingKey {
        case premium
        case tier
        case productId = "product_id"
        case expiresAt = "expires_at"
        case source
        case stripeManaged = "stripe_managed"
        case chatsPerDay = "chats_per_day"
    }
}

/// How the user composed a concierge turn. Voice and chat-extract get a
/// more action-oriented system prompt on the server.
enum ConciergeMessageSource: String {
    case text
    case voice
    case chatExtract = "chat_extract"
}

/// Public Concierge plan list from `GET /api/subscription/catalog`.
struct SubscriptionCatalog: Codable {
    let stripe: Bool?
    let currency: String?
    let plans: [Plan]

    struct Plan: Codable {
        let productId: String
        let tier: String
        let period: String
        let amountCents: Int
        let chats: Int
        let currency: String?

        enum CodingKeys: String, CodingKey {
            case productId = "product_id"
            case tier, period, chats, currency
            case amountCents = "amount_cents"
        }

        var displayPrice: String {
            let code = (currency ?? "cad").uppercased()
            let value = Decimal(amountCents) / 100
            let fmt = NumberFormatter()
            fmt.numberStyle = .currency
            fmt.currencyCode = code
            if code == "CAD" { fmt.currencySymbol = "CA$" }
            if code == "USD" { fmt.currencySymbol = "US$" }
            if code == "EUR" { fmt.currencySymbol = "€" }
            return fmt.string(from: value as NSDecimalNumber) ?? "\(code) \(value)"
        }
    }

    func plan(productId: String) -> Plan? {
        plans.first { $0.productId == productId }
    }
}

struct CheckoutSessionResponse: Codable {
    let url: String
    let id: String
}

struct CheckoutConfirmResponse: Codable {
    let sessionStatus: String?
    let paymentStatus: String?
    let premium: Bool
    let tier: String?
    let productId: String?
    let stripeManaged: Bool?
    let chatsPerDay: Int?

    enum CodingKeys: String, CodingKey {
        case sessionStatus = "session_status"
        case paymentStatus = "payment_status"
        case premium, tier
        case productId = "product_id"
        case stripeManaged = "stripe_managed"
        case chatsPerDay = "chats_per_day"
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
    let entityId: Int?
    let personId: Int?
    let personName: String?

    enum CodingKeys: String, CodingKey {
        case tool, summary
        case entityId = "entity_id"
        case personId = "person_id"
        case personName = "person_name"
    }
}

/// Summary row for a past conversation (from `GET /api/concierge/conversations`).
struct ConciergeConversationSummary: Codable, Identifiable {
    let id: Int
    let title: String?
    let updatedAt: String?
    let lastMessage: String?
    let messageCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, title
        case updatedAt = "updated_at"
        case lastMessage = "last_message"
        case messageCount = "message_count"
    }

    var displayTitle: String {
        if let t = title, !t.isEmpty { return t }
        if let m = lastMessage, !m.isEmpty { return m }
        return "Conversation"
    }
}

/// One stored message in a conversation (from `GET /api/concierge/conversations/:id/messages`).
struct ConciergeStoredMessage: Codable {
    let role: String
    let content: String
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
