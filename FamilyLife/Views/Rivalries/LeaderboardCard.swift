import SwiftUI
import SwiftData

struct LeaderboardCard: View {
    let points: [FamilyMemberPoints]
    @State private var showingMemberStats: FamilyMemberPoints?

    private var ranked: [FamilyMemberPoints] {
        points.sorted { $0.totalPoints > $1.totalPoints }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(.yellow)
                Text("Family Leaderboard")
                    .font(.headline)
            }
            .padding(.horizontal)

            ForEach(Array(ranked.enumerated()), id: \.element.id) { index, member in
                Button {
                    showingMemberStats = member
                } label: {
                    HStack(spacing: 12) {
                        // Rank
                        Text("\(index + 1)")
                            .font(.subheadline.bold())
                            .frame(width: 24)
                            .foregroundStyle(rankColor(index))

                        // Medal for top 3
                        if index < 3 {
                            Image(systemName: medalIcon(index))
                                .foregroundStyle(rankColor(index))
                                .frame(width: 20)
                        }

                        // Name
                        Text(member.memberName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)

                        Spacer()

                        // Stats
                        HStack(spacing: 8) {
                            Label("\(member.rivalriesWon)W", systemImage: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(member.totalPoints) pts")
                                .font(.subheadline.bold())
                                .foregroundStyle(.teal)
                        }
                    }
                    .padding(.vertical, DesignTokens.Spacing.rowVertical)
                    .padding(.horizontal, DesignTokens.Spacing.cardGap)
                }
                .buttonStyle(.plain)

                if index < ranked.count - 1 {
                    Divider().padding(.horizontal)
                }
            }
        }
        .padding(.vertical, DesignTokens.Spacing.cardGap)
        .padding(.horizontal, DesignTokens.Spacing.cardPadding)
        .flCard(tint: TabAccent.rivalries.color)
        .sheet(item: $showingMemberStats) { member in
            MemberStatsSheet(member: member)
        }
    }

    private func rankColor(_ index: Int) -> Color {
        switch index {
        case 0: .yellow
        case 1: .gray
        case 2: .brown
        default: .secondary
        }
    }

    private func medalIcon(_ index: Int) -> String {
        switch index {
        case 0: "medal.fill"
        case 1: "medal.fill"
        case 2: "medal.fill"
        default: "circle"
        }
    }
}

struct MemberStatsSheet: View {
    let member: FamilyMemberPoints

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.teal)
                        VStack(alignment: .leading) {
                            Text(member.memberName)
                                .font(.title2.bold())
                            Text("Family competitor")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Stats") {
                    StatRow(label: "Total Points", value: "\(member.totalPoints)", icon: "trophy.fill", color: .yellow)
                    StatRow(label: "Rivalries Won", value: "\(member.rivalriesWon)", icon: "star.fill", color: .teal)
                    StatRow(label: "Rivalries Completed", value: "\(member.rivalriesCompleted)", icon: "checkmark.circle.fill", color: .green)
                }
            }
            .navigationTitle("Stats")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}

struct StatRow: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            Text(label)
            Spacer()
            Text(value)
                .font(.headline)
        }
    }
}

#Preview {
    let p1 = FamilyMemberPoints(memberID: UUID(), memberName: "Jesse")
    p1.totalPoints = 350
    p1.rivalriesWon = 3
    p1.rivalriesCompleted = 5

    let p2 = FamilyMemberPoints(memberID: UUID(), memberName: "Sophie")
    p2.totalPoints = 280
    p2.rivalriesWon = 2
    p2.rivalriesCompleted = 4

    return LeaderboardCard(points: [p1, p2])
}
