import SwiftUI

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
                    .foregroundStyle(AccentTheme.saffron.color)
                Text("Family Leaderboard")
                    .font(.flHeadline)
            }
            .padding(.horizontal)

            ForEach(Array(ranked.enumerated()), id: \.element.id) { index, member in
                Button {
                    showingMemberStats = member
                } label: {
                    HStack(spacing: 12) {
                        // Rank
                        Text("\(index + 1)")
                            .font(.flSubheadline.bold())
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
                            .font(.flSubheadline.weight(.medium))
                            .foregroundStyle(.primary)

                        Spacer()

                        // Stats
                        HStack(spacing: 8) {
                            Label("\(member.rivalriesWon)W", systemImage: "star.fill")
                                .font(.flCaption2)
                                .foregroundStyle(WarmPalette.ink3)
                            Text("\(member.totalPoints) pts")
                                .font(.flSubheadline.bold())
                                .foregroundStyle(TabAccent.home.color)
                                .contentTransition(.numericText())
                                .animation(.snappy, value: member.totalPoints)
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
        case 0: AccentTheme.saffron.color
        case 1: WarmPalette.ink3
        case 2: WarmPalette.ink2
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
                        FamilyAvatar(initial: String(member.memberName.prefix(1)).uppercased(), size: 40, name: member.memberName)
                        VStack(alignment: .leading) {
                            Text(member.memberName)
                                .font(.flTitle)
                            Text("Family competitor")
                                .font(.flCaption)
                                .foregroundStyle(WarmPalette.ink3)
                        }
                    }
                }

                Section("Stats") {
                    StatRow(label: "Total Points", value: "\(member.totalPoints)", icon: "trophy.fill", color: AccentTheme.saffron.color)
                    StatRow(label: "Rivalries Won", value: "\(member.rivalriesWon)", icon: "star.fill", color: TabAccent.home.color)
                    StatRow(label: "Rivalries Completed", value: "\(member.rivalriesCompleted)", icon: "checkmark.circle.fill", color: WarmPalette.good)
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground(style: .rivalries) }
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
                .font(.flHeadline)
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
