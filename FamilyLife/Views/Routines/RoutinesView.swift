import SwiftUI

/// Home for the Routines feature — a list of the household's trackers (cycles,
/// baby sleep, the guided sleep-training program, custom habits) with a path to
/// create a new one.
struct RoutinesView: View {
    @Environment(APIService.self) private var api

    @State private var routines: [RoutineResponse] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingNew = false

    private let accent = TabAccent.routines.color

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                FLScreenHeader(
                    eyebrow: routines.isEmpty ? "Track what repeats" : "\(routines.count) active",
                    title: "Routines",
                    subtitle: "Cycles, baby sleep, and the rhythms of family life.",
                    accent: accent
                )

                if isLoading {
                    FLLoadingState(message: "Loading your routines…")
                        .padding(.top, 40)
                } else if routines.isEmpty {
                    WarmEmptyState(
                        title: "No routines yet",
                        systemImage: "repeat",
                        description: "Track a menstrual cycle, a baby's sleep, or start the guided sleep-training program — newborn to 4 years.",
                        actionLabel: "New routine",
                        action: { showingNew = true }
                    )
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(routines) { routine in
                            NavigationLink {
                                RoutineDetailView(routineId: routine.id)
                            } label: {
                                RoutineCard(routine: routine)
                            }
                            .buttonStyle(.flCardPress)
                        }
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
                Button { showingNew = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accent)
                }
            }
        }
        .inlineError(errorMessage) { errorMessage = nil }
        .sheet(isPresented: $showingNew) {
            NewRoutineView { Task { await load() } }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            routines = try await api.fetchRoutines()
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load your routines. Pull to try again."
        }
        isLoading = false
    }
}

private struct RoutineCard: View {
    let routine: RoutineResponse

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: routine.icon ?? routine.type.icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(TabAccent.routines.color)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 40, height: 40)
                .background(TabAccent.routines.color.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(routine.name)
                    .font(.flSubheadline.weight(.semibold))
                    .foregroundStyle(WarmPalette.ink1)
                HStack(spacing: 6) {
                    Text(routine.type.displayName)
                        .font(.flCaption.weight(.medium))
                        .foregroundStyle(TabAccent.routines.color)
                    if let subject = routine.subject_name, !subject.isEmpty {
                        Text("· \(subject)")
                            .font(.flCaption)
                            .foregroundStyle(WarmPalette.ink3)
                    }
                }
                Text(subtitle)
                    .font(.flFootnote)
                    .foregroundStyle(WarmPalette.ink3)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WarmPalette.ink4)
        }
        .padding(14)
        .flCard()
    }

    private var subtitle: String {
        let count = routine.entry_count ?? 0
        if count == 0 { return "No entries yet — tap to start" }
        if let last = routine.last_entry_date { return "\(count) entries · last \(last)" }
        return "\(count) entries"
    }
}

#Preview {
    NavigationStack {
        RoutinesView()
    }
    .environment(APIService())
}
