import SwiftUI

/// Today's chores on Home: one row per child with a tappable dot per open
/// slot — so "fed the dog" is one tap from the front page rather than a trip
/// into Routines. Ticks are optimistic; the server's recomputed week replaces
/// the row when it lands.
struct ChoreBar: View {
    let summary: ChoresTodaySummary
    var onToggle: (String, String) -> Void      // chore id, slot
    var onTap: () -> Void

    private var accent: Color { TabAccent.routines.color }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    Image(systemName: summary.open_slots == 0 ? "checkmark.seal.fill" : "checkmark.seal")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(accent.opacity(0.12)))

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(summary.displayName)
                                .font(.flHeadline)
                                .foregroundStyle(WarmPalette.ink1)
                            Text(stateText)
                                .font(.flSubheadline)
                                .foregroundStyle(WarmPalette.ink2)
                        }
                        Text(detailText)
                            .font(.flFootnote)
                            .foregroundStyle(WarmPalette.ink3)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.flCardPress)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                ForEach(summary.chores) { chore in
                    ForEach(chore.slots) { slot in
                        Button { onToggle(chore.id, slot.slot) } label: {
                            ZStack {
                                Circle()
                                    .fill(slot.done ? accent : WarmPalette.ink4.opacity(0.14))
                                    .frame(width: 30, height: 30)
                                Image(systemName: slot.done ? "checkmark" : slotGlyph(chore: chore, slot: slot))
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(slot.done ? .white : WarmPalette.ink3)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(chore.title), \(slot.label)")
                        .accessibilityValue(slot.done ? "done" : "not done")
                    }
                }
            }
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .flCard(tint: summary.open_slots == 0 ? accent.opacity(0.05) : .clear)
    }

    private func slotGlyph(chore: ChoresTodayChore, slot: ChoreSlotState) -> String {
        chore.slots.count > 1 ? slot.icon : chore.icon
    }

    private var stateText: String {
        if summary.total_slots == 0 { return "no chores today" }
        if summary.open_slots == 0 { return "all done" }
        return "\(summary.total_slots - summary.open_slots) of \(summary.total_slots) done"
    }

    private var detailText: String {
        var bits: [String] = []
        if summary.open_slots > 0, let next = summary.chores.first(where: { $0.slots.contains { !$0.done } }) {
            let slot = next.slots.first { !$0.done }
            bits.append(slot.map { $0.slot == "anytime" ? next.title : "\(next.title) · \($0.label.lowercased())" } ?? next.title)
        }
        if let n = summary.lifetime_done, n > 0 { bits.append("helped \(n)×") }
        if summary.week_total > 0 { bits.append(summary.week_total.formatted(.currency(code: summary.currency).precision(.fractionLength(0...2))) + " this week") }
        return bits.isEmpty ? "Chores" : bits.joined(separator: " · ")
    }
}

#Preview {
    let json = """
    {"routine_id":1,"name":"Jude's chores","subject_name":"Jude","color":null,"today":"2026-08-19",
     "chores":[{"id":"dog","title":"Feed the dog","icon":"pawprint.fill","slots":[{"slot":"morning","done":true,"entry_id":1},{"slot":"evening","done":false,"entry_id":null}]}],
     "open_slots":1,"total_slots":2,"streak_days":4,"week_total":3,"currency":"USD"}
    """
    let s = try! JSONDecoder().decode(ChoresTodaySummary.self, from: Data(json.utf8))
    return VStack { ChoreBar(summary: s, onToggle: { _, _ in }, onTap: {}) }
        .padding()
        .background { AmbientBackground(style: .home) }
}
