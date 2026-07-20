import SwiftUI

/// A single routine: its recent entries, a type-appropriate quick-log, and —
/// for the guided sleep-training program — the current age phase with a link to
/// the full program.
struct RoutineDetailView: View {
    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss

    let routineId: Int

    @State private var detail: RoutineDetailResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingDeleteConfirm = false

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
                        if let guidance = detail.guidance {
                            SleepGuidanceCard(guidance: guidance)
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
        .confirmationDialog("Delete this routine and all its entries?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await deleteRoutine() } }
            Button("Cancel", role: .cancel) {}
        }
        .inlineError(errorMessage) { errorMessage = nil }
        .task { await load() }
        .refreshable { await load() }
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
                case .custom:
                    logButton("Done today", "checkmark", entryType: "note")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .flCard()
    }

    private func logButton(_ title: String, _ icon: String, entryType: String) -> some View {
        Button {
            Task { await log(entryType: entryType) }
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
            detail = try await api.fetchRoutine(id: routineId)
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load this routine."
        }
        isLoading = false
    }

    private func log(entryType: String) async {
        do {
            try await api.addRoutineEntry(id: routineId, data: ["entry_type": entryType])
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
                    .foregroundStyle(WarmPalette.ink1)
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
        switch entry.entry_type {
        case "period_start": "Period started"
        case "period_end": "Period ended"
        case "symptom": "Symptom"
        case "nap": "Nap"
        case "night_sleep": "Night sleep"
        case "wake": "Woke up"
        case "milestone": "Milestone"
        case "note", .none: "Logged"
        case .some(let t): t.replacingOccurrences(of: "_", with: " ").capitalized
        }
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
}
