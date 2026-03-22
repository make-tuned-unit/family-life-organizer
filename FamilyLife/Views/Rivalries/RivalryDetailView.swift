import SwiftUI
import SwiftData

struct RivalryDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let rivalry: Rivalry

    @Query(sort: \RivalryEntry.loggedAt, order: .reverse)
    private var allEntries: [RivalryEntry]
    @State private var showingLogProgress = false
    @State private var showingWinOverlay = false
    @State private var healthKitManager = HealthKitManager()
    @State private var isSyncingHealth = false

    // Current user
    private let currentUserName = "Jesse"
    private let currentUserID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    private var entries: [RivalryEntry] {
        allEntries.filter { $0.rivalryID == rivalry.id }
    }

    private var initiatorTotal: Double {
        entries.filter { $0.memberID == rivalry.initiatorID }.reduce(0) { $0 + $1.value }
    }

    private var opponentTotal: Double {
        entries.filter { $0.memberID == rivalry.opponentID }.reduce(0) { $0 + $1.value }
    }

    private var isExpired: Bool {
        Date() > rivalry.endDate
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header card
                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: rivalry.challengeType.icon)
                            .font(.title2)
                            .foregroundStyle(challengeColor)
                        Text(rivalry.title)
                            .font(.headline)
                        Spacer()
                        StatusBadge(status: rivalry.status)
                    }

                    // Score comparison
                    HStack(spacing: 20) {
                        PlayerColumn(name: rivalry.initiatorName, value: initiatorTotal, color: .teal, isLeading: initiatorTotal > opponentTotal)
                        Text("vs")
                            .font(.title3.bold())
                            .foregroundStyle(.secondary)
                        PlayerColumn(name: rivalry.opponentName, value: opponentTotal, color: .orange, isLeading: opponentTotal > initiatorTotal)
                    }

                    // Progress bars
                    VStack(spacing: 4) {
                        ProgressRow(name: rivalry.initiatorName, value: initiatorTotal, maxValue: max(initiatorTotal, opponentTotal), color: .teal)
                        ProgressRow(name: rivalry.opponentName, value: opponentTotal, maxValue: max(initiatorTotal, opponentTotal), color: .orange)
                    }

                    // Points & time
                    HStack {
                        Label("\(rivalry.pointValue) pts to winner", systemImage: "trophy.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if rivalry.status == .active {
                            let days = Calendar.current.dateComponents([.day], from: Date(), to: rivalry.endDate).day ?? 0
                            Text(days >= 0 ? "\(days) days left" : "Overtime")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(days <= 1 ? .red : .secondary)
                        }
                    }
                }
                .padding(DesignTokens.Spacing.cardPadding)
                .flCard(tint: TabAccent.rivalries.color)
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)

                // Actions
                if rivalry.status == .active {
                    HStack(spacing: 12) {
                        Button {
                            showingLogProgress = true
                        } label: {
                            Label("Log Progress", systemImage: "plus.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.flPrimary(tint: TabAccent.rivalries.color))

                        if rivalry.challengeType == .steps {
                            Button {
                                syncFromHealth()
                            } label: {
                                if isSyncingHealth {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                } else {
                                    Label("Sync Health", systemImage: "heart.fill")
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .buttonStyle(.flSecondary)
                            .disabled(isSyncingHealth)
                        }
                    }
                    .padding(.horizontal)

                    if isExpired {
                        Button {
                            completeRivalry()
                        } label: {
                            Text("Finalize Results")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.flPrimary(tint: .green))
                        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                    }
                }

                // Entry log
                if !entries.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Activity Log")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(entries) { entry in
                            EntryRow(entry: entry, rivalry: rivalry)
                                .padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .navigationTitle(rivalry.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingLogProgress) {
            LogProgressView(rivalry: rivalry, memberID: currentUserID, memberName: currentUserName)
        }
        .overlay {
            if showingWinOverlay {
                WinOverlay(rivalry: rivalry, initiatorTotal: initiatorTotal, opponentTotal: opponentTotal) {
                    showingWinOverlay = false
                }
            }
        }
    }

    private var challengeColor: Color {
        switch rivalry.challengeType {
        case .steps: .blue
        case .workout: .orange
        case .habit: .green
        case .custom: .purple
        }
    }

    private func syncFromHealth() {
        isSyncingHealth = true
        Task {
            let authorized = await healthKitManager.requestStepAuthorization()
            guard authorized else {
                isSyncingHealth = false
                return
            }

            let steps = await healthKitManager.fetchSteps(from: rivalry.startDate, to: rivalry.endDate)
            // Remove existing verified entries for current user, replace with fresh total
            let myVerifiedEntries = entries.filter { $0.memberID == currentUserID && $0.isVerified }
            for entry in myVerifiedEntries {
                modelContext.delete(entry)
            }
            // Subtract manual entries to get HealthKit-only value
            let manualTotal = entries.filter { $0.memberID == currentUserID && !$0.isVerified }.reduce(0) { $0 + $1.value }
            let healthOnlySteps = max(0, steps - manualTotal)

            if healthOnlySteps > 0 {
                let entry = RivalryEntry(
                    rivalryID: rivalry.id,
                    memberID: currentUserID,
                    memberName: currentUserName,
                    value: healthOnlySteps,
                    note: "Synced from Apple Health",
                    isVerified: true
                )
                modelContext.insert(entry)
            }
            isSyncingHealth = false
        }
    }

    private func completeRivalry() {
        rivalry.status = .completed

        // Determine winner
        if initiatorTotal > opponentTotal {
            rivalry.winnerID = rivalry.initiatorID
            awardPoints(to: rivalry.initiatorID, name: rivalry.initiatorName, points: rivalry.pointValue)
        } else if opponentTotal > initiatorTotal {
            rivalry.winnerID = rivalry.opponentID
            awardPoints(to: rivalry.opponentID, name: rivalry.opponentName, points: rivalry.pointValue)
        } else {
            // Tie — split points
            let half = rivalry.pointValue / 2
            awardPoints(to: rivalry.initiatorID, name: rivalry.initiatorName, points: half)
            awardPoints(to: rivalry.opponentID, name: rivalry.opponentName, points: half)
        }

        // Mark both as completed
        incrementCompleted(for: rivalry.initiatorID, name: rivalry.initiatorName)
        incrementCompleted(for: rivalry.opponentID, name: rivalry.opponentName)

        showingWinOverlay = true
    }

    private func awardPoints(to memberID: UUID, name: String, points: Int) {
        let descriptor = FetchDescriptor<FamilyMemberPoints>(
            predicate: #Predicate { $0.memberID == memberID }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.totalPoints += points
            existing.rivalriesWon += 1
            existing.lastUpdated = Date()
        } else {
            let new = FamilyMemberPoints(memberID: memberID, memberName: name)
            new.totalPoints = points
            new.rivalriesWon = 1
            modelContext.insert(new)
        }
    }

    private func incrementCompleted(for memberID: UUID, name: String) {
        let descriptor = FetchDescriptor<FamilyMemberPoints>(
            predicate: #Predicate { $0.memberID == memberID }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.rivalriesCompleted += 1
            existing.lastUpdated = Date()
        } else {
            let new = FamilyMemberPoints(memberID: memberID, memberName: name)
            new.rivalriesCompleted = 1
            modelContext.insert(new)
        }
    }
}

// MARK: - Subviews

struct PlayerColumn: View {
    let name: String
    let value: Double
    let color: Color
    let isLeading: Bool

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "person.circle.fill")
                .font(.title)
                .foregroundStyle(color)
            Text(name)
                .font(.subheadline.weight(.medium))
            Text("\(Int(value))")
                .font(.title.bold())
                .foregroundStyle(isLeading ? color : .primary)
            if isLeading {
                Image(systemName: "crown.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct ProgressRow: View {
    let name: String
    let value: Double
    let maxValue: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.fill.tertiary)
                RoundedRectangle(cornerRadius: 4)
                    .fill(color)
                    .frame(width: maxValue > 0 ? geo.size.width * (value / maxValue) : 0)
            }
        }
        .frame(height: 6)
    }
}

struct EntryRow: View {
    let entry: RivalryEntry
    let rivalry: Rivalry

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(entry.memberID == rivalry.initiatorID ? .teal : .orange)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.memberName)
                        .font(.subheadline.weight(.medium))
                    Text("+\(Int(entry.value))")
                        .font(.subheadline.bold())
                        .foregroundStyle(.teal)
                    if entry.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
                if let note = entry.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(entry.loggedAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(DesignTokens.Spacing.inset)
        .background(.fill.tertiary)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Spacing.inset))
    }
}

// MARK: - Win Overlay

struct WinOverlay: View {
    let rivalry: Rivalry
    let initiatorTotal: Double
    let opponentTotal: Double
    let onDismiss: () -> Void

    private var winnerName: String {
        if initiatorTotal > opponentTotal { return rivalry.initiatorName }
        if opponentTotal > initiatorTotal { return rivalry.opponentName }
        return "It's a tie!"
    }

    private var isTie: Bool { initiatorTotal == opponentTotal }

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.yellow)

                if isTie {
                    Text("It's a Tie!")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                    Text("\(rivalry.pointValue / 2) points each")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.8))
                } else {
                    Text("\(winnerName) Wins!")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                    Text("+\(rivalry.pointValue) points")
                        .font(.title3)
                        .foregroundStyle(.yellow)
                }

                Text("\(Int(initiatorTotal)) - \(Int(opponentTotal))")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.7))

                Button {
                    onDismiss()
                } label: {
                    Text("Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.white)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, DesignTokens.Spacing.large)
                .padding(.top, DesignTokens.Spacing.inset)
            }
        }
        .transition(.opacity)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Rivalry.self, RivalryEntry.self, FamilyMemberPoints.self, configurations: config)
    let rivalry = Rivalry(
        title: "Step Battle",
        challengeType: .steps,
        initiatorID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        initiatorName: "Jesse",
        opponentID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        opponentName: "Sophie",
        endDate: Date().addingTimeInterval(7 * 86400),
        pointValue: 100
    )
    container.mainContext.insert(rivalry)

    return NavigationStack {
        RivalryDetailView(rivalry: rivalry)
    }
    .modelContainer(container)
}
