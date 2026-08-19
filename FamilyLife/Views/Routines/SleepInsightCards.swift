import SwiftUI

// The two cards that answer "why is he waking at 4am, and what do we try?"
// without anyone having to open the concierge. They render the same analysis
// the concierge reasons over, so the app and the chat can never tell a parent
// two different stories about the same nights.

// MARK: - The pattern

/// When the wakings happen, whether they follow a rhythm, and what was
/// different about the days that preceded them.
///
/// Every number here is observed, never predicted. The card is deliberately
/// silent until there's a repeating waking to describe — one rough night is not
/// a pattern, and naming it as one would be its own kind of lie.
struct SleepPatternCard: View {
    let analysis: SleepWakingAnalysis
    let accent: Color

    var body: some View {
        if let cluster = analysis.cluster, let time = cluster.typical_time {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WarmPalette.ink3)
                    Text("The pattern")
                        .font(.flHeadline)
                        .foregroundStyle(WarmPalette.ink1)
                    Spacer()
                    if let nights = analysis.nights_analyzed {
                        Text("\(nights) nights")
                            .font(.flFootnote)
                            .foregroundStyle(WarmPalette.ink3)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Waking around \(time)")
                        .font(.flTitle)
                        .foregroundStyle(WarmPalette.ink1)
                    if let frequency = cluster.frequencyText {
                        Text(rhythmLine(frequency: frequency))
                            .font(.flSubheadline)
                            .foregroundStyle(WarmPalette.ink2)
                    }
                    if let awake = cluster.median_awake_minutes, awake > 0 {
                        Text("Awake about \(SleepValue.durationText(minutes: awake)) before settling again")
                            .font(.flFootnote)
                            .foregroundStyle(WarmPalette.ink3)
                    }
                }

                if !analysis.nights.isEmpty {
                    nightStrip(analysis.nights)
                }

                if !analysis.differences.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What was different on those nights")
                            .font(.flOverline)
                            .foregroundStyle(WarmPalette.ink3)
                        ForEach(analysis.differences) { diff in
                            differenceRow(diff)
                        }
                    }
                }

                if let basis = analysis.basis {
                    Text(basis)
                        .font(.flCaption2)
                        .foregroundStyle(WarmPalette.ink4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .flCard()
        }
    }

    /// "7 of the last 14 nights, roughly every second night" — the rhythm is
    /// only named when the analysis was confident enough to name it.
    private func rhythmLine(frequency: String) -> String {
        guard let rhythm = analysis.rhythm, let label = rhythm.label,
              rhythm.confidence != "low" else { return frequency }
        return "\(frequency) — \(label)"
    }

    /// One mark per night, oldest to newest: a filled mark is a night with a
    /// waking. An alternating rhythm is visible here at a glance, which is
    /// what makes the claim above believable rather than something to trust.
    private func nightStrip(_ nights: [SleepNightDetail]) -> some View {
        HStack(spacing: 3) {
            ForEach(nights.reversed()) { night in
                RoundedRectangle(cornerRadius: 2)
                    .fill(night.wasDisturbed ? accent : WarmPalette.ink4.opacity(0.22))
                    .frame(height: night.wasDisturbed ? 18 : 10)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 20)
        .accessibilityElement()
        .accessibilityLabel("\(nights.filter(\.wasDisturbed).count) of \(nights.count) nights had a waking, oldest first")
    }

    private func differenceRow(_ diff: SleepNightDifference) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: (diff.delta_minutes ?? 0) > 0 ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accent)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(diff.label)
                    .font(.flFootnote.weight(.medium))
                    .foregroundStyle(WarmPalette.ink1)
                if let disturbed = diff.disturbed_value, let settled = diff.settled_value,
                   let direction = diff.direction {
                    Text("\(disturbed) on the disturbed nights, \(settled) on the settled ones — \(direction)")
                        .font(.flCaption)
                        .foregroundStyle(WarmPalette.ink3)
                }
            }
        }
    }
}

// MARK: - What to try

/// The recommendations, in the order the data supports them. Each one opens to
/// show the observation that earned it and the research behind it — a parent
/// deciding whether to change their child's night deserves to see both.
struct SleepRecommendationsCard: View {
    let recommendations: SleepRecommendations
    let accent: Color
    /// Hands the question to the concierge, which reads this same analysis and
    /// can answer the follow-ups a card can't. Gated exactly like
    /// WarmEmptyState's prompt: without cloud AI the button would navigate to
    /// the concierge and silently drop the question.
    var conciergePrompt: String?

    @Environment(ConciergeLaunch.self) private var conciergeLaunch: ConciergeLaunch?
    @AppStorage("aiConciergeEnabled") private var aiConciergeEnabled = false
    @AppStorage("cloudAIEnabled") private var cloudAIEnabled = true

    var body: some View {
        if !recommendations.items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent)
                    Text("What to try")
                        .font(.flHeadline)
                        .foregroundStyle(WarmPalette.ink1)
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(recommendations.items) { item in
                        RecommendationRow(item: item, accent: accent)
                    }
                }

                if let conciergePrompt, aiConciergeEnabled, cloudAIEnabled, let conciergeLaunch {
                    Button {
                        conciergeLaunch.ask(conciergePrompt)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Ask the concierge about this")
                                .font(.flFootnote.weight(.medium))
                        }
                        .foregroundStyle(accent)
                    }
                    .buttonStyle(.plain)
                }

                if let note = recommendations.note {
                    Text(note)
                        .font(.flCaption2)
                        .foregroundStyle(WarmPalette.ink4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .flCard(tint: accent.opacity(0.05))
        }
    }
}

private struct RecommendationRow: View {
    let item: SleepRecommendation
    let accent: Color
    @State private var expanded = false

    var body: some View {
        Button {
            withAnimation(.snappy) { expanded.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Text(item.title)
                        .font(.flSubheadline.weight(.medium))
                        .foregroundStyle(WarmPalette.ink1)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WarmPalette.ink4)
                }

                // The observation stays visible collapsed: it is the reason to
                // trust the headline, so hiding it behind a tap would make the
                // card feel like it was guessing.
                if let because = item.because {
                    Text(because)
                        .font(.flCaption)
                        .foregroundStyle(WarmPalette.ink3)
                        .multilineTextAlignment(.leading)
                        .lineLimit(expanded ? nil : 2)
                }

                if expanded {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(Array(item.what_to_try.enumerated()), id: \.offset) { _, step in
                            HStack(alignment: .top, spacing: 7) {
                                Circle()
                                    .fill(accent)
                                    .frame(width: 4, height: 4)
                                    .padding(.top, 7)
                                Text(step)
                                    .font(.flFootnote)
                                    .foregroundStyle(WarmPalette.ink2)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                    }
                    if let note = item.note {
                        Text(note)
                            .font(.flCaption)
                            .foregroundStyle(WarmPalette.ink3)
                            .multilineTextAlignment(.leading)
                    }
                    if let source = item.source {
                        HStack(spacing: 5) {
                            // The evidence rating is the honest part: a rule of
                            // thumb must not be able to pass itself off as an
                            // RCT just because it sits in the same list.
                            Text(item.isStrongEvidence ? "Strong evidence" : "Rule of thumb")
                                .font(.flCaption2.weight(.semibold))
                                .foregroundStyle(item.isStrongEvidence ? WarmPalette.good : WarmPalette.ink3)
                            Text(source)
                                .font(.flCaption2)
                                .foregroundStyle(WarmPalette.ink4)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("Pattern") {
    ScrollView {
        VStack(spacing: 12) {
            SleepPatternCard(analysis: .preview, accent: TabAccent.routines.color)
            SleepRecommendationsCard(recommendations: .preview,
                                     accent: TabAccent.routines.color,
                                     conciergePrompt: "Why is Jude waking at 4am every second night?")
        }
        .padding()
    }
    .background(WarmPalette.cream1)
}

extension SleepWakingAnalysis {
    /// Jude's fortnight: a 4am waking on every second night, with the last nap
    /// running an hour later on the nights that break.
    static var preview: SleepWakingAnalysis {
        SleepWakingAnalysis(
            window_days: 14,
            nights_analyzed: 14,
            nights_with_timed_wakings: 7,
            total_wakings: 7,
            avg_wakings_per_night: 1.0,
            cluster: SleepWakingCluster(
                typical_time: "4:00am", typical_time_minutes: 240,
                earliest: "3:50am", latest: "4:15am",
                nights_affected: 7, nights_logged: 14, waking_count: 7,
                median_awake_minutes: 25, dates: []
            ),
            rhythm: SleepWakingRhythm(
                pattern: "alternating", label: "roughly every second night",
                consecutive_pairs: 13, alternating_pairs: 13, confidence: "high",
                detail: "Of 13 back-to-back night pairs, 13 flipped."
            ),
            differences: [
                SleepNightDifference(
                    key: "last_nap_end", label: "Last nap ended", phrase: "when the last nap ends",
                    lever: "the time the last nap ends", disturbed_value: "4:00pm",
                    settled_value: "3:00pm", delta_minutes: 60, direction: "later",
                    summary: "An hour later on the disturbed nights."
                ),
                SleepNightDifference(
                    key: "bedtime", label: "Bedtime", phrase: "bedtime", lever: "bedtime",
                    disturbed_value: "7:40pm", settled_value: "7:15pm",
                    delta_minutes: 25, direction: "later", summary: "25m later."
                ),
            ],
            nights: (0..<14).map { i in
                SleepNightDetail(
                    date: "2026-08-\(String(format: "%02d", 5 + i))",
                    bedtime: i % 2 == 1 ? "7:40pm" : "7:15pm", morning_wake: "6:45am",
                    night_minutes: 640, nap_minutes: 165, nap_count: 2,
                    last_nap_end: i % 2 == 1 ? "4:00pm" : "3:00pm",
                    pre_bed_window_minutes: i % 2 == 1 ? 220 : 255,
                    waking_count: i % 2 == 1 ? 1 : 0,
                    wakings: i % 2 == 1 ? [SleepWakingEvent(at: "4:00am", awake_minutes: 25)] : []
                )
            },
            basis: "Patterns observed in your own log over the last 14 nights."
        )
    }
}

extension SleepRecommendations {
    static var preview: SleepRecommendations {
        SleepRecommendations(items: [
            SleepRecommendation(
                key: "alternating_pattern",
                title: "The every-second-night pattern tracks when the last nap ends",
                because: "Of 13 back-to-back night pairs, 13 flipped between a disturbed night and a settled one. Last nap ended was 1h later on the disturbed nights (4:00pm vs 3:00pm).",
                what_to_try: [
                    "Hold the time the last nap ends steady for a week — match the settled nights (3:00pm), not the average.",
                    "Change one thing only, and give it 5–7 nights before judging it.",
                ],
                source: "Mindell et al. 2015 — bedtime routine dose-response (n=10,085)",
                strength: "strong",
                note: "An alternating rhythm usually means something in the day alternates too.",
                method_key: nil
            ),
            SleepRecommendation(
                key: "early_morning_waking",
                title: "Treat the 4:00am waking as an early-morning waking",
                because: "Wakings cluster at 4:00am on 7 of 14 logged nights.",
                what_to_try: [
                    "Make the room properly dark and keep it dark until your chosen morning time.",
                    "Hold the same response you would use at midnight.",
                ],
                source: "Common pediatric sleep guidance (NHS)",
                strength: "rule of thumb",
                note: nil,
                method_key: nil
            ),
        ], note: "Educational guidance, not medical advice — change one thing at a time.")
    }
}
