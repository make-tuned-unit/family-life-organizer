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
    let shared_scope: String?
    let created_by: Int?
    let color: String?
    let icon: String?
    let start_date: String?
    let active: Int?
    let created_at: String?
    let entry_count: Int?
    let last_entry_date: String?

    var type: RoutineType { RoutineType(rawValue: routine_type) ?? .custom }
    /// Routines are private unless explicitly shared with the household.
    var isSharedWithHousehold: Bool { shared_scope == "household" }
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
    let shared_scope: String?
    let created_by: Int?
    let color: String?
    let icon: String?
    let start_date: String?
    let active: Int?
    let created_at: String?
    let entries: [RoutineEntryResponse]
    let guidance: SleepGuidance?
    let cycle: CyclePrediction?
    let achievements: RoutineAchievements?
    let next_sleep: NextSleepWindow?
    let bedtime_prep: BedtimePrep?
    /// What the age guidance was computed from — "routine" when the routine
    /// carries a birthdate, "people" when it came from the child's People card.
    let birthdate_source: String?
    let resolved_birthdate: String?

    var type: RoutineType { RoutineType(rawValue: routine_type) ?? .custom }
    var isSharedWithHousehold: Bool { shared_scope == "household" }
}

/// When the next sleep is likely due, from the last wake plus the typical wake
/// window for the child's age. Absent when there's no birthdate to reason from
/// or no finished sleep to measure from.
struct NextSleepWindow: Codable {
    let last_wake_at: String?
    let last_sleep_type: String?
    let wake_window_label: String?
    let due_from: String?
    let due_by: String?
    let prepare_at: String?
    let lead_minutes: Int?
    let basis: String?

    var prepareDate: Date? { prepare_at.flatMap { DateFormatter.dateTimeMinute.date(from: $0) } }
    var dueFromDate: Date? { due_from.flatMap { DateFormatter.dateTimeMinute.date(from: $0) } }
    var dueByDate: Date? { due_by.flatMap { DateFormatter.dateTimeMinute.date(from: $0) } }

    /// The prediction has outlived its window — the nap either happened and
    /// wasn't logged, or the day moved on. Showing it after this point states a
    /// time in the past as though it were still coming.
    var isStale: Bool { dueByDate.map { $0 < Date() } ?? false }
    /// Inside the window: not "coming up" any more, but "now".
    var isDueNow: Bool {
        guard let from = dueFromDate, !isStale else { return false }
        return from <= Date()
    }
}

/// When to start the bedtime routine, from the bedtime actually kept. Nil until
/// there are a few nights logged — one early night shouldn't set the reminder.
struct BedtimePrep: Codable {
    let start_time: String?     // "HH:mm"
    let bedtime: String?        // the observed average, already formatted
    let lead_minutes: Int?
    let based_on_nights: Int?
    let spread_minutes: Int?
    let basis: String?

    /// Hour and minute for a repeating daily trigger.
    var startComponents: (hour: Int, minute: Int)? {
        guard let parts = start_time?.split(separator: ":"), parts.count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return (h, m)
    }
}

// MARK: - Sleep statistics

/// GET /api/routines/:id/sleep-stats — what the logged sleeps actually say,
/// measured against the age-appropriate AASM/AAP range, plus earned tips.
struct SleepStats: Codable {
    let window_days: Int?
    let days: [SleepDay]
    let totals: SleepTotals
    let bedtime: SleepClock?
    let wake_time: SleepClock?
    let trend: SleepTrend?
    let guidance: SleepStatsGuidance?
    let tips: [SleepTip]

    var hasData: Bool { (totals.days_logged ?? 0) > 0 }
}

struct SleepDay: Codable, Identifiable {
    let date: String
    let total_minutes: Int
    let night_minutes: Int
    let nap_minutes: Int
    let nap_count: Int
    let wake_count: Int

    var id: String { date }
}

struct SleepTotals: Codable {
    let nights_logged: Int?
    let days_logged: Int?
    let avg_daily_minutes: Int?
    let avg_night_minutes: Int?
    let avg_nap_minutes: Int?
    let avg_naps_per_day: Double?
    let avg_wakings: Double?
    let longest_stretch_minutes: Int?
    let last_night_minutes: Int?
}

struct SleepClock: Codable {
    let average: String?
    let earliest: String?
    let latest: String?
    let spread_minutes: Int?
}

struct SleepTrend: Codable {
    let daily_delta_minutes: Int?
    let prior_avg_daily_minutes: Int?
}

struct SleepStatsGuidance: Codable {
    let age_label: String?
    let recommended_min_minutes: Int?
    let recommended_max_minutes: Int?
    let recommended_label: String?
    let nap_label: String?
    let note: String?
    let source: String?
}

struct SleepTip: Codable, Identifiable {
    let key: String
    let severity: String?
    let title: String
    let detail: String
    let source: String?

    var id: String { key }
    /// 'watch' tips are worth a second look; everything else is reassurance.
    var isWatch: Bool { severity == "watch" }
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
