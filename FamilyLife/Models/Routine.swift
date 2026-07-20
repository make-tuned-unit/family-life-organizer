import Foundation

// Routines: recurring life-pattern trackers — menstrual cycles, baby sleep, the
// guided sleep-training program, and freeform custom routines. `config` and each
// entry's `value` are JSON strings the backend stores verbatim, so they decode
// as optional Strings the views parse as needed.

enum RoutineType: String, Codable, CaseIterable, Identifiable {
    case period
    case babySleep = "baby_sleep"
    case sleepTraining = "sleep_training"
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .period:        "Cycle"
        case .babySleep:     "Baby sleep"
        case .sleepTraining: "Sleep training"
        case .custom:        "Custom"
        }
    }

    /// One-line description shown when picking a type.
    var blurb: String {
        switch self {
        case .period:        "Track your menstrual cycle and symptoms."
        case .babySleep:     "Log naps, night sleep, and wake-ups."
        case .sleepTraining: "A guided program from newborn to 4 years."
        case .custom:        "Track any habit or routine, your way."
        }
    }

    // SF Symbols — one canonical glyph per type.
    var icon: String {
        switch self {
        case .period:        "drop.fill"
        case .babySleep:     "moon.zzz.fill"
        case .sleepTraining: "moon.stars.fill"
        case .custom:        "repeat"
        }
    }

    var needsBirthdate: Bool { self == .babySleep || self == .sleepTraining }
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

    var type: RoutineType { RoutineType(rawValue: routine_type) ?? .custom }
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
