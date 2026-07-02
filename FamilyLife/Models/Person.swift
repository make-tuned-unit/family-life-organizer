import Foundation
import SwiftUI

/// A member of the household's People registry. Either linked to a real user
/// account (`user_id` set) or a dependent — a kid or relative without a device.
struct PersonResponse: Codable, Identifiable {
    let id: Int
    let name: String
    let relationship: String?
    let birthday: String?
    let anniversary: String?
    let notes: String?
    let user_id: Int?
    let is_dependent: Int?
    let avatar_color: String?
    let created_at: String?
    let gift_idea_count: Int?
    let milestone_count: Int?
    let decision_count: Int?
    let key_date_count: Int?

    var isDependent: Bool { (is_dependent ?? 0) == 1 }
    var isLinkedUser: Bool { user_id != nil }

    var accentColor: Color {
        switch avatar_color {
        case "rose": return AccentTheme.rose.color
        case "ocean": return AccentTheme.ocean.color
        case "saffron": return AccentTheme.saffron.color
        case "terracotta": return AccentTheme.terracotta.color
        case "mauve": return AccentTheme.mauve.color
        case "sage": return AccentTheme.sage.color
        default:
            // No color set — auto-assign a stable one so people don't all look
            // identical. Deterministic by id, so a person keeps the same color.
            let palette: [AccentTheme] = [.sage, .rose, .ocean, .saffron, .mauve, .terracotta]
            return palette[abs(id) % palette.count].color
        }
    }

    /// Bridge into the existing gift views, which predate the People registry.
    var asGiftPerson: GiftPersonResponse {
        GiftPersonResponse(id: id, name: name, relationship: relationship ?? "other",
                           birthday: birthday, anniversary: anniversary, notes: notes,
                           created_at: created_at)
    }
}

struct MilestoneResponse: Codable, Identifiable {
    let id: Int
    let person_id: Int
    let person_name: String?
    let title: String
    let description: String?
    let milestone_date: String
    let category: String?
    let photo_data: String?
    let creator_name: String?
    let created_at: String?

    var categoryEnum: MilestoneCategory { MilestoneCategory(rawValue: category ?? "") ?? .moment }
}

enum MilestoneCategory: String, CaseIterable, Identifiable {
    case first, school, sports, growth, moment

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .first: "First"
        case .school: "School"
        case .sports: "Sports"
        case .growth: "Growth"
        case .moment: "Moment"
        }
    }

    var icon: String {
        switch self {
        case .first: "sparkles"
        case .school: "graduationcap.fill"
        case .sports: "trophy.fill"
        case .growth: "chart.line.uptrend.xyaxis"
        case .moment: "heart.fill"
        }
    }

    var color: Color {
        switch self {
        case .first: AccentTheme.saffron.color
        case .school: AccentTheme.ocean.color
        case .sports: AccentTheme.rose.color
        case .growth: AccentTheme.sage.color
        case .moment: AccentTheme.terracotta.color
        }
    }
}
