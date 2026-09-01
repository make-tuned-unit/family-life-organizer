import SwiftUI

/// The kid-facing check-off modal. Opened by tapping a chore row on Home:
/// every slot becomes a big, thumb-of-a-five-year-old-sized button, and each
/// tick fires confetti so finishing a chore feels like winning. Parents reach
/// the full program (weeks, allowance, bonuses) via the toolbar.
struct ChoreCheckoffSheet: View {
    let routineId: Int
    var viewModel: HomeViewModel
    /// Swap this sheet for the full `RoutineDetailView` (handled by Home).
    var onOpenProgram: () -> Void

    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss
    @State private var confettiTrigger = 0
    @State private var confettiIntensity = 42

    private var accent: Color { TabAccent.routines.color }

    private var summary: ChoresTodaySummary? {
        viewModel.choresToday.first { $0.routine_id == routineId }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let summary {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: DesignTokens.Spacing.cardGap) {
                            header(summary)
                            ForEach(summary.chores) { chore in
                                choreCard(chore, summary: summary)
                            }
                            if summary.total_slots > 0, summary.open_slots == 0 {
                                allDoneBanner(summary)
                            }
                        }
                        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                        .padding(.top, 8)
                        .padding(.bottom, DesignTokens.Spacing.bottomBuffer)
                    }
                } else {
                    FLLoadingState(message: "Getting today's chores…")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { AmbientBackground(style: .home) }
            .navigationTitle(summary?.displayName ?? "Chores")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(WarmPalette.ink2)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { onOpenProgram() } label: {
                        Label("Program", systemImage: "chart.bar.doc.horizontal")
                            .font(.flSubheadline)
                    }
                    .foregroundStyle(WarmPalette.ink2)
                    .accessibilityLabel("Open full chore program")
                }
            }
            .overlay {
                ConfettiCelebration(trigger: confettiTrigger,
                                    origin: UnitPoint(x: 0.5, y: 0.45),
                                    intensity: confettiIntensity)
            }
            .sensoryFeedback(.success, trigger: confettiTrigger)
            .inlineError(viewModel.error) { viewModel.error = nil }
        }
    }

    // MARK: - Header

    private func header(_ summary: ChoresTodaySummary) -> some View {
        VStack(spacing: 6) {
            Image(systemName: summary.open_slots == 0 && summary.total_slots > 0
                    ? "checkmark.seal.fill" : "checkmark.seal")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(accent)
            Text(headline(summary))
                .font(.flTitle)
                .foregroundStyle(WarmPalette.ink1)
                .multilineTextAlignment(.center)
            if let sub = subheadline(summary) {
                Text(sub)
                    .font(.flSubheadline)
                    .foregroundStyle(WarmPalette.ink3)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func headline(_ summary: ChoresTodaySummary) -> String {
        if summary.total_slots == 0 { return "No chores today!" }
        if summary.open_slots == 0 { return "All done — amazing!" }
        let done = summary.total_slots - summary.open_slots
        return done == 0 ? "Ready to go?" : "\(done) of \(summary.total_slots) done — keep going!"
    }

    private func subheadline(_ summary: ChoresTodaySummary) -> String? {
        var bits: [String] = []
        if summary.streak_days > 1 { bits.append("\(summary.streak_days)-day streak") }
        if summary.week_total > 0 {
            bits.append(summary.week_total.formatted(.currency(code: summary.currency)
                .precision(.fractionLength(0...2))) + " this week")
        }
        return bits.isEmpty ? nil : bits.joined(separator: " · ")
    }

    // MARK: - Chore card

    private func choreCard(_ chore: ChoresTodayChore, summary: ChoresTodaySummary) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: chore.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(accent)
                Text(chore.title)
                    .font(.flHeadline)
                    .foregroundStyle(WarmPalette.ink1)
                Spacer(minLength: 0)
            }
            HStack(spacing: 18) {
                ForEach(chore.slots) { slot in
                    slotButton(chore: chore, slot: slot, summary: summary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .flCard(tint: chore.slots.allSatisfy(\.done) ? accent.opacity(0.06) : .clear)
    }

    /// The whole point: an 88pt target a young hand can't miss.
    private func slotButton(chore: ChoresTodayChore, slot: ChoreSlotState,
                            summary: ChoresTodaySummary) -> some View {
        Button {
            tick(chore: chore, slot: slot, summary: summary)
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(slot.done ? accent : WarmPalette.ink4.opacity(0.14))
                        .frame(width: 88, height: 88)
                    Circle()
                        .strokeBorder(slot.done ? accent : WarmPalette.ink4.opacity(0.35),
                                      lineWidth: slot.done ? 0 : 2)
                        .frame(width: 88, height: 88)
                    Image(systemName: slot.done ? "checkmark" : glyph(chore: chore, slot: slot))
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(slot.done ? .white : WarmPalette.ink3)
                }
                .animation(.spring(duration: 0.35, bounce: 0.5), value: slot.done)
                Text(chore.slots.count > 1 || slot.slot != "anytime" ? slot.label : "Today")
                    .font(.flSubheadline.weight(.semibold))
                    .foregroundStyle(slot.done ? accent : WarmPalette.ink2)
            }
        }
        .buttonStyle(.flCardPress)
        .accessibilityLabel("\(chore.title), \(slot.label)")
        .accessibilityValue(slot.done ? "done" : "not done")
    }

    private func glyph(chore: ChoresTodayChore, slot: ChoreSlotState) -> String {
        chore.slots.count > 1 ? slot.icon : chore.icon
    }

    private func tick(chore: ChoresTodayChore, slot: ChoreSlotState, summary: ChoresTodaySummary) {
        if !slot.done {
            // Checking off: the last open slot gets the big finale burst.
            confettiIntensity = summary.open_slots == 1 ? 110 : 42
            confettiTrigger += 1
        }
        Task {
            await viewModel.toggleChore(routineId: routineId, choreId: chore.id,
                                        slot: slot.slot, api: api)
        }
    }

    // MARK: - All done

    private func allDoneBanner(_ summary: ChoresTodaySummary) -> some View {
        VStack(spacing: 8) {
            Text("🎉")
                .font(.system(size: 44))
            Text("Every chore done today!")
                .font(.flHeadline)
                .foregroundStyle(WarmPalette.ink1)
            if summary.streak_days > 1 {
                Text("That's \(summary.streak_days) days in a row.")
                    .font(.flSubheadline)
                    .foregroundStyle(WarmPalette.ink3)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(DesignTokens.Spacing.cardPadding)
        .flCard(tint: accent.opacity(0.08))
    }
}

#Preview {
    let json = """
    {"routine_id":1,"name":"Jude's chores","subject_name":"Jude","color":null,"today":"2026-08-19",
     "chores":[{"id":"dog","title":"Feed the dog","icon":"pawprint.fill","slots":[{"slot":"morning","done":true,"entry_id":1},{"slot":"evening","done":false,"entry_id":null}]},
               {"id":"bed","title":"Make the bed","icon":"bed.double.fill","slots":[{"slot":"morning","done":false,"entry_id":null}]}],
     "open_slots":2,"total_slots":3,"streak_days":4,"week_total":3,"currency":"USD"}
    """
    let s = try! JSONDecoder().decode(ChoresTodaySummary.self, from: Data(json.utf8))
    let vm = HomeViewModel()
    vm.choresToday = [s]
    return ChoreCheckoffSheet(routineId: 1, viewModel: vm, onOpenProgram: {})
        .environment(APIService())
}
