import HealthKit
import SwiftUI

struct RivalryDetailView: View {
    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss
    let rivalry: RivalryResponse
    let onChange: (() async -> Void)?

    @State private var currentRivalry: RivalryResponse
    @State private var showingDeleteConfirm = false
    @State private var isDeleting = false
    @State private var entries: [RivalryEntryResponse] = []
    @State private var showingLogProgress = false
    @State private var error: String?
    @State private var healthSteps: Double?
    @State private var isSyncingSteps = false
    @State private var hasAutoSynced = false
    @State private var completionMessage: String?
    @State private var showingLevelUp: FamilyTier?
    @State private var healthKit = HealthKitManager()

    @Environment(AuthService.self) private var auth

    init(rivalry: RivalryResponse, onChange: (() async -> Void)? = nil) {
        self.rivalry = rivalry
        self.onChange = onChange
        _currentRivalry = State(initialValue: rivalry)
    }

    private var initiatorTotal: Double {
        entriesTotal(for: currentRivalry.initiator_name)
    }

    private var opponentTotal: Double {
        entriesTotal(for: currentRivalry.opponent_name)
    }

    private var participantScores: [(name: String, total: Double)] {
        currentRivalry.participantNames.map { name in
            (name: name, total: entriesTotal(for: name))
        }.sorted { $0.total > $1.total }
    }

    private var teamATotal: Double { currentRivalry.teamANames.reduce(0) { $0 + entriesTotal(for: $1) } }
    private var teamBTotal: Double { currentRivalry.teamBNames.reduce(0) { $0 + entriesTotal(for: $1) } }

    @ViewBuilder
    private func teamColumn(names: [String], total: Double, color: Color, leading: Bool) -> some View {
        VStack(spacing: 4) {
            Text(leading ? "Leading" : " ")
                .font(.caption2.weight(.bold))
                .foregroundStyle(leading ? color : .clear)
            Text(Int(total).formatted())
                .font(.title.bold())
                .foregroundStyle(color)
            Text(names.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(WarmPalette.ink3)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }

    /// Match entries to a participant name, handling "Sophie" vs "Sophie Chiasson" mismatches
    private func entriesTotal(for name: String) -> Double {
        entries.filter { rivalryNameMatches($0.member_name, name) }.reduce(0) { $0 + $1.value }
    }

    private var isExpired: Bool {
        guard let endDate = currentRivalry.endDate else { return false }
        return Date() > endDate
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Winner banner
                if currentRivalry.status == RivalryStatus.completed.rawValue {
                    VStack(spacing: 8) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(AccentTheme.saffron.color)
                        if let winner = currentRivalry.winner_name {
                            Text("\(winner) Wins!")
                                .font(.title2.bold())
                                .foregroundStyle(WarmPalette.ink1)
                        } else {
                            Text("It's a Tie!")
                                .font(.title2.bold())
                                .foregroundStyle(WarmPalette.ink1)
                        }
                        if let msg = completionMessage {
                            Text(msg)
                                .font(.flFootnote)
                                .foregroundStyle(WarmPalette.ink2)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 8)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .flCard(tint: AccentTheme.saffron.color)
                    .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                }

                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: currentRivalry.challengeType.icon)
                            .font(.title2)
                            .foregroundStyle(challengeColor)
                        Text(currentRivalry.title)
                            .font(.headline)
                        Spacer()
                        StatusBadge(status: currentRivalry.statusValue)
                    }

                    if currentRivalry.isTeam {
                        // Team scoreboard: two team totals, then per-member breakdown.
                        HStack(spacing: 16) {
                            teamColumn(names: currentRivalry.teamANames, total: teamATotal, color: TabAccent.home.color, leading: teamATotal >= teamBTotal)
                            Text("vs").font(.title3.bold()).foregroundStyle(WarmPalette.ink3)
                            teamColumn(names: currentRivalry.teamBNames, total: teamBTotal, color: AccentTheme.saffron.color, leading: teamBTotal > teamATotal)
                        }
                        let maxVal = participantScores.first?.total ?? 0
                        VStack(spacing: 6) {
                            ForEach(Array(participantScores.enumerated()), id: \.element.name) { _, ps in
                                let onA = currentRivalry.teamANames.contains { rivalryNameMatches(ps.name, $0) }
                                ProgressRow(name: ps.name, value: ps.total, maxValue: maxVal, color: onA ? TabAccent.home.color : AccentTheme.saffron.color)
                            }
                        }
                    } else if currentRivalry.isMultiPlayer {
                        // Multi-player scoreboard
                        let maxVal = participantScores.first?.total ?? 0
                        VStack(spacing: 6) {
                            ForEach(Array(participantScores.enumerated()), id: \.element.name) { _, ps in
                                ProgressRow(name: ps.name, value: ps.total, maxValue: maxVal, color: PersonPalette.color(for: ps.name))
                            }
                        }
                    } else {
                        // Classic 1v1
                        HStack(spacing: 20) {
                            PlayerColumn(name: currentRivalry.initiator_name, value: initiatorTotal, color: PersonPalette.color(for: currentRivalry.initiator_name), isLeading: initiatorTotal > opponentTotal)
                            Text("vs")
                                .font(.title3.bold())
                                .foregroundStyle(WarmPalette.ink3)
                            PlayerColumn(name: currentRivalry.opponent_name, value: opponentTotal, color: PersonPalette.color(for: currentRivalry.opponent_name), isLeading: opponentTotal > initiatorTotal)
                        }

                        VStack(spacing: 4) {
                            ProgressRow(name: currentRivalry.initiator_name, value: initiatorTotal, maxValue: max(initiatorTotal, opponentTotal), color: PersonPalette.color(for: currentRivalry.initiator_name))
                            ProgressRow(name: currentRivalry.opponent_name, value: opponentTotal, maxValue: max(initiatorTotal, opponentTotal), color: PersonPalette.color(for: currentRivalry.opponent_name))
                        }
                    }

                    HStack {
                        Label("\(currentRivalry.point_value) pts to winner", systemImage: "trophy.fill")
                            .font(.caption)
                            .foregroundStyle(WarmPalette.ink3)
                        Spacer()
                        if currentRivalry.status == RivalryStatus.active.rawValue, let endDate = currentRivalry.endDate {
                            let days = Calendar.current.dateComponents([.day], from: Date(), to: endDate).day ?? 0
                            Text(days >= 0 ? "\(days) days left" : "Overtime")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(days <= 1 ? .red : .secondary)
                        }
                    }
                }
                .padding(DesignTokens.Spacing.cardPadding)
                .flCard(tint: TabAccent.rivalries.color)
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)

                if currentRivalry.status == RivalryStatus.active.rawValue {
                    // HealthKit auto-sync for steps/stairs challenges
                    if currentRivalry.challengeType.isHealthKitSynced && healthSteps == nil {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading \(currentRivalry.challengeType.healthMetricLabel) from Apple Health...")
                                .font(.flFootnote)
                                .foregroundStyle(WarmPalette.ink3)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(DesignTokens.Spacing.cardPadding)
                        .flCard(tint: AccentTheme.ocean.color)
                        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                    }

                    if currentRivalry.challengeType.isHealthKitSynced, let hkSteps = healthSteps {
                        let myTotal = myLoggedTotal
                        let delta = hkSteps - myTotal
                        VStack(spacing: 8) {
                            HStack {
                                Image(systemName: "heart.fill")
                                    .foregroundStyle(.red)
                                Text("Apple Health: \(Int(hkSteps)) \(currentRivalry.challengeType.healthMetricLabel)")
                                    .font(.flSubheadline.weight(.semibold))
                                Spacer()
                                if delta > 0 {
                                    Text("+\(Int(delta)) to sync")
                                        .font(.flCaption.weight(.medium))
                                        .foregroundStyle(WarmPalette.good)
                                }
                            }
                            if delta > 0 {
                                Button {
                                    Task { await syncDailyTotalsFromHealth() }
                                } label: {
                                    Label(isSyncingSteps ? "Syncing..." : "Sync from Health", systemImage: "arrow.triangle.2.circlepath")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.flPrimary(tint: AccentTheme.ocean.color))
                                .disabled(isSyncingSteps)
                            } else {
                                Text("\(currentRivalry.challengeType.displayName) are up to date")
                                    .font(.flCaption)
                                    .foregroundStyle(WarmPalette.ink3)
                            }
                        }
                        .padding(DesignTokens.Spacing.cardPadding)
                        .flCard(tint: AccentTheme.ocean.color)
                        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                    }

                    // For HealthKit challenges, sync replaces manual logging
                    if !currentRivalry.challengeType.isHealthKitSynced {
                        HStack(spacing: 12) {
                            Button {
                                showingLogProgress = true
                            } label: {
                                Label("Log Progress", systemImage: "plus.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.flPrimary(tint: TabAccent.rivalries.color))
                        }
                        .padding(.horizontal)
                    }

                    if isExpired {
                        Button {
                            Task { await completeRivalry() }
                        } label: {
                            Text("Finalize Results")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.flPrimary(tint: WarmPalette.good))
                        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                    }
                }

                if !entries.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Activity Log")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(entries) { entry in
                            EntryRowRemote(entry: entry, rivalry: currentRivalry)
                                .padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .background { AmbientBackground(style: .rivalries) }
        .navigationTitle(currentRivalry.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) { showingDeleteConfirm = true } label: {
                        Label("Delete Challenge", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("Delete this challenge?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await deleteRivalry() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the challenge and all logged progress for everyone. This can't be undone.")
        }
        .sheet(isPresented: $showingLogProgress) {
            LogProgressView(rivalry: currentRivalry, memberName: myRivalryName) {
                await loadEntries()
            }
        }
        .inlineError(error) { error = nil }
        .task {
            await loadEntries()
            if currentRivalry.challengeType.isHealthKitSynced && !hasAutoSynced {
                hasAutoSynced = true
                await fetchHealthData()
                // Auto-sync per-day totals from HealthKit without requiring manual tap
                await syncDailyTotalsFromHealth()
            }
            // Auto-complete expired rivalries
            if currentRivalry.status == RivalryStatus.active.rawValue && isExpired {
                await autoCompleteRivalry()
            }
        }
        .fullScreenCover(item: $showingLevelUp) { tier in
            LevelUpCelebration(tier: tier)
        }
    }

    /// Find the current user's name as it appears in the rivalry (e.g. "Sophie Chiasson" not "Sophie")
    private var myRivalryName: String {
        let name = auth.currentUser?.name ?? ""
        let username = auth.currentUser?.username ?? ""
        for participant in currentRivalry.participantNames {
            if rivalryNameMatches(participant, name) || rivalryNameMatches(participant, username) {
                return participant
            }
        }
        return name.isEmpty ? username : name
    }

    private var myLoggedTotal: Double {
        let myName = myRivalryName
        return entries.filter { rivalryNameMatches($0.member_name, myName) }.reduce(0) { $0 + $1.value }
    }

    private func fetchHealthData() async {
        let authorized: Bool
        if currentRivalry.challengeType == .stairs {
            authorized = await healthKit.requestFlightsAuthorization()
        } else {
            authorized = await healthKit.requestStepAuthorization()
        }
        guard authorized else {
            healthSteps = 0
            return
        }

        let startDate = ISO8601DateFormatter.flexible.date(from: currentRivalry.start_date)
            ?? DateFormatter.isoDate.date(from: currentRivalry.start_date)
            ?? Date()
        let endDate = currentRivalry.endDate ?? Date()

        if currentRivalry.challengeType == .stairs {
            healthSteps = await healthKit.fetchFlightsClimbed(from: startDate, to: min(endDate, Date()))
        } else {
            healthSteps = await healthKit.fetchSteps(from: startDate, to: min(endDate, Date()))
        }
    }

    /// Push one idempotent daily total per calendar day to the backend. The
    /// server upserts per (rivalry, member, day), so re-syncing never doubles.
    private func syncDailyTotalsFromHealth() async {
        let isStairs = currentRivalry.challengeType == .stairs
        let authorized = isStairs
            ? await healthKit.requestFlightsAuthorization()
            : await healthKit.requestStepAuthorization()
        guard authorized else { return }

        let startDate = ISO8601DateFormatter.flexible.date(from: currentRivalry.start_date)
            ?? DateFormatter.isoDate.date(from: currentRivalry.start_date)
            ?? Date()
        let endDate = currentRivalry.endDate ?? Date()
        let identifier: HKQuantityTypeIdentifier = isStairs ? .flightsClimbed : .stepCount
        let daily = await healthKit.fetchDailyTotals(for: identifier, from: startDate, to: min(endDate, Date()))
        guard !daily.isEmpty else { return }

        let dayFormatter = DateFormatter()
        dayFormatter.calendar = Calendar.current
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"

        isSyncingSteps = true
        do {
            for entry in daily {
                try await api.addRivalryEntry(id: currentRivalry.id, data: [
                    "member_name": myRivalryName,
                    "value": Int(entry.value.rounded()),
                    "activity_date": dayFormatter.string(from: entry.day),
                    "note": "Synced from Apple Health",
                    "is_verified": true
                ])
            }
            await loadEntries()
            await fetchHealthData()
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
        isSyncingSteps = false
    }

    private var challengeColor: Color {
        switch currentRivalry.challengeType {
        case .steps, .stairs: AccentTheme.ocean.color
        case .workout, .pushups, .squats, .situps, .plank: AccentTheme.saffron.color
        case .running: AccentTheme.ocean.color
        case .habit: WarmPalette.good
        case .custom: AccentTheme.mauve.color
        }
    }

    private func loadEntries() async {
        do {
            entries = try await api.fetchRivalryEntries(id: currentRivalry.id)
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }

    private func deleteRivalry() async {
        guard !isDeleting else { return }
        isDeleting = true
        do {
            try await api.deleteRivalry(id: currentRivalry.id)
            await onChange?()
            dismiss()
        } catch {
            isDeleting = false
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }

    private func autoCompleteRivalry() async {
        // Steps already synced by .task — just complete
        await completeRivalry()
    }

    private func completeRivalry() async {
        do {
            let result = try await api.completeRivalry(id: currentRivalry.id)
            completionMessage = result.message
            currentRivalry = RivalryResponse(
                id: currentRivalry.id,
                title: currentRivalry.title,
                challenge_type: currentRivalry.challenge_type,
                initiator_name: currentRivalry.initiator_name,
                opponent_name: currentRivalry.opponent_name,
                start_date: currentRivalry.start_date,
                end_date: currentRivalry.end_date,
                status: RivalryStatus.completed.rawValue,
                point_value: currentRivalry.point_value,
                winner_name: result.winner_name,
                created_at: currentRivalry.created_at,
                participants: currentRivalry.participants,
                rivalry_type: currentRivalry.rivalry_type,
                team_a: currentRivalry.team_a,
                team_b: currentRivalry.team_b,
                winner_team: result.winner_team
            )
            // Level-up check
            let myName = auth.currentUser?.name ?? ""
            if result.winner_name?.localizedCaseInsensitiveCompare(myName) == .orderedSame {
                let oldXP = UserDefaults.standard.integer(forKey: "rivalry_xp")
                let newXP = oldXP + currentRivalry.point_value
                let oldTier = FamilyTier.tier(for: oldXP)
                let newTier = FamilyTier.tier(for: newXP)
                UserDefaults.standard.set(newXP, forKey: "rivalry_xp")
                if newTier.rawValue > oldTier.rawValue {
                    showingLevelUp = newTier
                }
            }
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }

}

struct EntryRowRemote: View {
    let entry: RivalryEntryResponse
    let rivalry: RivalryResponse

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(PersonPalette.color(for: entry.member_name))
                .frame(width: 10, height: 10)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.member_name)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(entry.value, specifier: "%.0f")")
                        .font(.subheadline.bold())
                }
                if let note = entry.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(WarmPalette.ink3)
                }
            }
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .flCard(tint: TabAccent.rivalries.color)
    }
}

#Preview {
    NavigationStack {
        RivalryDetailView(
            rivalry: RivalryResponse(id: 1, title: "Step Challenge", challenge_type: "steps", initiator_name: "Jesse", opponent_name: "Sophie", start_date: "2026-04-01", end_date: "2026-04-10", status: "active", point_value: 100, winner_name: nil, created_at: nil, participants: nil, rivalry_type: nil, team_a: nil, team_b: nil, winner_team: nil)
        )
        .environment(APIService())
    }
}
