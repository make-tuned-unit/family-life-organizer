import SwiftUI

struct RivalriesView: View {
    var showsDismissButton = false

    @Environment(\.dismiss) private var dismiss
    @Environment(APIService.self) private var api
    @Environment(AuthService.self) private var auth

    @State private var rivalries: [RivalryResponse] = []
    @State private var leaderboard: [RivalryLeaderboardResponse] = []
    @State private var entriesByRivalry: [Int: [RivalryEntryResponse]] = [:]
    @State private var showingStartRivalry = false
    @State private var isLoading = false
    @State private var error: String?

    private var activeRivalries: [RivalryResponse] {
        let now = Date()
        return rivalries.filter { rivalry in
            guard rivalry.status == RivalryStatus.active.rawValue || rivalry.status == RivalryStatus.pending.rawValue else { return false }
            // Filter out rivalries past their end date
            if let end = rivalry.endDate, end < now { return false }
            return true
        }
    }

    private var completedRivalries: [RivalryResponse] {
        let now = Date()
        return rivalries.filter { rivalry in
            rivalry.status == RivalryStatus.completed.rawValue
            || rivalry.status == RivalryStatus.declined.rawValue
            || (rivalry.endDate.map { $0 < now } == true)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                if !leaderboard.isEmpty {
                    LeaderboardCardRemote(points: leaderboard)
                }

                if !activeRivalries.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Active Rivalries")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(activeRivalries) { rivalry in
                            NavigationLink {
                                RivalryDetailView(rivalry: rivalry) { await loadAll() }
                            } label: {
                                RivalryCardRemote(rivalry: rivalry, entries: entriesByRivalry[rivalry.id] ?? [])
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal)
                            .contextMenu {
                                Button(role: .destructive) {
                                    Task { await deleteRivalry(rivalry) }
                                } label: { Label("Delete Challenge", systemImage: "trash") }
                            }
                        }
                    }
                }

                if !completedRivalries.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Completed")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(completedRivalries.prefix(10)) { rivalry in
                            NavigationLink {
                                RivalryDetailView(rivalry: rivalry) { await loadAll() }
                            } label: {
                                RivalryCardRemote(rivalry: rivalry, entries: entriesByRivalry[rivalry.id] ?? [])
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal)
                            .contextMenu {
                                Button(role: .destructive) {
                                    Task { await deleteRivalry(rivalry) }
                                } label: { Label("Delete Challenge", systemImage: "trash") }
                            }
                        }
                    }
                }

                if activeRivalries.isEmpty && completedRivalries.isEmpty && !isLoading {
                    VStack(spacing: 16) {
                        WarmEmptyState(
                            title: "No Rivalries Yet",
                            systemImage: "flag.2.crossed.fill",
                            description: "Challenge a family member to a head-to-head competition!"
                        )
                        Button("Start a Rivalry") {
                            showingStartRivalry = true
                        }
                        .buttonStyle(.flPrimary(tint: TabAccent.rivalries.color))
                    }
                    .padding(.top, DesignTokens.Spacing.large)
                }
            }
            .padding(.vertical)
        }
        .background { AmbientBackground(style: .rivalries) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .toolbar {
            if showsDismissButton {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingStartRivalry = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Start a rivalry")
            }
        }
        .sheet(isPresented: $showingStartRivalry) {
            StartRivalryView {
                await loadAll()
            }
        }
        .refreshable {
            await loadAll()
        }
        .overlay {
            if isLoading && rivalries.isEmpty {
                ProgressView()
            }
        }
        .inlineError(error) { error = nil }
        .task {
            await loadAll()
        }
    }

    private func loadAll() async {
        isLoading = true
        error = nil
        do {
            let fetchedRivalries = try await api.fetchRivalries()
            rivalries = fetchedRivalries
            leaderboard = try await api.fetchRivalryLeaderboard()
            // Cache current user's XP for level-up detection
            if let myName = auth.currentUser?.name,
               let myEntry = leaderboard.first(where: { $0.member_name.localizedCaseInsensitiveCompare(myName) == .orderedSame }) {
                UserDefaults.standard.set(myEntry.total_points, forKey: "rivalry_xp")
            }
            var nextEntries: [Int: [RivalryEntryResponse]] = [:]
            for rivalry in fetchedRivalries {
                nextEntries[rivalry.id] = try await api.fetchRivalryEntries(id: rivalry.id)
            }
            entriesByRivalry = nextEntries

            // Schedule local milestone notifications for active rivalries
            if let myName = auth.currentUser?.name {
                NotificationService.shared.scheduleRivalryMilestones(fetchedRivalries, myName: myName, myUsername: auth.currentUser?.username ?? "", entriesByRivalry: nextEntries)
            }
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func deleteRivalry(_ rivalry: RivalryResponse) async {
        do {
            try await api.deleteRivalry(id: rivalry.id)
            await loadAll()
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }

}

struct RivalryCardRemote: View {
    let rivalry: RivalryResponse
    let entries: [RivalryEntryResponse]

    private func total(for name: String) -> Double {
        entries.filter { rivalryNameMatches($0.member_name, name) }.reduce(0) { $0 + $1.value }
    }

    private func teamLabel(_ names: [String]) -> String {
        if names.count <= 1 { return names.first ?? "Team" }
        if names.count == 2 { return names.joined(separator: " & ") }
        return "\(names.first ?? "Team") +\(names.count - 1)"
    }

    // Left/right sides unify individual (initiator vs opponent) and team modes.
    private var leftTotal: Double { rivalry.isTeam ? rivalry.teamANames.reduce(0) { $0 + total(for: $1) } : total(for: rivalry.initiator_name) }
    private var rightTotal: Double { rivalry.isTeam ? rivalry.teamBNames.reduce(0) { $0 + total(for: $1) } : total(for: rivalry.opponent_name) }
    private var leftName: String { rivalry.isTeam ? teamLabel(rivalry.teamANames) : rivalry.initiator_name }
    private var rightName: String { rivalry.isTeam ? teamLabel(rivalry.teamBNames) : rivalry.opponent_name }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: rivalry.challengeType.icon)
                    .foregroundStyle(challengeColor)
                Text(rivalry.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                StatusBadge(status: rivalry.statusValue)
            }

            HStack {
                CompetitorScore(name: leftName, value: leftTotal, isLeading: leftTotal >= rightTotal)
                Spacer()
                Text("vs")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WarmPalette.ink3)
                Spacer()
                CompetitorScore(name: rightName, value: rightTotal, isLeading: rightTotal >= leftTotal, trailing: true)
            }

            GeometryReader { geo in
                let total = max(leftTotal + rightTotal, 1)
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(TabAccent.home.color)
                        .frame(width: geo.size.width * (leftTotal / total))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AccentTheme.saffron.color)
                        .frame(width: geo.size.width * (rightTotal / total))
                }
            }
            .frame(height: 8)

            if rivalry.isTeam {
                Text("Team challenge")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(TabAccent.rivalries.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Label("\(rivalry.point_value) pts", systemImage: "trophy.fill")
                    .font(.caption2)
                    .foregroundStyle(WarmPalette.ink3)
                Spacer()
                Text(daysRemaining)
                    .font(.caption2)
                    .foregroundStyle(WarmPalette.ink3)
            }
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .flCard(tint: TabAccent.rivalries.color)
    }

    private var challengeColor: Color {
        switch rivalry.challengeType {
        case .steps, .stairs: AccentTheme.ocean.color
        case .workout, .pushups, .squats, .situps, .plank: AccentTheme.saffron.color
        case .running: AccentTheme.ocean.color
        case .habit: WarmPalette.good
        case .custom: AccentTheme.mauve.color
        }
    }

    private var daysRemaining: String {
        if rivalry.status == RivalryStatus.completed.rawValue { return "Completed" }
        guard let endDate = rivalry.endDate else { return "No end date" }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: endDate).day ?? 0
        if days < 0 { return "Ended" }
        if days == 0 { return "Last day!" }
        return "\(days)d left"
    }
}

struct LeaderboardCardRemote: View {
    let points: [RivalryLeaderboardResponse]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Leaderboard")
                .font(.headline)
                .padding(.horizontal)

            VStack(spacing: 10) {
                ForEach(Array(points.prefix(5).enumerated()), id: \.element.id) { index, member in
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(.subheadline.bold())
                            .foregroundStyle(index == 0 ? AccentTheme.saffron.color : WarmPalette.ink3)
                            .frame(width: 20)
                        Text(member.member_name)
                            .font(.subheadline.weight(.medium))
                        LevelBadge(xp: member.total_points, compact: true)
                        Spacer()
                        Text("\(member.total_points) pts")
                            .font(.subheadline.bold())
                            .foregroundStyle(TabAccent.home.color)
                    }
                }
            }
            .padding(DesignTokens.Spacing.cardPadding)
            .flCard(tint: TabAccent.rivalries.color)
            .padding(.horizontal)
        }
    }
}

extension RivalryResponse {
    var challengeType: ChallengeType {
        ChallengeType(rawValue: challenge_type) ?? .custom
    }

    var statusValue: RivalryStatus {
        RivalryStatus(rawValue: status) ?? .active
    }

    var endDate: Date? {
        ISO8601DateFormatter.flexible.date(from: end_date) ?? DateFormatter.isoDate.date(from: end_date)
    }
}

struct StatusBadge: View {
    let status: RivalryStatus

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.16))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var label: String {
        switch status {
        case .pending: "Pending"
        case .active: "Active"
        case .completed: "Completed"
        case .declined: "Declined"
        }
    }

    private var color: Color {
        switch status {
        case .pending: AccentTheme.saffron.color
        case .active: TabAccent.home.color
        case .completed: WarmPalette.good
        case .declined: WarmPalette.ink3
        }
    }
}

struct CompetitorScore: View {
    let name: String
    let value: Double
    let isLeading: Bool
    var trailing = false

    var body: some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 4) {
            Text(name)
                .font(.caption.weight(.medium))
                .foregroundStyle(WarmPalette.ink3)
            Text(valueText)
                .font(.title3.bold())
                .foregroundStyle(isLeading ? .primary : WarmPalette.ink3)
            if isLeading {
                Text("Leading")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WarmPalette.good)
            }
        }
    }

    private var valueText: String {
        if value.rounded(.towardZero) == value {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}

struct PlayerColumn: View {
    let name: String
    let value: Double
    let color: Color
    let isLeading: Bool

    var body: some View {
        VStack(spacing: 6) {
            Text(name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(WarmPalette.ink3)
            Text(valueText)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(isLeading ? "Ahead" : "Chasing")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isLeading ? WarmPalette.good : WarmPalette.ink3)
        }
        .frame(maxWidth: .infinity)
    }

    private var valueText: String {
        if value.rounded(.towardZero) == value {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}

struct ProgressRow: View {
    let name: String
    let value: Double
    let maxValue: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(WarmPalette.ink3)
                Spacer()
                Text(valueText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(WarmPalette.ink1.opacity(0.06))
                    RoundedRectangle(cornerRadius: 6)
                        .fill(color.opacity(0.85))
                        .frame(width: geo.size.width * fillFraction)
                }
            }
            .frame(height: 10)
        }
    }

    private var fillFraction: CGFloat {
        guard maxValue > 0 else { return 0 }
        return CGFloat(value / maxValue)
    }

    private var valueText: String {
        if value.rounded(.towardZero) == value {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}

#Preview {
    NavigationStack {
        RivalriesView()
            .environment(APIService())
            .environment(AuthService())
            .environment(HouseholdService())
    }
}
