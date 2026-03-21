import SwiftUI
import SwiftData

struct RivalriesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Rivalry.createdAt, order: .reverse)
    private var allRivalries: [Rivalry]

    @Query private var allEntries: [RivalryEntry]
    @Query private var allPoints: [FamilyMemberPoints]

    private var activeRivalries: [Rivalry] {
        allRivalries.filter { $0.status == .active || $0.status == .pending }
    }

    private var completedRivalries: [Rivalry] {
        allRivalries.filter { $0.status == .completed || $0.status == .declined }
    }

    @State private var showingStartRivalry = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // Leaderboard
                if !allPoints.isEmpty {
                    LeaderboardCard(points: allPoints)
                }

                // Active rivalries
                if !activeRivalries.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Active Rivalries")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(activeRivalries) { rivalry in
                            NavigationLink {
                                RivalryDetailView(rivalry: rivalry)
                            } label: {
                                RivalryCard(rivalry: rivalry, entries: allEntries)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal)
                        }
                    }
                }

                // Completed rivalries
                if !completedRivalries.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Completed")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(completedRivalries.prefix(10)) { rivalry in
                            NavigationLink {
                                RivalryDetailView(rivalry: rivalry)
                            } label: {
                                RivalryCard(rivalry: rivalry, entries: allEntries)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal)
                        }
                    }
                }

                // Empty state
                if activeRivalries.isEmpty && completedRivalries.isEmpty {
                    ContentUnavailableView {
                        Label("No Rivalries Yet", systemImage: "flag.2.crossed.fill")
                    } description: {
                        Text("Challenge a family member to a head-to-head competition!")
                    } actions: {
                        Button("Start a Rivalry") {
                            showingStartRivalry = true
                        }
                        .buttonStyle(.flPrimary(tint: TabAccent.rivalries.color))
                    }
                    .padding(.top, 40)
                }
            }
            .padding(.vertical)
        }
        .background { AmbientBackground(style: .rivalries) }
        .navigationTitle("Rivalries")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingStartRivalry = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingStartRivalry) {
            StartRivalryView()
        }
    }
}

// MARK: - Rivalry Card

struct RivalryCard: View {
    let rivalry: Rivalry
    let entries: [RivalryEntry]

    private var initiatorTotal: Double {
        entries.filter { $0.rivalryID == rivalry.id && $0.memberID == rivalry.initiatorID }.reduce(0) { $0 + $1.value }
    }

    private var opponentTotal: Double {
        entries.filter { $0.rivalryID == rivalry.id && $0.memberID == rivalry.opponentID }.reduce(0) { $0 + $1.value }
    }

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: rivalry.challengeType.icon)
                    .foregroundStyle(challengeColor)
                Text(rivalry.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                StatusBadge(status: rivalry.status)
            }

            // Competitors
            HStack {
                CompetitorScore(name: rivalry.initiatorName, value: initiatorTotal, isLeading: initiatorTotal >= opponentTotal)
                Spacer()
                Text("vs")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                CompetitorScore(name: rivalry.opponentName, value: opponentTotal, isLeading: opponentTotal >= initiatorTotal, trailing: true)
            }

            // Progress bars
            GeometryReader { geo in
                let total = max(initiatorTotal + opponentTotal, 1)
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.teal)
                        .frame(width: geo.size.width * (initiatorTotal / total))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.orange)
                        .frame(width: geo.size.width * (opponentTotal / total))
                }
            }
            .frame(height: 8)

            // Footer
            HStack {
                Label("\(rivalry.pointValue) pts", systemImage: "trophy.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(daysRemaining)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .flCard(tint: TabAccent.rivalries.color)
    }

    private var challengeColor: Color {
        switch rivalry.challengeType {
        case .steps: .blue
        case .workout: .orange
        case .habit: .green
        case .custom: .purple
        }
    }

    private var daysRemaining: String {
        if rivalry.status == .completed { return "Completed" }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: rivalry.endDate).day ?? 0
        if days < 0 { return "Ended" }
        if days == 0 { return "Last day!" }
        return "\(days)d left"
    }
}

struct CompetitorScore: View {
    let name: String
    let value: Double
    let isLeading: Bool
    var trailing: Bool = false

    var body: some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 2) {
            Text(name)
                .font(.caption.weight(.medium))
            Text("\(Int(value))")
                .font(.title3.bold())
                .foregroundStyle(isLeading ? .teal : .primary)
        }
    }
}

struct StatusBadge: View {
    let status: RivalryStatus

    var body: some View {
        Text(status.rawValue.capitalized)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(statusColor.opacity(0.15))
            .foregroundStyle(statusColor)
            .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch status {
        case .pending: .yellow
        case .active: .green
        case .completed: .blue
        case .declined: .red
        }
    }
}

#Preview {
    NavigationStack {
        RivalriesView()
    }
    .modelContainer(for: [Rivalry.self, RivalryEntry.self, FamilyMemberPoints.self])
}
