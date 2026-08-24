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
    case chores
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .period:        "Cycle"
        case .babySleep:     "Baby sleep"
        case .sleepTraining: "Sleep training"
        case .activity:      "Activity"
        case .chores:        "Chores"
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
        case .chores:        "A child's chores, allowance, and an age-by-age program."
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
        case .chores:        "checkmark.seal.fill"
        case .custom:        "repeat"
        }
    }

    var needsBirthdate: Bool { self == .babySleep || self == .sleepTraining || self == .chores }
    var isChores: Bool { self == .chores }
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
    /// The week engine's output for a `chores` routine — nil for every other kind.
    let chores: ChoreSummary?
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

    /// True once today's wind-down time has arrived — the point the Home bar
    /// should talk about bedtime rather than an overdue morning nap.
    func hasStarted(now: Date = Date()) -> Bool {
        guard let (hour, minute) = startComponents,
              let start = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: now)
        else { return false }
        return now >= start
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
    /// When the night wakings happen and whether they follow a rhythm. Reads
    /// back further than the averages do — a fortnight, since an every-second-
    /// night pattern can't be told from bad luck in under two weeks.
    let wakings: SleepWakingAnalysis?
    /// What to change, earned by the data above.
    let recommendations: SleepRecommendations?

    var hasData: Bool { (totals.days_logged ?? 0) > 0 }
}

// MARK: - Night-waking analysis

/// The wakings pulled back out of the log: a disturbed night is recorded as
/// several night_sleep entries, so the gap between them is a waking with a
/// clock time attached. Nothing extra has to be logged for this to work.
struct SleepWakingAnalysis: Codable {
    let window_days: Int?
    let nights_analyzed: Int?
    let nights_with_timed_wakings: Int?
    let total_wakings: Int?
    let avg_wakings_per_night: Double?
    let cluster: SleepWakingCluster?
    let rhythm: SleepWakingRhythm?
    let differences: [SleepNightDifference]
    let nights: [SleepNightDetail]
    let basis: String?

    /// Nothing to show until there is a repeating waking to talk about.
    var hasPattern: Bool { cluster != nil }
}

/// The time of night the wakings gather around.
struct SleepWakingCluster: Codable {
    let typical_time: String?
    let typical_time_minutes: Int?
    let earliest: String?
    let latest: String?
    let nights_affected: Int?
    let nights_logged: Int?
    let waking_count: Int?
    let median_awake_minutes: Int?
    let dates: [String]?

    /// "7 of the last 14 nights" — the line that makes the pattern land.
    var frequencyText: String? {
        guard let hit = nights_affected, let total = nights_logged else { return nil }
        return "\(hit) of the last \(total) nights"
    }
}

/// Whether the cluster lands every second night, most nights, or without shape.
struct SleepWakingRhythm: Codable {
    let pattern: String?          // alternating | nightly | irregular
    let label: String?
    let consecutive_pairs: Int?
    let alternating_pairs: Int?
    let confidence: String?       // high | moderate | low
    let detail: String?

    var isAlternating: Bool { pattern == "alternating" }
}

/// One daytime factor that differs between the disturbed and settled nights.
/// A correlation over a handful of nights — never presented as a cause.
struct SleepNightDifference: Codable, Identifiable {
    let key: String
    let label: String
    let phrase: String?
    let lever: String?
    let disturbed_value: String?
    let settled_value: String?
    let delta_minutes: Int?
    let direction: String?
    let summary: String?

    var id: String { key }
}

struct SleepNightDetail: Codable, Identifiable {
    let date: String
    let bedtime: String?
    let morning_wake: String?
    let night_minutes: Int?
    let nap_minutes: Int?
    let nap_count: Int?
    let last_nap_end: String?
    let pre_bed_window_minutes: Int?
    let waking_count: Int?
    let wakings: [SleepWakingEvent]

    var id: String { date }
    var wasDisturbed: Bool { (waking_count ?? 0) > 0 }
}

struct SleepWakingEvent: Codable, Hashable {
    let at: String?
    let awake_minutes: Int?
}

// MARK: - Recommendations

/// "What to try" — each item states the observation that earned it and names
/// the research behind it, so a parent can check the reasoning before acting.
struct SleepRecommendations: Codable {
    let items: [SleepRecommendation]
    let note: String?
}

struct SleepRecommendation: Codable, Identifiable {
    let key: String
    let title: String
    /// The observed numbers this is reacting to.
    let because: String?
    let what_to_try: [String]
    let source: String?
    /// "strong" for the consensus/RCT-backed levers, "rule of thumb" otherwise.
    let strength: String?
    let note: String?
    let method_key: String?

    var id: String { key }
    var isStrongEvidence: Bool { strength == "strong" }
}

// MARK: - Live sleep status (Home)

/// GET /api/routines/sleep-now — one row per sleep routine the caller can see:
/// asleep or awake right now, since when, and when the next sleep is due.
/// Powers the Home sleep bar so checking the next nap doesn't mean a trip into
/// Routines.
struct SleepNowSummary: Codable, Identifiable {
    let routine_id: Int
    let name: String
    let subject_name: String?
    let routine_type: String?
    let color: String?
    let state: String            // asleep | awake
    let asleep_kind: String?     // nap | night_sleep
    let asleep_since: String?
    let awake_since: String?
    let last_sleep_type: String?
    let next_sleep: NextSleepWindow?
    let bedtime_prep: BedtimePrep?
    let last_night_minutes: Int?
    let avg_wakings: Double?

    var id: Int { routine_id }
    var isAsleep: Bool { state == "asleep" }
    /// First name only — the bar is glanceable, not a report.
    var displayName: String { subject_name ?? name }

    var asleepSinceDate: Date? { asleep_since.flatMap { DateFormatter.dateTimeMinute.date(from: $0) } }
    var awakeSinceDate: Date? { awake_since.flatMap { DateFormatter.dateTimeMinute.date(from: $0) } }

    /// The moment the current state began, whichever state that is. Nil when
    /// there's nothing logged to count from — the bar must then stay quiet
    /// rather than count from an invented time.
    var since: Date? { isAsleep ? asleepSinceDate : awakeSinceDate }

    /// How far through the typical wake window they are, 0–1. Drives the bar's
    /// fill. Nil while asleep or without a predicted window.
    func wakeWindowProgress(now: Date = Date()) -> Double? {
        guard !isAsleep, let from = awakeSinceDate,
              let due = next_sleep?.dueFromDate else { return nil }
        let total = due.timeIntervalSince(from)
        guard total > 0 else { return nil }
        return min(1, max(0, now.timeIntervalSince(from) / total))
    }
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

// MARK: - Chores (per-child routine: week grid, earnings, age guidance)

struct ChoreSlotState: Codable, Identifiable {
    let slot: String            // morning | afternoon | evening | anytime
    let done: Bool
    let entry_id: Int?
    var id: String { slot }

    var label: String {
        switch slot {
        case "morning":   "Morning"
        case "afternoon": "Afternoon"
        case "evening":   "Evening"
        default:          "Today"
        }
    }
    var icon: String {
        switch slot {
        case "morning":   "sunrise.fill"
        case "afternoon": "sun.max.fill"
        case "evening":   "moon.fill"
        default:          "checkmark"
        }
    }
}

struct ChoreDay: Codable, Identifiable {
    let date: String
    let applies: Bool
    let past: Bool
    let today: Bool
    let slots: [ChoreSlotState]
    var id: String { date }
    var allDone: Bool { !slots.isEmpty && slots.allSatisfy(\.done) }
    var anyDone: Bool { slots.contains { $0.done } }
}

struct ChoreState: Codable, Identifiable {
    let id: String
    let title: String
    let icon: String
    let slots: [String]
    let days: [ChoreDay]
    let done_count: Int
    let expected_count: Int
    let lifetime_count: Int
    var today: ChoreDay? { days.first { $0.today } }
}

struct ChoreBonusState: Codable, Identifiable {
    let id: String
    let title: String
    let amount: Double
    let icon: String
    let earned_dates: [ChoreBonusDate]
    let earned_this_week: Bool
}

struct ChoreBonusDate: Codable { let date: String; let entry_id: Int? }

struct ChoreEarnings: Codable {
    let currency: String
    let allowance: Double
    let bonus: Double
    let total: Double
    let payday: Int
    let paid: Bool
    let paid_amount: Double
    let payout_entry_id: Int?
}

struct ChoreUnpaidWeek: Codable, Identifiable {
    let week_start: String
    let week_end: String
    let amount: Double
    var id: String { week_start }
}

struct ChoreLedger: Codable {
    let unpaid_weeks: [ChoreUnpaidWeek]
    let owed: Double
    let lifetime_paid: Double
}

struct ChoreNudge: Codable {
    let kind: String            // start | soon | add | hold | steady
    let text: String
}

struct ChoreSuggestion: Codable, Identifiable {
    let title: String
    let icon: String
    let slots: [String]
    let note: String?
    var id: String { title }
}

struct ChoreGuidance: Codable {
    let age_years: Int?
    let band_key: String
    let band_title: String
    let age_label: String
    let chore_count: String
    let allowance_label: String
    let next_band: String?
    let suggested: [ChoreSuggestion]
    let nudge: ChoreNudge
}

struct ChoreSummary: Codable {
    let today: String
    let week_start: String
    let week_end: String
    let week_start_day: Int
    let chores: [ChoreState]
    let completion_pct: Int?
    let done_total: Int
    let expected_total: Int
    let streak_days: Int
    let lifetime_done: Int
    let bonuses: [ChoreBonusState]
    let earnings: ChoreEarnings
    let ledger: ChoreLedger
    let guidance: ChoreGuidance?
}

/// POST /api/routines/:id/chores/{toggle,bonus,payout} — the recomputed week.
struct ChoreMutationResponse: Codable {
    let success: Bool
    let chores: ChoreSummary
}

/// GET /api/routines/chores-today — one row per chores routine, for Home.
struct ChoresTodaySummary: Codable, Identifiable {
    let routine_id: Int
    let name: String
    let subject_name: String?
    let color: String?
    let today: String
    let chores: [ChoresTodayChore]
    let open_slots: Int
    let total_slots: Int
    let streak_days: Int
    let week_total: Double
    let currency: String
    var id: Int { routine_id }
    var displayName: String { subject_name ?? name }
}

struct ChoresTodayChore: Codable, Identifiable {
    let id: String
    let title: String
    let icon: String
    let slots: [ChoreSlotState]
}

// The static chores program (age bands + sources).

struct ChoreBandAllowance: Codable {
    let label: String
    let note: String
}

struct ChoreBand: Codable, Identifiable {
    let key: String
    let title: String
    let age_label: String
    let min_years: Int?
    let max_years: Int?
    let chore_count: String
    let description: String
    let suggested: [ChoreSuggestion]
    let steps: [String]
    let tips: [String]
    let allowance: ChoreBandAllowance
    let next_band: String?
    var id: String { key }
}

struct ChoresTemplate: Codable {
    let id: String
    let title: String
    let subtitle: String
    let disclaimer: String
    let principles: [String]
    let bands: [ChoreBand]
    let sources: [SleepSource]
}

/// The editable shape of a chores routine's `config` JSON. Mirrors what
/// `services/chores.js` `parseConfig` accepts.
struct ChoreConfig: Codable {
    struct Chore: Codable, Identifiable {
        var id: String
        var title: String
        var icon: String
        var slots: [String]
        var days: [Int]?
        var active: Bool?
        var started_on: String?
    }
    struct Allowance: Codable {
        var weekly_amount: Double
        var currency: String?
        var payday: Int?
    }
    struct Bonus: Codable, Identifiable {
        var id: String
        var title: String
        var amount: Double
        var icon: String?
    }
    var chores: [Chore]
    var allowance: Allowance
    var bonuses: [Bonus]
    var week_start: Int?

    static let empty = ChoreConfig(chores: [], allowance: Allowance(weekly_amount: 0, currency: "USD", payday: 0), bonuses: [], week_start: 1)

    static func decode(_ json: String?) -> ChoreConfig {
        guard let json, let data = json.data(using: .utf8),
              let cfg = try? JSONDecoder().decode(ChoreConfig.self, from: data) else { return .empty }
        return cfg
    }

    /// As the `[String: Any]` the API client sends.
    var jsonObject: [String: Any] {
        guard let data = try? JSONEncoder().encode(self),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return obj
    }
}
