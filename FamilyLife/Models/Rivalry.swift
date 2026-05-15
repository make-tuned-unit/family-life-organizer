import Foundation
import SwiftData

enum ChallengeType: String, Codable, CaseIterable, Identifiable {
    case steps
    case workout
    case pushups
    case squats
    case situps
    case plank
    case running
    case habit
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .steps: "Steps"
        case .workout: "Workouts"
        case .pushups: "Push-ups"
        case .squats: "Squats"
        case .situps: "Sit-ups"
        case .plank: "Plank"
        case .running: "Running"
        case .habit: "Habit Streak"
        case .custom: "Custom"
        }
    }

    var icon: String {
        switch self {
        case .steps: "figure.walk"
        case .workout: "dumbbell.fill"
        case .pushups: "figure.strengthtraining.traditional"
        case .squats: "figure.cooldown"
        case .situps: "figure.core.training"
        case .plank: "figure.pilates"
        case .running: "figure.run"
        case .habit: "checkmark.circle.fill"
        case .custom: "star.fill"
        }
    }

    var hint: String {
        switch self {
        case .steps: "Who can log the most steps?"
        case .workout: "Track completed workouts. Each workout counts as 1."
        case .pushups: "Daily push-up count — e.g. 20 per day for a month."
        case .squats: "Daily squat count — set a target and go."
        case .situps: "Daily sit-up count — track your core work."
        case .plank: "Track total plank seconds or daily plank holds."
        case .running: "Track distance (km) or minutes of running."
        case .habit: "Build a streak — log daily to keep your count going."
        case .custom: "Define your own challenge and track any metric."
        }
    }

    var color: String {
        switch self {
        case .steps: "blue"
        case .workout, .pushups, .squats, .situps, .plank: "orange"
        case .running: "teal"
        case .habit: "green"
        case .custom: "purple"
        }
    }
}

enum RivalryStatus: String, Codable, CaseIterable {
    case pending
    case active
    case completed
    case declined
}

@Model
final class Rivalry {
    @Attribute(.unique) var id: UUID
    var title: String
    var challengeType: ChallengeType
    var initiatorID: UUID
    var initiatorName: String
    var opponentID: UUID
    var opponentName: String
    var startDate: Date
    var endDate: Date
    var status: RivalryStatus
    var pointValue: Int
    var winnerID: UUID?
    var createdAt: Date

    init(
        title: String,
        challengeType: ChallengeType,
        initiatorID: UUID,
        initiatorName: String,
        opponentID: UUID,
        opponentName: String,
        startDate: Date = Date(),
        endDate: Date,
        pointValue: Int = 100
    ) {
        self.id = UUID()
        self.title = title
        self.challengeType = challengeType
        self.initiatorID = initiatorID
        self.initiatorName = initiatorName
        self.opponentID = opponentID
        self.opponentName = opponentName
        self.startDate = startDate
        self.endDate = endDate
        self.status = .active
        self.pointValue = pointValue
        self.createdAt = Date()
    }
}

@Model
final class RivalryEntry {
    @Attribute(.unique) var id: UUID
    var rivalryID: UUID
    var memberID: UUID
    var memberName: String
    var value: Double
    var note: String?
    var loggedAt: Date
    var isVerified: Bool

    init(
        rivalryID: UUID,
        memberID: UUID,
        memberName: String,
        value: Double,
        note: String? = nil,
        isVerified: Bool = false
    ) {
        self.id = UUID()
        self.rivalryID = rivalryID
        self.memberID = memberID
        self.memberName = memberName
        self.value = value
        self.note = note
        self.loggedAt = Date()
        self.isVerified = isVerified
    }
}

@Model
final class FamilyMemberPoints {
    @Attribute(.unique) var id: UUID
    var memberID: UUID
    var memberName: String
    var totalPoints: Int
    var rivalriesWon: Int
    var rivalriesCompleted: Int
    var lastUpdated: Date

    init(memberID: UUID, memberName: String) {
        self.id = UUID()
        self.memberID = memberID
        self.memberName = memberName
        self.totalPoints = 0
        self.rivalriesWon = 0
        self.rivalriesCompleted = 0
        self.lastUpdated = Date()
    }
}

struct RivalryResponse: Codable, Identifiable {
    let id: Int
    let title: String
    let challenge_type: String
    let initiator_name: String
    let opponent_name: String
    let start_date: String
    let end_date: String
    let status: String
    let point_value: Int
    let winner_name: String?
    let created_at: String?
    let participants: String? // JSON array of all participant names

    var participantNames: [String] {
        guard let participants, let data = participants.data(using: .utf8),
              let names = try? JSONDecoder().decode([String].self, from: data) else {
            return [initiator_name, opponent_name]
        }
        return names
    }

    var isMultiPlayer: Bool { participantNames.count > 2 }
}

struct RivalryEntryResponse: Codable, Identifiable {
    let id: Int
    let rivalry_id: Int
    let member_name: String
    let value: Double
    let note: String?
    let is_verified: Int?
    let logged_at: String?
}

struct RivalryCompleteResponse: Codable {
    let success: Bool
    let winner_name: String?
    let initiator_total: Double
    let opponent_total: Double
    let scores: [ParticipantScore]?
    let message: String?
    let is_tie: Bool?
}

struct ParticipantScore: Codable, Identifiable {
    let name: String
    let total: Double
    var id: String { name }
}

struct RivalryLeaderboardResponse: Codable, Identifiable {
    var id: String { member_name }
    let member_name: String
    let rivalries_completed: Int
    let rivalries_won: Int
    let total_points: Int
}
