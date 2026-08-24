import SwiftUI

// Cards for a `chores` routine's detail screen: the week grid you tick, what
// the week has earned, and the age-based guidance with a path to the full
// program. Everything visible is computed server-side (`services/chores.js`)
// so the grid, the streak, and the money always agree.

// MARK: - Week grid

struct ChoreWeekCard: View {
    let summary: ChoreSummary
    let accent: Color
    var onToggle: (String, String, String) -> Void      // chore id, slot, date
    var onManage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("This week")
                        .font(.flHeadline)
                        .foregroundStyle(WarmPalette.ink1)
                    Text(weekLine)
                        .font(.flCaption)
                        .foregroundStyle(WarmPalette.ink3)
                }
                Spacer()
                // The number that only goes up. A resettable streak tells a
                // child one missed day is a catastrophe; the habit research
                // says it isn't, so the chain is never the headline here.
                if summary.lifetime_done > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "hands.clap.fill").font(.system(size: 11, weight: .semibold))
                        Text("helped \(summary.lifetime_done)×")
                    }
                    .font(.flCaption.weight(.semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(accent.opacity(0.12), in: Capsule())
                    .accessibilityLabel("helped \(summary.lifetime_done) times so far")
                }
            }

            if summary.chores.isEmpty {
                Text("No chores yet — add one from the suggestions below, or tap Manage.")
                    .font(.flFootnote)
                    .foregroundStyle(WarmPalette.ink3)
            } else {
                ForEach(summary.chores) { chore in
                    choreRow(chore)
                }
            }

            HStack {
                if let pct = summary.completion_pct {
                    Text("\(summary.done_total) of \(summary.expected_total) so far · \(pct)%")
                        .font(.flCaption)
                        .foregroundStyle(WarmPalette.ink3)
                }
                Spacer()
                Button("Manage", action: onManage)
                    .font(.flCaption.weight(.semibold))
                    .foregroundStyle(accent)
            }
        }
        .padding(16)
        .flCard()
    }

    private var weekLine: String {
        guard let start = DateFormatter.isoDate.date(from: summary.week_start),
              let end = DateFormatter.isoDate.date(from: summary.week_end) else { return "" }
        return "\(DateFormatter.longMonthDay.string(from: start)) – \(DateFormatter.longMonthDay.string(from: end))"
    }

    private func choreRow(_ chore: ChoreState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: chore.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(accent)
                    .frame(width: 22)
                Text(chore.title)
                    .font(.flSubheadline.weight(.semibold))
                    .foregroundStyle(WarmPalette.ink1)
                Spacer()
                Text("\(chore.lifetime_count)×")
                    .font(.flCaption)
                    .foregroundStyle(WarmPalette.ink4)
                    .accessibilityLabel("done \(chore.lifetime_count) times ever")
            }
            HStack(spacing: 6) {
                ForEach(chore.days) { day in
                    dayCell(chore: chore, day: day)
                }
            }
        }
    }

    /// One day: one dot per slot, stacked. Future days are dimmed and inert;
    /// past and present days toggle on tap. A day that doesn't apply (an
    /// every-other-day chore) shows a dash.
    private func dayCell(chore: ChoreState, day: ChoreDay) -> some View {
        VStack(spacing: 5) {
            Text(weekdayLetter(day.date))
                .font(.flCaption2.weight(day.today ? .bold : .medium))
                .foregroundStyle(day.today ? accent : WarmPalette.ink3)
            if !day.applies {
                Text("–")
                    .font(.flCaption)
                    .foregroundStyle(WarmPalette.ink4)
                    .frame(height: 22)
            } else {
                VStack(spacing: 3) {
                    ForEach(day.slots) { slot in
                        let future = !day.past && !day.today
                        Button {
                            onToggle(chore.id, slot.slot, day.date)
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(slot.done ? accent : WarmPalette.ink4.opacity(0.14))
                                    .frame(width: 22, height: 22)
                                if slot.done {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                } else if chore.slots.count > 1 {
                                    Image(systemName: slot.icon)
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(WarmPalette.ink4)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(future)
                        .opacity(future ? 0.45 : 1)
                        .accessibilityLabel("\(chore.title), \(slot.label), \(weekdayLetter(day.date))")
                        .accessibilityValue(slot.done ? "done" : "not done")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(day.today ? accent.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small))
    }

    private func weekdayLetter(_ iso: String) -> String {
        guard let d = DateFormatter.isoDate.date(from: iso) else { return "" }
        let f = DateFormatter(); f.dateFormat = "EEEEE"
        return f.string(from: d)
    }
}

// MARK: - Earnings

struct ChoreEarningsCard: View {
    let summary: ChoreSummary
    let accent: Color
    var onBonus: (String) -> Void                // bonus id, toggles today
    var onPayout: (String?) -> Void              // week_start (nil = this week)

    private var e: ChoreEarnings { summary.earnings }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Allowance")
                        .font(.flHeadline)
                        .foregroundStyle(WarmPalette.ink1)
                    Text(e.paid ? "Paid \(money(e.paid_amount)) this week" : "Payday \(weekdayName(e.payday))")
                        .font(.flCaption)
                        .foregroundStyle(WarmPalette.ink3)
                }
                Spacer()
                Text(money(e.total))
                    .font(.flStat)
                    .foregroundStyle(accent)
            }

            if e.allowance > 0 || !summary.bonuses.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    if e.allowance > 0 {
                        line("Weekly allowance", money(e.allowance), note: "Not tied to chores — see why in the program")
                    }
                    ForEach(summary.bonuses) { bonus in
                        Button { onBonus(bonus.id) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: bonus.earned_this_week ? "star.fill" : "star")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(bonus.earned_this_week ? AccentTheme.saffron.color : WarmPalette.ink4)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(bonus.title)
                                        .font(.flSubheadline)
                                        .foregroundStyle(WarmPalette.ink1)
                                    Text(bonusLine(bonus))
                                        .font(.flCaption)
                                        .foregroundStyle(WarmPalette.ink3)
                                }
                                Spacer()
                                Text("+\(money(bonus.amount))")
                                    .font(.flSubheadline.weight(.semibold))
                                    .foregroundStyle(bonus.earned_this_week ? WarmPalette.ink1 : WarmPalette.ink4)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Marks the bonus earned today")
                    }
                }
            } else {
                Text("No allowance set. That's fine — many families keep chores and money separate.")
                    .font(.flFootnote)
                    .foregroundStyle(WarmPalette.ink3)
            }

            if summary.bonuses.contains(where: { $0.title.localizedCaseInsensitiveContains("bed") }) {
                NavigationLink {
                    SleepTrainingProgramView()
                } label: {
                    Label("For bedtime, the Bedtime Pass has the evidence (ages 3–6) — it's in the sleep program.", systemImage: "moon.stars.fill")
                        .font(.flCaption)
                        .foregroundStyle(WarmPalette.ink3)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
            }

            if !summary.ledger.unpaid_weeks.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Owed from earlier weeks · \(money(summary.ledger.owed))")
                        .font(.flCaption.weight(.semibold))
                        .foregroundStyle(AccentTheme.terracotta.color)
                    ForEach(summary.ledger.unpaid_weeks.suffix(3)) { week in
                        HStack {
                            Text("Week of \(shortDate(week.week_start))")
                                .font(.flFootnote)
                                .foregroundStyle(WarmPalette.ink2)
                            Spacer()
                            Button("Paid \(money(week.amount))") { onPayout(week.week_start) }
                                .font(.flCaption.weight(.semibold))
                                .foregroundStyle(accent)
                        }
                    }
                }
                .padding(10)
                .background(AccentTheme.terracotta.color.opacity(0.07), in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small))
            }

            if !e.paid && e.total > 0 {
                Button { onPayout(nil) } label: {
                    Text("Mark this week paid · \(money(e.total))")
                        .font(.flSubheadline.weight(.semibold))
                }
                .buttonStyle(.flCTA(fill: accent))
            }

            if summary.ledger.lifetime_paid > 0 {
                Text("\(money(summary.ledger.lifetime_paid)) paid out all time")
                    .font(.flCaption)
                    .foregroundStyle(WarmPalette.ink4)
            }
        }
        .padding(16)
        .flCard(tint: accent.opacity(0.04))
    }

    private func line(_ title: String, _ value: String, note: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.flSubheadline).foregroundStyle(WarmPalette.ink1)
                if let note { Text(note).font(.flCaption).foregroundStyle(WarmPalette.ink3) }
            }
            Spacer()
            Text(value).font(.flSubheadline.weight(.semibold)).foregroundStyle(WarmPalette.ink1)
        }
    }

    private func bonusLine(_ bonus: ChoreBonusState) -> String {
        let n = bonus.earned_dates.count
        if n == 0 { return "Tap on a night it went well" }
        return "Earned · \(n) night\(n == 1 ? "" : "s") this week"
    }

    private func money(_ v: Double) -> String {
        v.formatted(.currency(code: e.currency).precision(.fractionLength(v.rounded() == v ? 0 : 2)))
    }

    private func weekdayName(_ day: Int) -> String {
        let names = Calendar.current.weekdaySymbols
        return names.indices.contains(day) ? names[day] : "Sunday"
    }

    private func shortDate(_ iso: String) -> String {
        guard let d = DateFormatter.isoDate.date(from: iso) else { return iso }
        return DateFormatter.longMonthDay.string(from: d)
    }
}

// MARK: - Guidance

struct ChoreGuidanceCard: View {
    let guidance: ChoreGuidance
    let subject: String?
    let accent: Color
    var onAddSuggested: (ChoreSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ageLine)
                        .font(.flCaption.weight(.semibold))
                        .foregroundStyle(accent)
                    Text(guidance.band_title)
                        .font(.flHeadline)
                        .foregroundStyle(WarmPalette.ink1)
                }
                Spacer()
            }

            Text(guidance.chore_count)
                .font(.flCaption)
                .foregroundStyle(WarmPalette.ink3)

            Label(guidance.nudge.text, systemImage: nudgeIcon)
                .font(.flFootnote)
                .foregroundStyle(WarmPalette.ink2)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small))

            if !guidance.suggested.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Good fits for \(guidance.age_label)")
                        .font(.flCaption.weight(.semibold))
                        .foregroundStyle(WarmPalette.ink3)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(guidance.suggested.prefix(6)) { s in
                                Button { onAddSuggested(s) } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: s.icon).font(.system(size: 12, weight: .medium))
                                        Text(s.title)
                                        if s.isSupervised {
                                            Text("with you")
                                                .font(.flCaption2)
                                                .foregroundStyle(WarmPalette.ink3)
                                        }
                                        Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                                    }
                                    .font(.flCaption.weight(.medium))
                                    .foregroundStyle(accent)
                                    .padding(.horizontal, DesignTokens.Spacing.chipPadding)
                                    .padding(.vertical, DesignTokens.Spacing.chipVerticalPadding)
                                    .background(accent.opacity(0.10), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            Text(guidance.allowance_label)
                .font(.flFootnote)
                .foregroundStyle(WarmPalette.ink3)

            NavigationLink {
                ChoreProgramView(highlightBand: guidance.band_key)
            } label: {
                Text("View the full program")
                    .font(.flSubheadline.weight(.semibold))
            }
            .buttonStyle(.flCTA(fill: accent))
        }
        .padding(16)
        .flCard(tint: accent.opacity(0.05))
    }

    private var ageLine: String {
        if let y = guidance.age_years {
            let who = subject.map { $0.split(separator: " ").first.map(String.init) ?? $0 } ?? "They"
            return "\(who) · \(y) years old"
        }
        return guidance.age_label
    }

    private var nudgeIcon: String {
        switch guidance.nudge.kind {
        case "add":   "plus.circle.fill"
        case "soon":  "birthday.cake.fill"
        case "start": "sparkles"
        case "hold":  "hourglass"
        default:      "hand.thumbsup.fill"
        }
    }
}

// MARK: - Manage sheet (chores, allowance, bonuses)

/// Edit the routine's config. Deliberately small: a chore is a title, an icon,
/// and when in the day it happens; allowance is one number; a bonus is a title
/// and an amount. Everything else the engine works out.
struct ManageChoresSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State var config: ChoreConfig
    let accent: Color
    var onSave: (ChoreConfig) async -> Bool

    @State private var newChoreTitle = ""
    @State private var newChoreSlots: Set<String> = ["morning"]
    @State private var newBonusTitle = ""
    @State private var newBonusAmount = ""
    @State private var allowanceText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private static let slotOptions = ["morning", "afternoon", "evening", "anytime"]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.large) {
                    choresSection
                    allowanceSection
                    bonusesSection
                }
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                .padding(.top, 8)
                .padding(.bottom, DesignTokens.Spacing.bottomBuffer)
            }
            .background { AmbientBackground(style: .home) }
            .navigationTitle("Manage chores")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled(isSaving)
                }
            }
            .inlineError(errorMessage) { errorMessage = nil }
            .onAppear {
                allowanceText = config.allowance.weekly_amount > 0 ? String(format: "%.2f", config.allowance.weekly_amount) : ""
            }
        }
    }

    private var choresSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("Chores")
            ForEach(config.chores) { chore in
                HStack(spacing: 10) {
                    Image(systemName: chore.icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(accent)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(chore.title).font(.flSubheadline.weight(.semibold)).foregroundStyle(WarmPalette.ink1)
                        Text(chore.slots.map(\.capitalized).joined(separator: " · "))
                            .font(.flCaption).foregroundStyle(WarmPalette.ink3)
                    }
                    Spacer()
                    Button {
                        config.chores.removeAll { $0.id == chore.id }
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(WarmPalette.ink4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(chore.title)")
                }
                .padding(12)
                .flCard()
            }

            VStack(alignment: .leading, spacing: 10) {
                TextField("New chore, e.g. Feed the dog", text: $newChoreTitle)
                    .font(.flBody)
                    .textInputAutocapitalization(.sentences)
                HStack(spacing: 6) {
                    ForEach(Self.slotOptions, id: \.self) { slot in
                        let on = newChoreSlots.contains(slot)
                        Button {
                            if slot == "anytime" { newChoreSlots = ["anytime"] }
                            else {
                                newChoreSlots.remove("anytime")
                                if on { newChoreSlots.remove(slot) } else { newChoreSlots.insert(slot) }
                                if newChoreSlots.isEmpty { newChoreSlots = ["anytime"] }
                            }
                        } label: {
                            Text(slot.capitalized)
                                .font(.flCaption.weight(.medium))
                                .foregroundStyle(on ? .white : accent)
                                .padding(.horizontal, DesignTokens.Spacing.chipPadding)
                                .padding(.vertical, DesignTokens.Spacing.chipVerticalPadding)
                                .background(on ? accent : accent.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button {
                    addChore()
                } label: {
                    Label("Add chore", systemImage: "plus")
                        .font(.flSubheadline.weight(.semibold))
                }
                .buttonStyle(.flCTA(fill: accent))
                .disabled(newChoreTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)
            .flCard(tint: accent.opacity(0.04))
        }
    }

    private var allowanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("Weekly allowance")
            HStack {
                Text(Locale.current.currencySymbol ?? "$")
                    .font(.flBody)
                    .foregroundStyle(WarmPalette.ink3)
                TextField("0", text: $allowanceText)
                    .font(.flBody)
                    .keyboardType(.decimalPad)
                Spacer()
                Picker("Payday", selection: Binding(
                    get: { config.allowance.payday ?? 0 },
                    set: { config.allowance.payday = $0 })) {
                    ForEach(0..<7, id: \.self) { d in
                        Text(Calendar.current.shortWeekdaySymbols[d]).tag(d)
                    }
                }
                .tint(accent)
            }
            .padding(12)
            .flCard()
            Text("A fixed amount, never docked for a missed chore — the research is clear that pay-per-chore backfires with young kids. Leave it empty to keep chores and money separate.")
                .font(.flFootnote)
                .foregroundStyle(WarmPalette.ink3)
        }
    }

    private var bonusesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("Behaviour bonuses")
            ForEach(config.bonuses) { bonus in
                HStack(spacing: 10) {
                    Image(systemName: "star.fill").font(.system(size: 13)).foregroundStyle(AccentTheme.saffron.color).frame(width: 22)
                    Text(bonus.title).font(.flSubheadline.weight(.semibold)).foregroundStyle(WarmPalette.ink1)
                    Spacer()
                    Text(bonus.amount.formatted(.currency(code: config.allowance.currency ?? "USD")))
                        .font(.flSubheadline).foregroundStyle(WarmPalette.ink2)
                    Button {
                        config.bonuses.removeAll { $0.id == bonus.id }
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(WarmPalette.ink4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(bonus.title)")
                }
                .padding(12)
                .flCard()
            }
            HStack(spacing: 10) {
                TextField("e.g. Good bedtime", text: $newBonusTitle).font(.flBody)
                TextField("1.00", text: $newBonusAmount).font(.flBody).keyboardType(.decimalPad).frame(width: 70)
                Button {
                    addBonus()
                } label: {
                    Image(systemName: "plus.circle.fill").font(.system(size: 22)).foregroundStyle(accent)
                }
                .buttonStyle(.plain)
                .disabled(newBonusTitle.trimmingCharacters(in: .whitespaces).isEmpty || Double(newBonusAmount) == nil)
                .accessibilityLabel("Add bonus")
            }
            .padding(12)
            .flCard(tint: accent.opacity(0.04))
            Text("A weekly bonus for something you're working on — bedtime, teeth, a calm morning. Mark the nights it went well; the bonus pays once for the week.")
                .font(.flFootnote)
                .foregroundStyle(WarmPalette.ink3)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.flCaption.weight(.semibold)).foregroundStyle(WarmPalette.ink3)
    }

    private func addChore() {
        let title = newChoreTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let slots = Self.slotOptions.filter { newChoreSlots.contains($0) }
        config.chores.append(.init(id: Self.slug(title), title: title, icon: Self.icon(for: title),
                                   slots: slots, days: nil, active: true, started_on: DateFormatter.isoDate.string(from: Date())))
        newChoreTitle = ""
        newChoreSlots = ["morning"]
    }

    private func addBonus() {
        let title = newBonusTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, let amount = Double(newBonusAmount) else { return }
        config.bonuses.append(.init(id: Self.slug(title), title: title, amount: amount, icon: "star.fill"))
        newBonusTitle = ""; newBonusAmount = ""
    }

    private func save() async {
        isSaving = true
        config.allowance.weekly_amount = Double(allowanceText.replacingOccurrences(of: ",", with: ".")) ?? 0
        if config.allowance.currency == nil { config.allowance.currency = Locale.current.currency?.identifier ?? "USD" }
        if await onSave(config) { dismiss() } else {
            errorMessage = "Couldn't save those changes. Please try again."
            isSaving = false
        }
    }

    /// Stable id from a title plus a short random tail so two "Feed the dog"
    /// chores added over the years don't collide in the history.
    static func slug(_ title: String) -> String {
        let base = title.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "\(base.prefix(24))-\(String(UUID().uuidString.prefix(4)).lowercased())"
    }

    /// A reasonable glyph from the words in the title — good enough that most
    /// chores get a fitting icon without a picker.
    static func icon(for title: String) -> String {
        let t = title.lowercased()
        if t.contains("dog") || t.contains("cat") || t.contains("pet") || t.contains("fish") { return "pawprint.fill" }
        if t.contains("bed") { return "bed.double.fill" }
        if t.contains("table") || t.contains("plate") || t.contains("dinner") || t.contains("meal") || t.contains("cook") { return "fork.knife" }
        if t.contains("toy") || t.contains("tidy") || t.contains("clean up") { return "shippingbox.fill" }
        if t.contains("laundry") || t.contains("clothes") || t.contains("sock") { return "tshirt.fill" }
        if t.contains("plant") || t.contains("garden") || t.contains("lawn") { return "leaf.fill" }
        if t.contains("dish") { return "dishwasher.fill" }
        if t.contains("trash") || t.contains("bin") || t.contains("garbage") || t.contains("recycl") { return "trash.fill" }
        if t.contains("teeth") || t.contains("brush") { return "mouth.fill" }
        if t.contains("bag") || t.contains("school") { return "backpack.fill" }
        if t.contains("sweep") || t.contains("vacuum") || t.contains("floor") { return "wind" }
        if t.contains("wipe") || t.contains("clean") { return "sparkles" }
        return "checkmark.circle.fill"
    }
}

// MARK: - Previews

#Preview("Week + earnings + guidance") {
    let json = """
    {"today":"2026-08-19","week_start":"2026-08-17","week_end":"2026-08-23","week_start_day":1,
     "chores":[{"id":"dog","title":"Feed the dog","icon":"pawprint.fill","slots":["morning","evening"],
       "days":[{"date":"2026-08-17","applies":true,"past":true,"today":false,"slots":[{"slot":"morning","done":true,"entry_id":1},{"slot":"evening","done":true,"entry_id":2}]},
               {"date":"2026-08-18","applies":true,"past":true,"today":false,"slots":[{"slot":"morning","done":true,"entry_id":3},{"slot":"evening","done":true,"entry_id":4}]},
               {"date":"2026-08-19","applies":true,"past":false,"today":true,"slots":[{"slot":"morning","done":true,"entry_id":5},{"slot":"evening","done":false,"entry_id":null}]},
               {"date":"2026-08-20","applies":true,"past":false,"today":false,"slots":[{"slot":"morning","done":false,"entry_id":null},{"slot":"evening","done":false,"entry_id":null}]},
               {"date":"2026-08-21","applies":true,"past":false,"today":false,"slots":[{"slot":"morning","done":false,"entry_id":null},{"slot":"evening","done":false,"entry_id":null}]},
               {"date":"2026-08-22","applies":true,"past":false,"today":false,"slots":[{"slot":"morning","done":false,"entry_id":null},{"slot":"evening","done":false,"entry_id":null}]},
               {"date":"2026-08-23","applies":true,"past":false,"today":false,"slots":[{"slot":"morning","done":false,"entry_id":null},{"slot":"evening","done":false,"entry_id":null}]}],
       "done_count":5,"expected_count":6,"lifetime_count":41}],
     "completion_pct":83,"done_total":5,"expected_total":6,"streak_days":2,"lifetime_done":41,
     "bonuses":[{"id":"bed","title":"Good bedtime","amount":1,"icon":"star.fill","earned_dates":[{"date":"2026-08-18","entry_id":9}],"earned_this_week":true}],
     "earnings":{"currency":"USD","allowance":2,"bonus":1,"total":3,"payday":0,"paid":false,"paid_amount":0,"payout_entry_id":null},
     "ledger":{"unpaid_weeks":[{"week_start":"2026-08-10","week_end":"2026-08-16","amount":3}],"owed":3,"lifetime_paid":12},
     "guidance":{"age_years":3,"band_key":"toddler","band_title":"Little helper","age_label":"2–3 years","chore_count":"1–2 chores, done together",
       "allowance_label":"Optional. $1–3/week is typical if you start now.","next_band":null,
       "suggested":[{"title":"Put toys in the bin","icon":"shippingbox.fill","slots":["evening"],"note":null},{"title":"Water a plant","icon":"leaf.fill","slots":["morning"],"note":null}],
       "nudge":{"kind":"hold","text":"Keep going with what's there — two steady weeks before adding the next one."}}}
    """
    let summary = try! JSONDecoder().decode(ChoreSummary.self, from: Data(json.utf8))
    return NavigationStack {
        ScrollView {
            VStack(spacing: 16) {
                ChoreWeekCard(summary: summary, accent: TabAccent.routines.color, onToggle: { _, _, _ in }, onManage: {})
                ChoreEarningsCard(summary: summary, accent: TabAccent.routines.color, onBonus: { _ in }, onPayout: { _ in })
                ChoreGuidanceCard(guidance: summary.guidance!, subject: "Jude", accent: TabAccent.routines.color, onAddSuggested: { _ in })
            }
            .padding()
        }
        .background { AmbientBackground(style: .home) }
    }
    .environment(APIService())
}

#Preview("Manage") {
    ManageChoresSheet(
        config: ChoreConfig(
            chores: [.init(id: "dog", title: "Feed the dog", icon: "pawprint.fill", slots: ["morning", "evening"], days: nil, active: true, started_on: nil)],
            allowance: .init(weekly_amount: 2, currency: "USD", payday: 0),
            bonuses: [.init(id: "bed", title: "Good bedtime", amount: 1, icon: "star.fill")],
            week_start: 1),
        accent: TabAccent.routines.color,
        onSave: { _ in true })
}
