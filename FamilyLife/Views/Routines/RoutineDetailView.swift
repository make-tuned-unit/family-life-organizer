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

                        quickLog(for: detail.type)

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
                    logButton("Nap", "sun.max.fill", entryType: "nap")
                    logButton("Night sleep", "moon.fill", entryType: "night_sleep")
                    logButton("Woke up", "sunrise.fill", entryType: "wake")
                    logButton("Milestone", "star.fill", entryType: "milestone")
                case .activity:
                    logButton("Did it today", "checkmark.circle.fill", entryType: "session")
                    logButton("Skipped", "xmark.circle", entryType: "session", value: ["status": "skipped"])
                case .custom:
                    logButton("Done today", "checkmark", entryType: "note")
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
            Label(title, systemImage: icon)
                .font(.flFootnote.weight(.semibold))
                .foregroundStyle(accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(accent.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
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
                    EntryRow(entry: entry) { Task { await deleteEntry(entry.id) } }
                }
            }
        }
    }

    // MARK: - Data

    private func load() async {
        do {
            let d = try await api.fetchRoutine(id: routineId)
            detail = d
            errorMessage = nil
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

    // Confirm (or mark skipped) attendance for a specific linked calendar date.
    private func confirm(date: String, attended: Bool) async {
        // The user has answered directly, so retire the pending "did you go?" nudge.
        NotificationService.shared.cancelActivityConfirmation(routineId: routineId, date: date)
        await log(entryType: "session", value: attended ? nil : ["status": "skipped"], date: date)
    }

    private func log(entryType: String, value: [String: Any]? = nil, date: String? = nil) async {
        var data: [String: Any] = ["entry_type": entryType]
        if let value { data["value"] = value }
        if let date { data["entry_date"] = date }
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
            dismiss()
        } catch {
            errorMessage = "Couldn't delete this routine."
        }
    }
}

private struct EntryRow: View {
    let entry: RoutineEntryResponse
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.flSubheadline.weight(.medium))
                    .foregroundStyle(isSkippedSession ? WarmPalette.ink3 : WarmPalette.ink1)
                Text(entry.entry_time != nil ? "\(entry.entry_date) · \(entry.entry_time!)" : entry.entry_date)
                    .font(.flCaption)
                    .foregroundStyle(WarmPalette.ink3)
                if let notes = entry.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.flFootnote)
                        .foregroundStyle(WarmPalette.ink3)
                }
            }
            Spacer()
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundStyle(WarmPalette.ink4)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .flCard()
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
