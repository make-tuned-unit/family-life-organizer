import SwiftUI

/// The sleep bar on Home: how long they have been awake (or asleep), and when
/// the next sleep is due — so checking the nap schedule doesn't mean opening
/// Routines and reading a log.
///
/// It ticks. A static "awake 1h 45m" rendered at launch is wrong within a
/// minute, and this is the one number on the screen a parent does arithmetic
/// with, so the elapsed time and the countdown re-render every 30 seconds.
struct SleepBar: View {
    let summary: SleepNowSummary
    var onTap: () -> Void

    private var accent: Color { TabAccent.routines.color }

    var body: some View {
        Button(action: onTap) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                content(now: context.date)
            }
        }
        .buttonStyle(.flCardPress)
    }

    private func content(now: Date) -> some View {
        HStack(spacing: 12) {
            Image(systemName: summary.isAsleep ? "moon.zzz.fill" : "sun.max.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 34, height: 34)
                .background(Circle().fill(accent.opacity(0.12)))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(summary.displayName)
                        .font(.flHeadline)
                        .foregroundStyle(WarmPalette.ink1)
                    Text(stateText(now: now))
                        .font(.flSubheadline)
                        .foregroundStyle(WarmPalette.ink2)
                }
                Text(detailText(now: now))
                    .font(.flFootnote)
                    .foregroundStyle(isOverdue(now: now) ? AccentTheme.terracotta.color : WarmPalette.ink3)
                    .lineLimit(1)

                // The fill is the wake window filling up, so "how much longer"
                // is readable without doing the subtraction. Only drawn when
                // there's a real predicted window behind it.
                if let progress = summary.wakeWindowProgress(now: now) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(WarmPalette.ink4.opacity(0.18))
                            Capsule()
                                .fill(progress >= 1 ? AccentTheme.terracotta.color : accent)
                                .frame(width: max(3, geo.size.width * progress))
                        }
                    }
                    .frame(height: 4)
                    .padding(.top, 3)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WarmPalette.ink4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .flCard(tint: accent.opacity(0.07))
    }

    // MARK: - Copy

    /// "Awake 1h 45m" / "Napping 40m". Falls back to the bare state when there
    /// is nothing logged to count from — an invented start time would be worse
    /// than no number.
    private func stateText(now: Date) -> String {
        let verb = summary.isAsleep
            ? (summary.asleep_kind == "night_sleep" ? "Asleep" : "Napping")
            : "Awake"
        guard let since = summary.since else { return verb }
        let minutes = max(0, Int(now.timeIntervalSince(since) / 60))
        return "\(verb) \(SleepValue.durationText(minutes: minutes))"
    }

    /// The line under the name: when the next sleep is due, or when this one
    /// started. Never states a prediction that has already expired.
    private func detailText(now: Date) -> String {
        if summary.isAsleep {
            if let since = summary.asleepSinceDate {
                return "Down at \(DateFormatter.shortTime.string(from: since))"
            }
            return "Sleeping now"
        }
        if let next = summary.next_sleep, !next.isStale, let due = next.dueFromDate {
            if due > now {
                let mins = max(0, Int(due.timeIntervalSince(now) / 60))
                let kind = next.last_sleep_type == "night_sleep" ? "First nap" : "Next nap"
                return "\(kind) around \(DateFormatter.shortTime.string(from: due)) · in \(SleepValue.durationText(minutes: mins))"
            }
            return "Nap window opened at \(DateFormatter.shortTime.string(from: due))"
        }
        // No prediction: the bedtime routine is the next useful thing to say.
        if let prep = summary.bedtime_prep, let bedtime = prep.bedtime {
            return "Bedtime routine around \(displayTime(prep.start_time)) for a \(bedtime) bedtime"
        }
        return "Log a sleep to see when the next nap is due"
    }

    /// Past the far end of the wake window — worth colouring, since the useful
    /// signal at that point is "they are getting overtired".
    private func isOverdue(now: Date) -> Bool {
        guard !summary.isAsleep, let next = summary.next_sleep, !next.isStale,
              let due = next.dueFromDate else { return false }
        return due <= now
    }

    /// "18:45" as stored → "6:45 PM" for display.
    private func displayTime(_ raw: String?) -> String {
        guard let raw else { return "—" }
        guard let date = DateFormatter.hourMinute.date(from: raw) else { return raw }
        return DateFormatter.shortTime.string(from: date)
    }
}

#Preview("Awake, nap due soon") {
    VStack(spacing: 12) {
        SleepBar(summary: .preview(state: "awake")) {}
        SleepBar(summary: .preview(state: "awake", overdue: true)) {}
        SleepBar(summary: .preview(state: "asleep")) {}
        SleepBar(summary: .preview(state: "awake", empty: true)) {}
    }
    .padding()
    .background(WarmPalette.cream1)
}

extension SleepNowSummary {
    /// Mock rows for previews. Times are built relative to now so the bar shows
    /// a live elapsed count rather than a frozen one.
    static func preview(state: String, overdue: Bool = false, empty: Bool = false) -> SleepNowSummary {
        let fmt = DateFormatter.dateTimeMinute
        let wokeAt = Date().addingTimeInterval(overdue ? -3.5 * 3600 : -1.75 * 3600)
        let dueFrom = wokeAt.addingTimeInterval(3 * 3600)
        return SleepNowSummary(
            routine_id: 1,
            name: "Jude sleep",
            subject_name: "Jude",
            routine_type: "baby_sleep",
            color: nil,
            state: state,
            asleep_kind: state == "asleep" ? "nap" : nil,
            asleep_since: state == "asleep" ? fmt.string(from: Date().addingTimeInterval(-40 * 60)) : nil,
            awake_since: (state == "awake" && !empty) ? fmt.string(from: wokeAt) : nil,
            last_sleep_type: "nap",
            next_sleep: (state == "awake" && !empty) ? NextSleepWindow(
                last_wake_at: fmt.string(from: wokeAt),
                last_sleep_type: "nap",
                wake_window_label: "about 3–4 hours",
                due_from: fmt.string(from: dueFrom),
                due_by: fmt.string(from: dueFrom.addingTimeInterval(3600)),
                prepare_at: fmt.string(from: dueFrom.addingTimeInterval(-15 * 60)),
                lead_minutes: 15,
                basis: "Typical wake windows used in pediatric sleep guidance."
            ) : nil,
            bedtime_prep: empty ? BedtimePrep(
                start_time: "18:45", bedtime: "7:15pm", lead_minutes: 30,
                based_on_nights: 6, spread_minutes: 12, basis: nil
            ) : nil,
            last_night_minutes: 675,
            avg_wakings: 1.4
        )
    }
}
