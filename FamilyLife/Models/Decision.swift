import Foundation
import SwiftData

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

@Model
final class Decision {
    @Attribute(.unique) var id: UUID
    var title: String
    var decisionType: DecisionType
    var body: String?
    var linkURL: String?
    var photoData: Data?
    var pollOptions: [String]
    var creatorName: String
    var status: DecisionStatus
    var createdAt: Date
    var expiresAt: Date

    init(
        title: String,
        decisionType: DecisionType,
        body: String? = nil,
        linkURL: String? = nil,
        pollOptions: [String] = [],
        creatorName: String = "Jesse"
    ) {
        self.id = UUID()
        self.title = title
        self.decisionType = decisionType
        self.body = body
        self.linkURL = linkURL
        self.pollOptions = pollOptions
        self.creatorName = creatorName
        self.status = .active
        self.createdAt = Date()
        self.expiresAt = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    }
}

@Model
final class DecisionReaction {
    @Attribute(.unique) var id: UUID
    var decisionID: UUID
    var memberName: String
    var reactionType: String // thumbsUp, thumbsDown, heart, vote
    var pollChoice: Int? // index of poll option if vote
    var createdAt: Date

    init(
        decisionID: UUID,
        memberName: String,
        reactionType: String,
        pollChoice: Int? = nil
    ) {
        self.id = UUID()
        self.decisionID = decisionID
        self.memberName = memberName
        self.reactionType = reactionType
        self.pollChoice = pollChoice
        self.createdAt = Date()
    }
}

@Model
final class DecisionComment {
    @Attribute(.unique) var id: UUID
    var decisionID: UUID
    var memberName: String
    var text: String
    var createdAt: Date

    init(
        decisionID: UUID,
        memberName: String,
        text: String
    ) {
        self.id = UUID()
        self.decisionID = decisionID
        self.memberName = memberName
        self.text = text
        self.createdAt = Date()
    }
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
