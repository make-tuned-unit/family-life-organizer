import Foundation

enum DecisionType: String, Codable, CaseIterable, Identifiable {
    case text
    case link
    case photo
    case poll

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .text: "Text"
        case .link: "Link"
        case .photo: "Photo"
        case .poll: "Poll"
        }
    }

    var icon: String {
        switch self {
        case .text: "text.bubble.fill"
        case .link: "link"
        case .photo: "photo.fill"
        case .poll: "chart.bar.fill"
        }
    }
}

enum DecisionStatus: String, Codable {
    case active
    case resolved
    case expired
}

struct DecisionResponse: Codable, Identifiable {
    let id: Int
    let title: String
    let decision_type: String
    let body: String?
    let link_url: String?
    let photo_data: String?
    let poll_options: [String]
    let creator_name: String
    let status: String
    let created_at: String?
    let expires_at: String?
    let group_id: Int?
    let person_id: Int?    // optional "about <person>" tag (People registry id)
}

struct DecisionReactionResponse: Codable, Identifiable {
    let id: Int
    let decision_id: Int
    let member_name: String
    let reaction_type: String
    let poll_choice: Int?
    let created_at: String?
}

struct DecisionCommentResponse: Codable, Identifiable {
    let id: Int
    let decision_id: Int
    let member_name: String
    let text: String
    let created_at: String?
}
