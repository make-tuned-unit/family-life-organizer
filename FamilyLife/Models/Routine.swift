import Foundation

// Routines: recurring life-pattern trackers — menstrual cycles, baby sleep, the
// guided sleep-training program, and freeform custom routines. `config` and each
// entry's `value` are JSON strings the backend stores verbatim, so they decode
// as optional Strings the views parse as needed.

enum RoutineType: String, Codable, CaseIterable, Identifiable {
    case period
    case babySleep = "baby_sleep"
    case sleepTraining = "sleep_training"
    case activity
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .period:        "Cycle"
        case .babySleep:     "Baby sleep"
        case .sleepTraining: "Sleep training"
        case .activity:      "Activity"
        case .custom:        "Custom"
        }
    }

    /// One-line description shown when picking a type.
    var blurb: String {
        switch self {
        case .period:        "Track your menstrual cycle, or your fertile window."
        case .babySleep:     "Log naps, night sleep, and wake-ups."
        case .sleepTraining: "A guided program from newborn to 4 years."
        case .activity:      "Practice like violin or swimming — earn milestones."
        case .custom:        "Track any habit or routine, your way."
        }
    }

    // SF Symbols — one canonical glyph per type.
    var icon: String {
        switch self {
        case .period:        "drop.fill"
        case .babySleep:     "moon.zzz.fill"
        case .sleepTraining: "moon.stars.fill"
        case .activity:      "figure.run"
        case .custom:        "repeat"
        }
    }

    var needsBirthdate: Bool { self == .babySleep || self == .sleepTraining }
    var isActivity: Bool { self == .activity }
    var isCycle: Bool { self == .period }
}

struct RoutineResponse: Codable, Identifiable {
    let id: Int
    let name: String
    let routine_type: String
    let subject_name: String?
    let subject_birthdate: String?
    let config: String?
    let color: String?
    let icon: String?
    let start_date: String?
    let active: Int?
    let created_at: String?
    let entry_count: Int?
    let last_entry_date: String?

    var type: RoutineType { RoutineType(rawValue: routine_type) ?? .custom }
}

struct RoutineEntryResponse: Codable, Identifiable {
    let id: Int
    let routine_id: Int?
    let entry_date: String
    let entry_time: String?
    let entry_type: String?
    let value: String?
    let notes: String?
    let created_at: String?
}

/// GET /api/routines/:id — the routine, its entries (newest first), and, for a
/// sleep_training routine with a birthdate, the age-based guidance.
struct RoutineDetailResponse: Codable, Identifiable {
    let id: Int
    let name: String
    let routine_type: String
    let subject_name: String?
    let subject_birthdate: String?
    let config: String?
    let color: String?
    let icon: String?
    let start_date: String?
    let active: Int?
    let created_at: String?
    let entries: [RoutineEntryResponse]
    let guidance: SleepGuidance?
    let cycle: CyclePrediction?
    let achievements: RoutineAchievements?

    var type: RoutineType { RoutineType(rawValue: routine_type) ?? .custom }
}

// MARK: - Cycle tracking (period + trying-to-conceive)

struct FertileWindow: Codable {
    let start: String
    let end: String
}

struct CyclePrediction: Codable {
    let mode: String                       // "period" | "ttc"
    let disclaimer: String
    let cycles_tracked: Int
    let insufficient: Bool?
    let note: String?
    let current_cycle_day: Int?
    let average_cycle_length: Int?
    let cycle_variability_days: Int?
    let period_length: Int?
    let next_period_date: String?
    let days_until_period: Int?
    let is_late: Bool?
    let late_by_days: Int?
    let current_phase: String?             // menstrual | follicular | fertile | ovulation | luteal
    let confidence: String?               // low | medium | high
    let irregular: Bool?
    // TTC only
    let predicted_ovulation_date: String?
    let fertile_window: FertileWindow?
    let fertile_note: String?

    var isTTC: Bool { mode == "ttc" }
}

// MARK: - Activity achievements

struct AchievementBadge: Codable, Identifiable {
    let count: Int
    let title: String
    let blurb: String
    var id: Int { count }
}

struct NextMilestone: Codable {
    let count: Int
    let title: String
    let blurb: String
    let remaining: Int
}

struct RoutineAchievements: Codable {
    let total_sessions: Int
    let current_streak_weeks: Int
    let last_session_date: String?
    let earned: [AchievementBadge]
    let next_milestone: NextMilestone?
    let latest: String?
}

// MARK: - Activity calendar occurrences

struct RoutineOccurrence: Codable, Identifiable {
    let date: String
    let confirmed: Bool
    let past: Bool
    let today: Bool
    var id: String { date }
}

struct RoutineOccurrences: Codable {
    let keyword: String?
    let occurrences: [RoutineOccurrence]
    let scheduled: Int
    let attended: Int
    let pending: [RoutineOccurrence]?
}

// MARK: - Sleep-training program (static template + age-based guidance)

struct SleepMethod: Codable, Identifiable {
    let key: String
    let name: String
    let summary: String
    let ages: String
    var id: String { key }
}

struct SleepPhase: Codable, Identifiable {
    let key: String
    let title: String
    let age_label: String
    let min_days: Int?
    let max_days: Int?
    let method: SleepMethod?
    let alt_methods: [SleepMethod]
    let description: String
    let steps: [String]
    let tips: [String]
    var id: String { key }
}

struct SleepSource: Codable, Identifiable {
    let title: String
    let url: String
    var id: String { url }
}

struct SleepTrainingTemplate: Codable {
    let id: String
    let title: String
    let subtitle: String
    let disclaimer: String
    let safe_sleep: [String]
    let methods: [SleepMethod]
    let phases: [SleepPhase]
    let sources: [SleepSource]
}

struct SleepGuidance: Codable {
    let age_days: Int
    let age_weeks: Int
    let age_months: Int
    let ready_for_training: Bool
    let current_phase: SleepPhase
    let safe_sleep: [String]
}
