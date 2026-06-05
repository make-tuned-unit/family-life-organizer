import SwiftUI

struct RivalryDetailView: View {
    @Environment(APIService.self) private var api
    let rivalry: RivalryResponse

    @State private var currentRivalry: RivalryResponse
    @State private var entries: [RivalryEntryResponse] = []
    @State private var showingLogProgress = false
    @State private var error: String?
    @State private var healthSteps: Double?
    @State private var isSyncingSteps = false
    @State private var completionMessage: String?
    @State private var showingLevelUp: FamilyTier?
    private let healthKit = HealthKitManager()

    @Environment(AuthService.self) private var auth

    init(rivalry: RivalryResponse) {
        self.rivalry = rivalry
        _currentRivalry = State(initialValue: rivalry)
    }

    private var initiatorTotal: Double {
        entries.filter { $0.member_name.localizedCaseInsensitiveCompare(currentRivalry.initiator_name) == .orderedSame }.reduce(0) { $0 + $1.value }
    }

    private var opponentTotal: Double {
        entries.filter { $0.member_name.localizedCaseInsensitiveCompare(currentRivalry.opponent_name) == .orderedSame }.reduce(0) { $0 + $1.value }
    }

    private var participantScores: [(name: String, total: Double)] {
        currentRivalry.participantNames.map { name in
            let total = entries.filter { $0.member_name.localizedCaseInsensitiveCompare(name) == .orderedSame }.reduce(0) { $0 + $1.value }
            return (name: name, total: total)
        }.sorted { $0.total > $1.total }
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
                                .font(.system(size: 13))
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

                    if currentRivalry.isMultiPlayer {
                        // Multi-player scoreboard
                        let maxVal = participantScores.first?.total ?? 0
                        VStack(spacing: 6) {
                            ForEach(Array(participantScores.enumerated()), id: \.element.name) { index, ps in
                                let color = index == 0 ? TabAccent.home.color : (index == 1 ? AccentTheme.saffron.color : AccentTheme.ocean.color)
                                ProgressRow(name: ps.name, value: ps.total, maxValue: maxVal, color: color)
                            }
                        }
                    } else {
                        // Classic 1v1
                        HStack(spacing: 20) {
                            PlayerColumn(name: currentRivalry.initiator_name, value: initiatorTotal, color: TabAccent.home.color, isLeading: initiatorTotal > opponentTotal)
                            Text("vs")
                                .font(.title3.bold())
                                .foregroundStyle(WarmPalette.ink3)
                            PlayerColumn(name: currentRivalry.opponent_name, value: opponentTotal, color: AccentTheme.saffron.color, isLeading: opponentTotal > initiatorTotal)
                        }

                        VStack(spacing: 4) {
                            ProgressRow(name: currentRivalry.initiator_name, value: initiatorTotal, maxValue: max(initiatorTotal, opponentTotal), color: TabAccent.home.color)
                            ProgressRow(name: currentRivalry.opponent_name, value: opponentTotal, maxValue: max(initiatorTotal, opponentTotal), color: AccentTheme.saffron.color)
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
                    // HealthKit auto-sync for steps challenges
                    if currentRivalry.challengeType == .steps && healthSteps == nil {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading steps from Apple Health...")
                                .font(.system(size: 13))
                                .foregroundStyle(WarmPalette.ink3)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(DesignTokens.Spacing.cardPadding)
                        .flCard(tint: AccentTheme.ocean.color)
                        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                    }

                    if currentRivalry.challengeType == .steps, let hkSteps = healthSteps {
                        let myTotal = myLoggedTotal
                        let delta = hkSteps - myTotal
                        VStack(spacing: 8) {
                            HStack {
                                Image(systemName: "heart.fill")
                                    .foregroundStyle(.red)
                                Text("Apple Health: \(Int(hkSteps)) steps")
                                    .font(.system(size: 14, weight: .semibold))
                                Spacer()
                                if delta > 0 {
                                    Text("+\(Int(delta)) to sync")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(WarmPalette.good)
                                }
                            }
                            if delta > 0 {
                                Button {
                                    Task { await syncStepsFromHealth(delta: delta) }
                                } label: {
                                    Label(isSyncingSteps ? "Syncing..." : "Sync Steps from Health", systemImage: "arrow.triangle.2.circlepath")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.flPrimary(tint: AccentTheme.ocean.color))
                                .disabled(isSyncingSteps)
                            } else {
                                Text("Steps are up to date")
                                    .font(.system(size: 12))
                                    .foregroundStyle(WarmPalette.ink3)
                            }
                        }
                        .padding(DesignTokens.Spacing.cardPadding)
                        .flCard(tint: AccentTheme.ocean.color)
                        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                    }

                    // For steps challenges, HealthKit sync replaces manual logging
                    if currentRivalry.challengeType != .steps {
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
        .sheet(isPresented: $showingLogProgress) {
            LogProgressView(rivalry: currentRivalry, memberName: auth.currentUser?.name ?? auth.currentUser?.username ?? "Me") {
                await loadEntries()
            }
        }
        .alert("Couldn’t update rivalry", isPresented: errorAlertIsPresented) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "An unexpected error occurred.")
        }
        .task {
            await loadEntries()
            if currentRivalry.challengeType == .steps {
                await fetchHealthSteps()
                // Auto-sync steps from HealthKit without requiring manual tap
                if let hkSteps = healthSteps {
                    let delta = hkSteps - myLoggedTotal
                    if delta > 0 {
                        await syncStepsFromHealth(delta: delta)
                    }
                }
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

    private var myLoggedTotal: Double {
        let myName = auth.currentUser?.name ?? auth.currentUser?.username ?? ""
        return entries.filter { $0.member_name.localizedCaseInsensitiveCompare(myName) == .orderedSame }.reduce(0) { $0 + $1.value }
    }

    private func fetchHealthSteps() async {
        let authorized = await healthKit.requestStepAuthorization()
        guard authorized else {
            healthSteps = 0
            return
        }

        let startDate = ISO8601DateFormatter.flexible.date(from: currentRivalry.start_date)
            ?? DateFormatter.isoDate.date(from: currentRivalry.start_date)
            ?? Date()
        let endDate = currentRivalry.endDate ?? Date()

        let steps = await healthKit.fetchSteps(from: startDate, to: min(endDate, Date()))
        healthSteps = steps
    }

    private func syncStepsFromHealth(delta: Double) async {
        isSyncingSteps = true
        do {
            try await api.addRivalryEntry(id: currentRivalry.id, data: [
                "member_name": auth.currentUser?.name ?? auth.currentUser?.username ?? "Me",
                "value": delta,
                "note": "Synced from Apple Health",
                "is_verified": true
            ])
            await loadEntries()
            await fetchHealthSteps()
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
        isSyncingSteps = false
    }

    private var challengeColor: Color {
        switch currentRivalry.challengeType {
        case .steps: AccentTheme.ocean.color
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

    private func autoCompleteRivalry() async {
        // Auto-sync steps first if applicable
        if currentRivalry.challengeType == .steps, let hkSteps = healthSteps {
            let delta = hkSteps - myLoggedTotal
            if delta > 0 {
                await syncStepsFromHealth(delta: delta)
            }
        }
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
                participants: currentRivalry.participants
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

    private var errorAlertIsPresented: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    }
}

struct EntryRowRemote: View {
    let entry: RivalryEntryResponse
    let rivalry: RivalryResponse

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(entry.member_name == rivalry.initiator_name ? TabAccent.home.color : .orange)
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
            rivalry: RivalryResponse(id: 1, title: "Step Challenge", challenge_type: "steps", initiator_name: "Jesse", opponent_name: "Sophie", start_date: "2026-04-01", end_date: "2026-04-10", status: "active", point_value: 100, winner_name: nil, created_at: nil, participants: nil)
        )
        .environment(APIService())
    }
}
