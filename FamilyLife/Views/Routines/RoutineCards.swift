import SwiftUI

// Shared helpers + the type-specific cards for a routine's detail screen:
// CycleCard (period / TTC), ActivityAchievementCard, and ConfirmAttendanceCard.

private let routineAccent = TabAccent.routines.color

/// Parse a "yyyy-MM-dd" API date and format it warmly (e.g. "Jul 8"). Falls back
/// to the raw string if parsing fails.
func routineShortDate(_ iso: String) -> String {
    let inFmt = DateFormatter()
    inFmt.calendar = Calendar(identifier: .gregorian)
    inFmt.locale = Locale(identifier: "en_US_POSIX")
    inFmt.dateFormat = "yyyy-MM-dd"
    guard let d = inFmt.date(from: String(iso.prefix(10))) else { return iso }
    let out = DateFormatter()
    out.dateFormat = "MMM d"
    return out.string(from: d)
}

// MARK: - Cycle card

private func cyclePhaseInfo(_ phase: String?) -> (label: String, blurb: String, color: Color, icon: String) {
    switch phase {
    case "menstrual":  return ("Your period", "Your body is shedding its lining. Rest and be kind to yourself.", AccentTheme.rose.color, "drop.fill")
    case "follicular": return ("Follicular phase", "Your body is preparing an egg. Energy often starts to build.", AccentTheme.sage.color, "leaf.fill")
    case "fertile":    return ("Fertile window", "The days you're most likely to conceive — the five days before ovulation, plus ovulation day.", AccentTheme.saffron.color, "sparkles")
    case "ovulation":  return ("Ovulation (estimated)", "An egg is likely released around now — your peak fertile day, though timing varies.", AccentTheme.terracotta.color, "sun.max.fill")
    case "luteal":     return ("Luteal phase", "Your body waits to see if pregnancy begins. Some notice mood or energy shifts before their period.", AccentTheme.mauve.color, "moon.fill")
    default:           return ("Your cycle", "", routineAccent, "circle.dashed")
    }
}

struct CycleCard: View {
    let cycle: CyclePrediction

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text(cycle.isTTC ? "Trying to conceive" : "Cycle")
                    .font(.flCaption2.weight(.semibold))
                    .foregroundStyle(routineAccent)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(routineAccent.opacity(0.12), in: Capsule())
                Spacer()
                if let day = cycle.current_cycle_day {
                    Text("Day \(day)")
                        .font(.flCaption.weight(.medium))
                        .foregroundStyle(WarmPalette.ink3)
                }
            }

            if cycle.insufficient == true {
                Text(cycle.note ?? "Log the first day of your period to begin.")
                    .font(.flSubheadline)
                    .foregroundStyle(WarmPalette.ink2)
            } else {
                let phase = cyclePhaseInfo(cycle.current_phase)
                HStack(spacing: 10) {
                    Image(systemName: phase.icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(phase.color)
                    Text(phase.label)
                        .font(.flHeadline)
                        .foregroundStyle(WarmPalette.ink1)
                }
                if !phase.blurb.isEmpty {
                    Text(phase.blurb)
                        .font(.flFootnote)
                        .foregroundStyle(WarmPalette.ink3)
                }

                // Next period / late.
                if let next = cycle.next_period_date {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.system(size: 13))
                            .foregroundStyle(routineAccent)
                        if cycle.is_late == true {
                            Text("Period is \(cycle.late_by_days ?? 0) day\(cycle.late_by_days == 1 ? "" : "s") late")
                                .font(.flSubheadline.weight(.medium))
                                .foregroundStyle(WarmPalette.ink1)
                        } else {
                            Text("Next period \(periodPhrase) · \(routineShortDate(next))")
                                .font(.flSubheadline.weight(.medium))
                                .foregroundStyle(WarmPalette.ink1)
                        }
                    }
                }

                // TTC: fertile window range (never a single day).
                if cycle.isTTC {
                    if let fw = cycle.fertile_window {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 13))
                                .foregroundStyle(AccentTheme.saffron.color)
                            Text("Fertile window \(routineShortDate(fw.start))–\(routineShortDate(fw.end))")
                                .font(.flSubheadline.weight(.medium))
                                .foregroundStyle(WarmPalette.ink1)
                        }
                        if let ov = cycle.predicted_ovulation_date {
                            Text("Ovulation likely around \(routineShortDate(ov)) — an estimate that can shift a few days.")
                                .font(.flFootnote)
                                .foregroundStyle(WarmPalette.ink3)
                        }
                    } else if let note = cycle.fertile_note {
                        Text(note)
                            .font(.flFootnote)
                            .foregroundStyle(WarmPalette.ink3)
                    }
                }

                // Metadata pills.
                HStack(spacing: 8) {
                    if let avg = cycle.average_cycle_length {
                        metaPill("\(avg)-day cycle")
                    }
                    if let conf = cycle.confidence {
                        metaPill("\(conf.capitalized) confidence")
                    }
                    if cycle.irregular == true {
                        metaPill("Irregular")
                    }
                }
            }

            // Persistent, plain-language disclaimer (research: never frame as contraception).
            Text(cycle.disclaimer)
                .font(.flCaption2)
                .foregroundStyle(WarmPalette.ink4)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .flCard(tint: routineAccent.opacity(0.05))
    }

    private var periodPhrase: String {
        guard let n = cycle.days_until_period else { return "soon" }
        if n <= 0 { return "due" }
        if n == 1 { return "tomorrow" }
        return "in \(n) days"
    }

    private func metaPill(_ text: String) -> some View {
        Text(text)
            .font(.flCaption2.weight(.medium))
            .foregroundStyle(WarmPalette.ink3)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(WarmPalette.cardSurface, in: Capsule())
    }
}

// MARK: - Activity achievements card

struct ActivityAchievementCard: View {
    let achievements: RoutineAchievements

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(achievements.total_sessions)")
                    .font(.flHero)
                    .foregroundStyle(routineAccent)
                Text(achievements.total_sessions == 1 ? "session" : "sessions")
                    .font(.flSubheadline)
                    .foregroundStyle(WarmPalette.ink2)
                Spacer()
                if achievements.current_streak_weeks > 0 {
                    Label("\(achievements.current_streak_weeks)-week streak", systemImage: "flame.fill")
                        .font(.flCaption.weight(.semibold))
                        .foregroundStyle(AccentTheme.terracotta.color)
                }
            }

            // Progress toward the next milestone.
            if let next = achievements.next_milestone {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(next.title)
                            .font(.flSubheadline.weight(.semibold))
                            .foregroundStyle(WarmPalette.ink1)
                        Spacer()
                        Text("\(next.remaining) to go")
                            .font(.flCaption.weight(.medium))
                            .foregroundStyle(routineAccent)
                    }
                    ProgressView(value: Double(achievements.total_sessions), total: Double(next.count))
                        .tint(routineAccent)
                    Text(next.blurb)
                        .font(.flFootnote)
                        .foregroundStyle(WarmPalette.ink3)
                }
            } else {
                Text("Every milestone unlocked. Legendary consistency.")
                    .font(.flFootnote)
                    .foregroundStyle(WarmPalette.ink3)
            }

            // Earned badges.
            if !achievements.earned.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Milestones earned")
                        .font(.flCaption.weight(.semibold))
                        .foregroundStyle(WarmPalette.ink3)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(achievements.earned) { badge in
                            Label(badge.title, systemImage: "checkmark.seal.fill")
                                .font(.flCaption2.weight(.medium))
                                .foregroundStyle(routineAccent)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(routineAccent.opacity(0.10), in: Capsule())
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .flCard(tint: routineAccent.opacity(0.05))
    }
}

// MARK: - Confirm attendance (from linked calendar events)

struct ConfirmAttendanceCard: View {
    let pending: [RoutineOccurrence]
    let activity: String
    let onConfirm: (_ date: String, _ attended: Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Did you go?", systemImage: "questionmark.circle.fill")
                .font(.flSubheadline.weight(.semibold))
                .foregroundStyle(WarmPalette.ink1)
            Text("Confirm the \(activity) sessions on your calendar so they count toward your milestones.")
                .font(.flFootnote)
                .foregroundStyle(WarmPalette.ink3)
            ForEach(pending.prefix(5)) { occ in
                HStack(spacing: 10) {
                    Text(routineShortDate(occ.date))
                        .font(.flSubheadline.weight(.medium))
                        .foregroundStyle(WarmPalette.ink1)
                    Spacer()
                    Button { onConfirm(occ.date, true) } label: {
                        Text("Yes")
                            .font(.flFootnote.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(routineAccent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Button { onConfirm(occ.date, false) } label: {
                        Text("Skip")
                            .font(.flFootnote.weight(.medium))
                            .foregroundStyle(WarmPalette.ink3)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(WarmPalette.cardSurface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .flCard()
    }
}

#Preview("Cycle") {
    ScrollView {
        VStack(spacing: 16) {
            CycleCard(cycle: CyclePrediction(
                mode: "ttc", disclaimer: "For information only — not medical advice, and not a form of birth control.",
                cycles_tracked: 4, insufficient: nil, note: nil, current_cycle_day: 12,
                average_cycle_length: 28, cycle_variability_days: 1, period_length: 5,
                next_period_date: "2026-07-27", days_until_period: 16, is_late: false, late_by_days: 0,
                current_phase: "fertile", confidence: "high", irregular: false,
                predicted_ovulation_date: "2026-07-13",
                fertile_window: FertileWindow(start: "2026-07-08", end: "2026-07-14"), fertile_note: nil))
            ActivityAchievementCard(achievements: RoutineAchievements(
                total_sessions: 7, current_streak_weeks: 3, last_session_date: "2026-07-06",
                earned: [AchievementBadge(count: 1, title: "First session", blurb: ""), AchievementBadge(count: 5, title: "5 sessions", blurb: "")],
                next_milestone: NextMilestone(count: 10, title: "10 sessions", blurb: "Double digits — real momentum.", remaining: 3),
                latest: "5 sessions"))
            ConfirmAttendanceCard(pending: [RoutineOccurrence(date: "2026-07-06", confirmed: false, past: true, today: false)], activity: "violin") { _, _ in }
        }
        .padding()
    }
    .background { AmbientBackground(style: .home) }
}
