import SwiftUI

/// A single routine: its recent entries, a type-appropriate quick-log, and —
/// for the guided sleep-training program — the current age phase with a link to
/// the full program.
struct RoutineDetailView: View {
    @Environment(APIService.self) private var api
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    let routineId: Int

    @State private var detail: RoutineDetailResponse?
    @State private var occurrences: RoutineOccurrences?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingDeleteConfirm = false
    @State private var isSharing = false
    @State private var sleepToLog: SleepKind?
    @State private var sleepStats: SleepStats?
    @State private var isTogglingLiveSleep = false
    /// The running sleep whose start time is being corrected.
    @State private var editingSleepStart: SleepStartEdit?
    /// A finished sleep being corrected — most often an end time stamped when
    /// you got round to tapping Awake rather than when they actually woke.
    @State private var editingSleep: LoggedSleep?
    /// The chores week, replaced wholesale by every toggle's response.
    @State private var choreSummary: ChoreSummary?
    @State private var showingManageChores = false

    private let accent = TabAccent.routines.color

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                if isLoading {
                    FLLoadingState(message: "Loading…").padding(.top, 60)
                } else if let detail {
                    FLScreenHeader(
                        eyebrow: detail.type.displayName,
                        title: detail.name,
                        subtitle: detail.subject_name,
                        accent: accent
                    )

                    VStack(spacing: 16) {
                        shareCard(detail)

                        if let guidance = detail.guidance {
                            SleepGuidanceCard(guidance: guidance)
                        }
                        if let cycle = detail.cycle {
                            CycleCard(cycle: cycle)
                        }
                        if let achievements = detail.achievements {
                            ActivityAchievementCard(achievements: achievements)
                        }
                        if detail.type.isActivity, let occ = occurrences, !(occ.pending ?? []).isEmpty {
                            ConfirmAttendanceCard(pending: occ.pending ?? [], activity: detail.name) { date, attended in
                                Task { await confirm(date: date, attended: attended) }
                            }
                        }

                        if detail.type == .babySleep || detail.type == .sleepTraining {
                            liveSleepCard(detail)
                            nextSleepCard(detail)
                            bedtimeCard(detail)
                        }

                        if detail.type.isChores, let summary = choreSummary {
                            ChoreWeekCard(summary: summary, accent: accent,
                                          onToggle: { choreId, slot, date in Task { await toggleChore(choreId, slot: slot, date: date) } },
                                          onManage: { showingManageChores = true })
                            ChoreEarningsCard(summary: summary, accent: accent,
                                              onBonus: { bonusId in Task { await toggleBonus(bonusId) } },
                                              onPayout: { weekStart in Task { await recordPayout(weekStart) } })
                            if let guidance = summary.guidance {
                                ChoreGuidanceCard(guidance: guidance, subject: detail.subject_name, accent: accent) { suggestion in
                                    Task { await addSuggestedChore(suggestion, detail: detail) }
                                }
                            }
                        }

                        if !detail.type.isChores {
                            quickLog(for: detail.type)
                        }

                        if let stats = sleepStats {
                            SleepStatsCard(stats: stats, accent: accent)
                            // The pattern and the levers only appear once the
                            // log has earned them — both cards render nothing
                            // when there is no repeating waking to explain.
                            if let wakings = stats.wakings {
                                SleepPatternCard(analysis: wakings, accent: accent)
                            }
                            if let recommendations = stats.recommendations {
                                SleepRecommendationsCard(
                                    recommendations: recommendations,
                                    accent: accent,
                                    conciergePrompt: conciergePrompt(for: detail, stats: stats))
                            }
                        }

                        entriesSection(detail.entries)
                    }
                    .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                    .padding(.top, 4)
                }
            }
            .padding(.bottom, DesignTokens.Spacing.bottomBuffer)
        }
        .background { AmbientBackground(style: .home) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .toolbar {
            // Deleting is the creator's alone — a shared routine can be logged to
            // by anyone at home, but only its author can take it away.
            if detail == nil || detail?.created_by == nil || detail?.created_by == auth.currentUser?.id {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) { showingDeleteConfirm = true } label: {
                            Label("Delete routine", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(accent)
                    }
                }
            }
        }
        .confirmationDialog("Delete this routine and all its entries?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await deleteRoutine() } }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $editingSleepStart) { edit in
            EditSleepStartSheet(current: edit.current, accent: accent) { time in
                await applySleepStart(time)
            }
        }
        .sheet(item: $editingSleep) { logged in
            LogSleepSheet(kind: logged.kind, accent: accent, editing: logged) { payload in
                await applySleepEdit(entryId: logged.id, payload: payload)
            }
        }
        .sheet(isPresented: $showingManageChores) {
            if let detail {
                ManageChoresSheet(config: ChoreConfig.decode(detail.config), accent: accent) { cfg in
                    await saveChoreConfig(cfg)
                }
            }
        }
        .sheet(item: $sleepToLog) { kind in
            LogSleepSheet(kind: kind, accent: accent) { payload in
                await log(entryType: kind.entryType, value: payload.value,
                          date: payload.date, time: payload.time, notes: payload.notes)
            }
        }
        .inlineError(errorMessage) { errorMessage = nil }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Sharing

    /// The creator gets a toggle; everyone else just gets told it's shared (they
    /// can only be looking at it because it is). Sharing is per-routine, so a
    /// cycle tracker can stay private while the baby's sleep log is shared.
    @ViewBuilder
    private func shareCard(_ detail: RoutineDetailResponse) -> some View {
        let isShared = detail.isSharedWithHousehold
        let isOwner = detail.created_by == nil || detail.created_by == auth.currentUser?.id
        HStack(spacing: 12) {
            Image(systemName: isShared ? "person.2.fill" : "lock.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isShared ? accent : WarmPalette.ink3)
                .frame(width: 30, height: 30)
                .background(isShared ? accent.opacity(0.15) : WarmPalette.ink4.opacity(0.12))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(isShared ? "Shared with your household" : "Just for you")
                    .font(.flSubheadline.weight(.semibold))
                    .foregroundStyle(WarmPalette.ink1)
                Text(isShared
                     ? "Everyone at home can see this and log to it."
                     : "Only you can see this.")
                    .font(.flFootnote)
                    .foregroundStyle(WarmPalette.ink3)
            }
            Spacer()
            if isOwner {
                Toggle("", isOn: Binding(
                    get: { isShared },
                    set: { newValue in Task { await setShared(newValue) } }
                ))
                .labelsHidden()
                .tint(accent)
                .disabled(isSharing)
            }
        }
        .padding(12)
        .flCard(tint: isShared ? accent.opacity(0.06) : .clear)
    }

    private func setShared(_ shared: Bool) async {
        isSharing = true
        defer { isSharing = false }
        do {
            try await api.setRoutineShared(id: routineId, shared: shared)
            await load()
        } catch {
            errorMessage = shared
                ? "Couldn't share this routine. Please try again."
                : "Couldn't make this routine private. Please try again."
        }
    }

    /// Keep the "start winding down" nudge in step with reality: scheduled from
    /// the last wake, and dropped while a sleep is actually running — they're
    /// already down, so a reminder to put them down is noise.
    private func syncNapPrepNotification(_ detail: RoutineDetailResponse) async {
        guard await NotificationService.shared.isAuthorized() else { return }

        if openSleep(detail) == nil, let next = detail.next_sleep, let at = next.prepareDate {
            NotificationService.shared.scheduleNapPrep(
                routineId: routineId,
                childName: detail.subject_name,
                at: at,
                windowLabel: next.wake_window_label
            )
        } else {
            NotificationService.shared.cancelNapPrep(routineId: routineId)
        }

        // Bedtime is a standing nightly reminder rather than an event-driven
        // one — but if they're already down tonight, tonight's occurrence is
        // noise ("start winding down" hours into a logged sleep), so it skips
        // to tomorrow while a sleep is running.
        if let prep = detail.bedtime_prep, let at = prep.startComponents {
            NotificationService.shared.scheduleBedtimePrep(
                routineId: routineId,
                childName: detail.subject_name,
                hour: at.hour, minute: at.minute,
                leadMinutes: prep.lead_minutes ?? 30,
                skipToday: openSleep(detail) != nil
            )
        } else {
            NotificationService.shared.cancelBedtimePrep(routineId: routineId)
        }
    }

    // MARK: - Next sleep

    /// Shown only when there's something real to say — a birthdate to reason
    /// from and a finished sleep to measure from — and never while one is
    /// running.
    @ViewBuilder
    private func nextSleepCard(_ detail: RoutineDetailResponse) -> some View {
        // Hidden once the evening routine has started: a prediction from this
        // morning shown at 8pm reads as "a nap is coming at 11am". Until then,
        // an overdue window still belongs on this card — not swapped for bedtime.
        let pastBedtimePrep = detail.bedtime_prep?.hasStarted() == true
        if openSleep(detail) == nil, let next = detail.next_sleep,
           !(next.isStale && pastBedtimePrep),
           let dueFrom = next.dueFromDate, let prepare = next.prepareDate {
            let dueNow = dueFrom <= Date()
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent)
                    Text("Next sleep")
                        .font(.flHeadline)
                        .foregroundStyle(WarmPalette.ink1)
                    Spacer()
                    // The countdown must run to the sleep time named below it —
                    // counting to the wind-down nudge instead read as the two
                    // disagreeing by the lead time.
                    if dueFrom > Date() {
                        Text("in \(relativeMinutes(to: dueFrom))")
                            .font(.flFootnote)
                            .foregroundStyle(WarmPalette.ink3)
                    }
                }
                Text(dueNow
                     ? "Due now — the window opened at \(DateFormatter.shortTime.string(from: dueFrom))"
                     : "Likely due around \(DateFormatter.shortTime.string(from: dueFrom))")
                    .font(.flSubheadline)
                    .foregroundStyle(dueNow ? WarmPalette.ink1 : WarmPalette.ink2)
                if let label = next.wake_window_label {
                    // Name the wind-down time outright, so the nudge and the
                    // sleep time are two clearly different clock times.
                    Text("Awake \(label) is typical at this age. \(windDownLine(prepare: prepare, leadMinutes: next.lead_minutes ?? 15))")
                        .font(.flFootnote)
                        .foregroundStyle(WarmPalette.ink3)
                }
                if let basis = next.basis {
                    Text(basis)
                        .font(.flCaption2)
                        .foregroundStyle(WarmPalette.ink4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .flCard(tint: accent.opacity(0.06))
        }
    }

    /// The standing bedtime reminder, shown whether or not a nap is due.
    @ViewBuilder
    private func bedtimeCard(_ detail: RoutineDetailResponse) -> some View {
        if let prep = detail.bedtime_prep, let startTime = prep.start_time {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Image(systemName: "moon.stars")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent)
                    Text("Bedtime routine")
                        .font(.flHeadline)
                        .foregroundStyle(WarmPalette.ink1)
                    Spacer()
                    if let nights = prep.based_on_nights {
                        Text("\(nights) night\(nights == 1 ? "" : "s")")
                            .font(.flFootnote)
                            .foregroundStyle(WarmPalette.ink3)
                    }
                }
                Text("Start around \(displayTime(startTime))\(prep.bedtime.map { " for a \($0) bedtime" } ?? "")")
                    .font(.flSubheadline)
                    .foregroundStyle(WarmPalette.ink2)
                if let basis = prep.basis {
                    Text(basis)
                        .font(.flCaption2)
                        .foregroundStyle(WarmPalette.ink4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .flCard()
        }
    }

    /// The wind-down half of the next-sleep card: the nudge is a separate,
    /// earlier moment than the sleep itself, so it gets its own clock time
    /// rather than a relative "15 minutes before".
    private func windDownLine(prepare: Date, leadMinutes: Int) -> String {
        prepare > Date()
            ? "We'll nudge you at \(DateFormatter.shortTime.string(from: prepare)) — \(leadMinutes) min before — to start winding down."
            : "Good time to start winding down."
    }

    /// Seeds the concierge with the question this data raises, named subject and
    /// all, so the chat opens on the specific night pattern rather than a blank
    /// "how is he sleeping".
    private func conciergePrompt(for detail: RoutineDetailResponse, stats: SleepStats) -> String {
        let who = detail.subject_name ?? detail.name
        if let time = stats.wakings?.cluster?.typical_time {
            let rhythm = stats.wakings?.rhythm
            let when = (rhythm?.confidence != "low" ? rhythm?.label : nil) ?? "on several nights"
            return "\(who) is waking around \(time) \(when). Look at the sleep log and tell me why, and what we could try differently to get him through the night."
        }
        return "Look at \(who)'s sleep log and tell me what the data says, and what we could try differently."
    }

    private func relativeMinutes(to date: Date) -> String {
        let mins = max(0, Int(date.timeIntervalSinceNow / 60))
        return SleepValue.durationText(minutes: mins)
    }

    // MARK: - Live sleep

    /// The in-progress sleep, if one is running: an entry that has a start but
    /// no end yet. One tap starts it, one tap ends it — for the 2am case where
    /// nobody is going to fill in a form.
    private func openSleep(_ detail: RoutineDetailResponse) -> RoutineEntryResponse? {
        detail.entries.first { entry in
            guard entry.entry_type == "nap" || entry.entry_type == "night_sleep",
                  let raw = entry.value?.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any]
            else { return false }
            return obj["in_progress"] as? Bool == true
        }
    }

    @ViewBuilder
    private func liveSleepCard(_ detail: RoutineDetailResponse) -> some View {
        if let open = openSleep(detail) {
            let started = open.entry_time ?? ""
            HStack(spacing: 12) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(accent)
                    .frame(width: 34, height: 34)
                    .background(accent.opacity(0.15))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(open.entry_type == "nap" ? "Napping now" : "Asleep for the night")
                        .font(.flSubheadline.weight(.semibold))
                        .foregroundStyle(WarmPalette.ink1)
                    // Tappable: the stamped time is only right if you tapped the
                    // button at the moment it happened, which is rarely the case.
                    Button {
                        editingSleepStart = SleepStartEdit(current: started)
                    } label: {
                        HStack(spacing: 4) {
                            Text(started.isEmpty ? "In progress" : "Since \(displayTime(started))")
                            Image(systemName: "pencil")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .font(.flFootnote)
                        .foregroundStyle(accent)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button("Awake") { Task { await endLiveSleep() } }
                    .buttonStyle(.flCTA)
                    .disabled(isTogglingLiveSleep)
            }
            .padding(12)
            .flCard(tint: accent.opacity(0.08))
        } else {
            // The label sits on its own line above the buttons: side-by-side,
            // "Down for the night" wrapped to two lines and the pair looked
            // cramped against the label.
            VStack(alignment: .leading, spacing: 10) {
                Text("Happening now")
                    .font(.flCaption.weight(.semibold))
                    .foregroundStyle(WarmPalette.ink3)
                HStack(spacing: 8) {
                    Button { Task { await startLiveSleep(kind: "nap") } } label: {
                        chip("Nap started", "sun.max", expands: true)
                    }
                    .buttonStyle(.plain)
                    .disabled(isTogglingLiveSleep)
                    Button { Task { await startLiveSleep(kind: "night_sleep") } } label: {
                        chip("Down for the night", "moon", expands: true)
                    }
                    .buttonStyle(.plain)
                    .disabled(isTogglingLiveSleep)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .flCard()
        }
    }

    private func startLiveSleep(kind: String) async {
        isTogglingLiveSleep = true
        defer { isTogglingLiveSleep = false }
        do {
            try await api.startSleep(routineId: routineId, kind: kind)
            await load()
        } catch {
            errorMessage = "Couldn't start that sleep. Please try again."
        }
    }

    /// "19:30" -> "7:30pm" for display; falls back to the raw value.
    private func displayTime(_ hhmm: String) -> String {
        guard let d = DateFormatter.hourMinute.date(from: hhmm) else { return hhmm }
        return DateFormatter.shortTime.string(from: d)
    }

    private func applySleepEdit(entryId: Int, payload: SleepPayload) async {
        do {
            try await api.updateRoutineEntry(routineId: routineId, entryId: entryId, data: [
                // Send the times and let the server recompute the span, so the
                // stored duration can never disagree with what was picked.
                "start_time": payload.time,
                "end_time": payload.endTime,
                "wake_count": payload.wakeCount as Any,
                "notes": payload.notes,
                // The full editor's start picker includes a date, so honour it —
                // logging a sleep on the wrong day is a thing to be able to fix.
                // (The quick start-time correction stays time-only by design.)
                "entry_date": payload.date,
            ])
            await load()
        } catch {
            errorMessage = "Couldn't save that change. Please try again."
        }
    }

    private func applySleepStart(_ time: String) async {
        do {
            try await api.setSleepStart(routineId: routineId, time: time)
            await load()
        } catch {
            errorMessage = "Couldn't change the start time. Please try again."
        }
    }

    private func endLiveSleep() async {
        isTogglingLiveSleep = true
        defer { isTogglingLiveSleep = false }
        do {
            try await api.endSleep(routineId: routineId, wakeCount: nil)
            await load()
        } catch {
            errorMessage = "Couldn't end that sleep. Please try again."
        }
    }

    // MARK: - Quick log

    @ViewBuilder
    private func quickLog(for type: RoutineType) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick log")
                .font(.flCaption.weight(.semibold))
                .foregroundStyle(WarmPalette.ink3)
            FlowButtons {
                switch type {
                case .period:
                    logButton("Period started", "drop.fill", entryType: "period_start")
                    logButton("Period ended", "drop", entryType: "period_end")
                    logButton("Symptom", "waveform.path.ecg", entryType: "symptom")
                case .babySleep, .sleepTraining:
                    // Sleep is a span, not a moment — these open a sheet for the
                    // start and end times rather than stamping "now".
                    sheetButton("Nap", "sun.max.fill", kind: .nap)
                    sheetButton("Night sleep", "moon.fill", kind: .night)
                    logButton("Woke up", "sunrise.fill", entryType: "wake")
                    logButton("Milestone", "star.fill", entryType: "milestone")
                case .activity:
                    logButton("Did it today", "checkmark.circle.fill", entryType: "session")
                    logButton("Skipped", "xmark.circle", entryType: "session", value: ["status": "skipped"])
                case .custom:
                    logButton("Done today", "checkmark", entryType: "note")
                case .chores:
                    // Chores tick in the week grid; there's nothing to stamp here.
                    EmptyView()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .flCard()
    }

    private func logButton(_ title: String, _ icon: String, entryType: String, value: [String: Any]? = nil) -> some View {
        Button {
            Task { await log(entryType: entryType, value: value) }
        } label: {
            chip(title, icon)
        }
        .buttonStyle(.plain)
    }

    private func sheetButton(_ title: String, _ icon: String, kind: SleepKind) -> some View {
        Button { sleepToLog = kind } label: { chip(title, icon) }
            .buttonStyle(.plain)
    }

    /// `expands` widens the pill itself rather than centring a content-sized
    /// pill in a wide frame — the frame has to be applied BEFORE the background
    /// or the capsule stays small and the row looks broken.
    private func chip(_ title: String, _ icon: String, expands: Bool = false) -> some View {
        Label(title, systemImage: icon)
            .font(.flFootnote.weight(.semibold))
            .foregroundStyle(accent)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: expands ? .infinity : nil)
            .background(accent.opacity(0.12), in: Capsule())
    }

    // MARK: - Entries

    @ViewBuilder
    private func entriesSection(_ entries: [RoutineEntryResponse]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("History")
                .font(.flCaption.weight(.semibold))
                .foregroundStyle(WarmPalette.ink3)
            if entries.isEmpty {
                Text("No entries yet — use quick log above to start.")
                    .font(.flFootnote)
                    .foregroundStyle(WarmPalette.ink3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .flCard()
            } else {
                ForEach(entries) { entry in
                    EntryRow(
                        entry: entry,
                        // Only completed sleeps are editable: a running one is
                        // corrected from the card above, and older entries have
                        // no span to correct.
                        onEdit: LoggedSleep(entry: entry).map { logged in
                            { editingSleep = logged }
                        },
                        onDelete: { Task { await deleteEntry(entry.id) } }
                    )
                }
            }
        }
    }

    // MARK: - Data

    private func load() async {
        do {
            let d = try await api.fetchRoutine(id: routineId)
            detail = d
            choreSummary = d.chores
            errorMessage = nil
            if d.type == .babySleep || d.type == .sleepTraining {
                sleepStats = try? await api.fetchSleepStats(routineId: routineId)
                await syncNapPrepNotification(d)
            }
            if d.type.isActivity {
                let occ = try? await api.fetchRoutineOccurrences(id: routineId)
                occurrences = occ
                // Schedule a "did you go?" nudge for each upcoming linked event.
                if let occ, await NotificationService.shared.isAuthorized() {
                    let label = occ.keyword?.capitalized ?? d.name
                    for o in occ.occurrences where !o.confirmed && !o.past {
                        NotificationService.shared.scheduleActivityConfirmation(routineId: routineId, activity: label, date: o.date)
                    }
                }
            }
        } catch {
            errorMessage = "Couldn't load this routine."
        }
        isLoading = false
    }

    // MARK: - Chores

    private func toggleChore(_ choreId: String, slot: String, date: String) async {
        do {
            choreSummary = try await api.toggleChore(routineId: routineId, choreId: choreId, slot: slot, date: date)
        } catch {
            errorMessage = "Couldn't update that chore."
        }
    }

    private func toggleBonus(_ bonusId: String) async {
        do {
            choreSummary = try await api.setChoreBonus(routineId: routineId, bonusId: bonusId)
        } catch {
            errorMessage = "Couldn't update that bonus."
        }
    }

    private func recordPayout(_ weekStart: String?) async {
        do {
            choreSummary = try await api.recordChorePayout(routineId: routineId, weekStart: weekStart)
        } catch {
            errorMessage = "Couldn't record that payment."
        }
    }

    /// Config edits go through the plain routine update; the server's next
    /// detail fetch recomputes the week against the new chore list.
    private func saveChoreConfig(_ cfg: ChoreConfig) async -> Bool {
        do {
            try await api.updateRoutine(id: routineId, data: ["config": cfg.jsonObject])
            await load()
            return true
        } catch {
            return false
        }
    }

    private func addSuggestedChore(_ s: ChoreSuggestion, detail: RoutineDetailResponse) async {
        var cfg = ChoreConfig.decode(detail.config)
        guard !cfg.chores.contains(where: { $0.title.caseInsensitiveCompare(s.title) == .orderedSame }) else { return }
        cfg.chores.append(.init(id: ManageChoresSheet.slug(s.title), title: s.title, icon: s.icon, slots: s.slots,
                                days: nil, active: true, started_on: DateFormatter.isoDate.string(from: Date())))
        if await saveChoreConfig(cfg) == false { errorMessage = "Couldn't add that chore." }
    }

    // Confirm (or mark skipped) attendance for a specific linked calendar date.
    private func confirm(date: String, attended: Bool) async {
        // The user has answered directly, so retire the pending "did you go?" nudge.
        NotificationService.shared.cancelActivityConfirmation(routineId: routineId, date: date)
        await log(entryType: "session", value: attended ? nil : ["status": "skipped"], date: date)
    }

    private func log(entryType: String, value: [String: Any]? = nil, date: String? = nil,
                     time: String? = nil, notes: String? = nil) async {
        var data: [String: Any] = ["entry_type": entryType]
        if let value { data["value"] = value }
        if let date { data["entry_date"] = date }
        if let time { data["entry_time"] = time }
        if let notes, !notes.isEmpty { data["notes"] = notes }
        do {
            try await api.addRoutineEntry(id: routineId, data: data)
            await load()
        } catch {
            errorMessage = "Couldn't save that entry. Please try again."
        }
    }

    private func deleteEntry(_ id: Int) async {
        do {
            try await api.deleteRoutineEntry(routineId: routineId, entryId: id)
            await load()
        } catch {
            errorMessage = "Couldn't delete that entry."
        }
    }

    private func deleteRoutine() async {
        do {
            try await api.deleteRoutine(id: routineId)
            // The bedtime nudge REPEATS nightly, so leaving it behind would keep
            // reminding you about a routine that no longer exists — forever.
            NotificationService.shared.cancelNapPrep(routineId: routineId)
            NotificationService.shared.cancelBedtimePrep(routineId: routineId)
            dismiss()
        } catch {
            errorMessage = "Couldn't delete this routine."
        }
    }
}

// MARK: - Sleep logging

/// The two sleep spans you log after the fact. `Identifiable` so it can drive
/// `.sheet(item:)` — which also guarantees the sheet is rebuilt (and its
/// defaults recomputed) each time it opens.
enum SleepKind: String, Identifiable {
    case nap, night

    var id: String { rawValue }
    var entryType: String { self == .nap ? "nap" : "night_sleep" }
    var title: String { self == .nap ? "Log a nap" : "Log night sleep" }
    var icon: String { self == .nap ? "sun.max.fill" : "moon.fill" }
}

/// What a sleep entry carries: the span itself, precomputed minutes so nothing
/// downstream has to re-derive it, and (for nights) how many times they woke.
struct SleepPayload {
    let value: [String: Any]
    let date: String
    let time: String
    /// The end of the span, for the edit path — the server recomputes the
    /// duration from the two times so the stored value can't drift from them.
    let endTime: String
    let wakeCount: Int?
    let notes: String
}

/// An already-logged sleep, unpacked from its stored value so the sheet can open
/// on the real numbers. Identifiable by entry id so `.sheet(item:)` can drive it.
struct LoggedSleep: Identifiable {
    let id: Int
    let kind: SleepKind
    let start: Date
    let end: Date
    let wakeCount: Int
    let notes: String

    /// Rebuilds from a history row, or nil if the row predates sleep spans (an
    /// old entry with no start/end has nothing to correct).
    init?(entry: RoutineEntryResponse) {
        guard entry.entry_type == "nap" || entry.entry_type == "night_sleep",
              let raw = entry.value?.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
              obj["in_progress"] as? Bool != true,
              let startText = obj["sleep_start"] as? String,
              let endText = obj["sleep_end"] as? String,
              let start = DateFormatter.dateTimeMinute.date(from: startText),
              let end = DateFormatter.dateTimeMinute.date(from: endText)
        else { return nil }
        self.id = entry.id
        self.kind = entry.entry_type == "nap" ? .nap : .night
        self.start = start
        self.end = end
        self.wakeCount = (obj["wake_count"] as? Int)
            ?? (obj["wake_count"] as? NSNumber)?.intValue ?? 0
        self.notes = entry.notes ?? ""
    }
}

/// Identifies the running sleep being corrected. `current` is its stored "HH:mm"
/// so the picker opens on the time already recorded, not on now.
struct SleepStartEdit: Identifiable {
    let current: String
    var id: String { current }
}

/// One picker: when they actually fell asleep. Deliberately not the full log
/// sheet — the sleep is still running, so there is no end time to ask for.
private struct EditSleepStartSheet: View {
    let current: String
    let accent: Color
    let onSave: (String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var time: Date
    @State private var isSaving = false

    init(current: String, accent: Color, onSave: @escaping (String) async -> Void) {
        self.current = current
        self.accent = accent
        self.onSave = onSave
        _time = State(initialValue: DateFormatter.hourMinute.date(from: current) ?? Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.large) {
                    Text("When did they actually fall asleep?")
                        .font(.flSubheadline)
                        .foregroundStyle(WarmPalette.ink2)

                    DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .tint(accent)

                    Text("Only the time changes — the sleep stays on the day it was logged.")
                        .font(.flFootnote)
                        .foregroundStyle(WarmPalette.ink3)

                    Button {
                        Task {
                            isSaving = true
                            await onSave(DateFormatter.hourMinute.string(from: time))
                            dismiss()
                        }
                    } label: {
                        Text("Save").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.flCTA)
                    .disabled(isSaving)
                }
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background { AmbientBackground(style: .home) }
            .navigationTitle("Start time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        // .large as well as .medium: a wheel picker plus copy and a button does
        // not fit half a screen on smaller phones, and overflow drew the content
        // under the navigation bar instead of scrolling.
        .presentationDetents([.medium, .large])
    }
}

/// Start, end, and a running duration. Every field is editable because sleep is
/// nearly always logged afterwards — mid-nap is the one time nobody reaches for
/// their phone.
private struct LogSleepSheet: View {
    let kind: SleepKind
    let accent: Color
    /// Set when correcting an already-logged sleep rather than adding one.
    let editing: LoggedSleep?
    let onSave: (SleepPayload) async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var start: Date
    @State private var end: Date
    @State private var wakeCount = 0
    @State private var notes = ""
    @State private var isSaving = false

    init(kind: SleepKind, accent: Color, editing: LoggedSleep? = nil,
         onSave: @escaping (SleepPayload) async -> Void) {
        self.kind = kind
        self.accent = accent
        self.editing = editing
        self.onSave = onSave
        if let editing {
            // Correcting: open on what was actually recorded, so a wrong end time
            // is a nudge rather than a re-entry.
            _start = State(initialValue: editing.start)
            _end = State(initialValue: editing.end)
            _wakeCount = State(initialValue: editing.wakeCount)
            _notes = State(initialValue: editing.notes)
        } else {
            // Defaults that match how each is actually logged: a nap gets written
            // up right after it ends, a night the morning after it started.
            let now = Date()
            _end = State(initialValue: now)
            _start = State(initialValue: kind == .nap
                           ? now.addingTimeInterval(-3600)
                           : Calendar.current.date(byAdding: .hour, value: -12, to: now) ?? now)
        }
    }

    /// End before start means it ran past midnight — the normal case for a night
    /// sleep, and possible for a late nap. Roll the end forward a day rather than
    /// rejecting it, so nobody has to fight the date picker at 6am.
    private var resolvedEnd: Date {
        end > start ? end : (Calendar.current.date(byAdding: .day, value: 1, to: end) ?? end)
    }

    private var minutes: Int { max(0, Int(resolvedEnd.timeIntervalSince(start) / 60)) }
    private var crossesMidnight: Bool { end <= start }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.large) {
                    durationCard

                    field(label: "Fell asleep") {
                        DatePicker("", selection: $start)
                            .labelsHidden()
                            .tint(accent)
                    }

                    field(label: "Woke up") {
                        DatePicker("", selection: $end, displayedComponents: crossesMidnight ? [.hourAndMinute] : [.date, .hourAndMinute])
                            .labelsHidden()
                            .tint(accent)
                    }

                    if kind == .night {
                        field(label: "Night wakings") {
                            Stepper("\(wakeCount) time\(wakeCount == 1 ? "" : "s")", value: $wakeCount, in: 0...20)
                                .font(.flBody)
                        }
                    }

                    field(label: "Notes (optional)") {
                        TextField(kind == .nap ? "e.g. in the carrier" : "e.g. teething", text: $notes, axis: .vertical)
                            .font(.flBody)
                            .lineLimit(1...3)
                    }

                    Button {
                        Task { await save() }
                    } label: {
                        Text("Save").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.flCTA)
                    .disabled(isSaving || minutes == 0)
                }
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                .padding(.top, 8)
                .padding(.bottom, DesignTokens.Spacing.bottomBuffer)
            }
            .background { AmbientBackground(style: .home) }
            .navigationTitle(editing == nil ? kind.title : "Edit sleep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var durationCard: some View {
        VStack(spacing: 6) {
            Text(SleepValue.durationText(minutes: minutes))
                .font(.flStat)
                .foregroundStyle(WarmPalette.ink1)
                .contentTransition(.numericText())
            Text(crossesMidnight ? "Overnight · ends the next day" : "Total sleep")
                .font(.flFootnote)
                .foregroundStyle(WarmPalette.ink3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .flCard(tint: accent.opacity(0.08))
    }

    @ViewBuilder
    private func field<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.flCaption.weight(.semibold))
                .foregroundStyle(WarmPalette.ink3)
            content()
                .padding(12)
                .flCard()
        }
    }

    private func save() async {
        isSaving = true
        var value: [String: Any] = [
            "sleep_start": DateFormatter.dateTimeMinute.string(from: start),
            "sleep_end": DateFormatter.dateTimeMinute.string(from: resolvedEnd),
            "duration_minutes": minutes,
        ]
        if kind == .night { value["wake_count"] = wakeCount }
        await onSave(SleepPayload(
            value: value,
            // Filed under the day it STARTED, so a 7pm–6am night belongs to the
            // evening it began rather than splitting across two dates.
            date: DateFormatter.isoDate.string(from: start),
            time: DateFormatter.hourMinute.string(from: start),
            endTime: DateFormatter.hourMinute.string(from: resolvedEnd),
            wakeCount: kind == .night ? wakeCount : nil,
            notes: notes.trimmingCharacters(in: .whitespaces)
        ))
        dismiss()
    }
}

// MARK: - Sleep stats

/// The averages, the age-appropriate range, and the tips the data earned.
/// Deliberately reads top-down: how much sleep, how it's trending, then what
/// (if anything) to do about it.
private struct SleepStatsCard: View {
    let stats: SleepStats
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                Image(systemName: "chart.bar")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WarmPalette.ink3)
                Text("Sleep")
                    .font(.flHeadline)
                    .foregroundStyle(WarmPalette.ink1)
                Spacer()
                if let days = stats.window_days, stats.hasData {
                    Text("Last \(days) days")
                        .font(.flFootnote)
                        .foregroundStyle(WarmPalette.ink3)
                }
            }

            if stats.hasData {
                headline
                metrics
                if let bedtime = stats.bedtime, let avg = bedtime.average {
                    bedtimeRow(avg, spread: bedtime.spread_minutes, wake: stats.wake_time?.average)
                }
            }

            if !stats.tips.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(stats.tips) { tip in
                        TipRow(tip: tip, accent: accent)
                    }
                }
            }

            Text("Educational only — not medical advice. Check anything that worries you with your pediatrician.")
                .font(.flCaption2)
                .foregroundStyle(WarmPalette.ink4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .flCard()
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(minutesText(stats.totals.avg_daily_minutes))
                .font(.flStat)
                .foregroundStyle(WarmPalette.ink1)
                .contentTransition(.numericText())
            HStack(spacing: 6) {
                Text("average a day")
                    .font(.flFootnote)
                    .foregroundStyle(WarmPalette.ink3)
                if let delta = stats.trend?.daily_delta_minutes, abs(delta) >= 5 {
                    Label(minutesText(abs(delta)), systemImage: delta > 0 ? "arrow.up" : "arrow.down")
                        .font(.flCaption.weight(.semibold))
                        .foregroundStyle(delta > 0 ? WarmPalette.good : WarmPalette.warn)
                }
            }
            if let label = stats.guidance?.recommended_label {
                Text("Typical for \(stats.guidance?.age_label?.lowercased() ?? "this age"): \(label)")
                    .font(.flCaption)
                    .foregroundStyle(WarmPalette.ink3)
            }
        }
    }

    private var metrics: some View {
        HStack(spacing: 8) {
            WarmStatTile(label: "Nights", value: minutesText(stats.totals.avg_night_minutes),
                         sub: "average", icon: "moon")
            WarmStatTile(label: "Naps", value: napsText, sub: "a day", icon: "sun.max")
            WarmStatTile(label: "Wakings", value: wakingsText, sub: "a night", icon: "eye")
        }
    }

    private func bedtimeRow(_ average: String, spread: Int?, wake: String?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "bed.double")
                .font(.system(size: 12))
                .foregroundStyle(WarmPalette.ink3)
            Text("Bedtime around \(average)")
                .font(.flFootnote)
                .foregroundStyle(WarmPalette.ink2)
            if let spread, spread > 0 {
                Text("· ±\(spread)m")
                    .font(.flFootnote)
                    .foregroundStyle(WarmPalette.ink3)
            }
            if let wake {
                Text("· up \(wake)")
                    .font(.flFootnote)
                    .foregroundStyle(WarmPalette.ink3)
            }
        }
    }

    private var napsText: String {
        guard let n = stats.totals.avg_naps_per_day else { return "—" }
        return n == n.rounded() ? "\(Int(n))" : String(format: "%.1f", n)
    }

    private var wakingsText: String {
        guard let n = stats.totals.avg_wakings else { return "—" }
        return n == n.rounded() ? "\(Int(n))" : String(format: "%.1f", n)
    }

    private func minutesText(_ minutes: Int?) -> String {
        guard let minutes else { return "—" }
        return SleepValue.durationText(minutes: minutes)
    }
}

private struct TipRow: View {
    let tip: SleepTip
    let accent: Color
    @State private var expanded = false

    var body: some View {
        Button {
            withAnimation(.snappy) { expanded.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: tip.isWatch ? "exclamationmark.circle.fill" : "lightbulb")
                        .font(.system(size: 13))
                        .foregroundStyle(tip.isWatch ? AccentTheme.terracotta.color : accent)
                    Text(tip.title)
                        .font(.flSubheadline.weight(.medium))
                        .foregroundStyle(WarmPalette.ink1)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WarmPalette.ink4)
                }
                if expanded {
                    Text(tip.detail)
                        .font(.flFootnote)
                        .foregroundStyle(WarmPalette.ink2)
                        .multilineTextAlignment(.leading)
                    if let source = tip.source {
                        Text(source)
                            .font(.flCaption2)
                            .foregroundStyle(WarmPalette.ink4)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(11)
            .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small))
        }
        .buttonStyle(.plain)
    }
}

/// Reads back what the sheet wrote. Kept in one place so the history row and the
/// sheet can never disagree about the shape of a sleep entry.
enum SleepValue {
    static func durationText(minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }

    /// "9:30 PM – 6:45 AM · 9h 15m", or nil for entries logged before sleep
    /// spans existed (they simply show their type and date as they always did).
    static func summary(from raw: String?) -> String? {
        guard let raw, let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let minutes = (obj["duration_minutes"] as? Int)
            ?? (obj["duration_minutes"] as? NSNumber)?.intValue
        guard let startText = obj["sleep_start"] as? String,
              let endText = obj["sleep_end"] as? String,
              let start = DateFormatter.dateTimeMinute.date(from: startText),
              let end = DateFormatter.dateTimeMinute.date(from: endText)
        else { return minutes.map { durationText(minutes: $0) } }

        let span = "\(DateFormatter.shortTime.string(from: start)) – \(DateFormatter.shortTime.string(from: end))"
        let mins = minutes ?? max(0, Int(end.timeIntervalSince(start) / 60))
        var text = "\(span) · \(durationText(minutes: mins))"
        if let wakes = (obj["wake_count"] as? Int) ?? (obj["wake_count"] as? NSNumber)?.intValue, wakes > 0 {
            text += " · woke \(wakes)×"
        }
        return text
    }
}

private struct EntryRow: View {
    let entry: RoutineEntryResponse
    /// Present when this row can be corrected; drives the tap target and the
    /// pencil, so a row only advertises editing when it actually supports it.
    var onEdit: (() -> Void)?
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.flSubheadline.weight(.medium))
                    .foregroundStyle(isSkippedSession ? WarmPalette.ink3 : WarmPalette.ink1)
                // A sleep entry leads with its span and duration; everything else
                // keeps the date/time stamp it has always shown.
                if let sleep = SleepValue.summary(from: entry.value), isSleep {
                    Text(sleep)
                        .font(.flCaption.weight(.medium))
                        .foregroundStyle(WarmPalette.ink2)
                    Text(entry.entry_date)
                        .font(.flCaption)
                        .foregroundStyle(WarmPalette.ink3)
                } else {
                    Text(entry.entry_time != nil ? "\(entry.entry_date) · \(entry.entry_time!)" : entry.entry_date)
                        .font(.flCaption)
                        .foregroundStyle(WarmPalette.ink3)
                }
                if let notes = entry.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.flFootnote)
                        .foregroundStyle(WarmPalette.ink3)
                }
            }
            Spacer()
            if onEdit != nil {
                Image(systemName: "pencil")
                    .font(.system(size: 12))
                    .foregroundStyle(WarmPalette.ink4)
            }
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundStyle(WarmPalette.ink4)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .flCard()
        .contentShape(Rectangle())
        .onTapGesture { onEdit?() }
    }

    private var label: String {
        if isSkippedSession { return "Skipped" }
        return switch entry.entry_type {
        case "period_start": "Period started"
        case "period_end": "Period ended"
        case "symptom": "Symptom"
        case "nap": "Nap"
        case "night_sleep": "Night sleep"
        case "wake": "Woke up"
        case "milestone": "Milestone"
        case "session", "attended": "Session"
        case "note", .none: "Logged"
        case .some(let t): t.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private var isSleep: Bool {
        entry.entry_type == "nap" || entry.entry_type == "night_sleep"
    }

    // A session entry whose stored value marks it skipped — shown muted so it's
    // distinct from an attended session, matching the backend's milestone rule.
    private var isSkippedSession: Bool {
        guard entry.entry_type == "session" || entry.entry_type == "attended",
              let raw = entry.value?.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any]
        else { return false }
        return obj["status"] as? String == "skipped"
    }
}

/// Simple wrapping row of chips (no external dependency).
private struct FlowButtons<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        // A lazy grid gives a clean wrap without hand-rolling layout math.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
            content
        }
    }
}

#Preview {
    NavigationStack {
        RoutineDetailView(routineId: 1)
    }
    .environment(APIService())
    .environment(AuthService())
}
