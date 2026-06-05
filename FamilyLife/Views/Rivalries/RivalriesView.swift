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
                                RivalryDetailView(rivalry: rivalry)
                            } label: {
                                RivalryCardRemote(rivalry: rivalry, entries: entriesByRivalry[rivalry.id] ?? [])
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal)
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
                                RivalryDetailView(rivalry: rivalry)
                            } label: {
                                RivalryCardRemote(rivalry: rivalry, entries: entriesByRivalry[rivalry.id] ?? [])
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal)
                        }
                    }
                }

                if activeRivalries.isEmpty && completedRivalries.isEmpty && !isLoading {
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
        .alert("Couldn’t load rivalries", isPresented: errorAlertIsPresented) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "An unexpected error occurred.")
        }
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
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private var errorAlertIsPresented: Binding<Bool> {
        Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )
    }
}

struct RivalryCardRemote: View {
    let rivalry: RivalryResponse
    let entries: [RivalryEntryResponse]

    private var initiatorTotal: Double {
        entries.filter { $0.member_name.localizedCaseInsensitiveCompare(rivalry.initiator_name) == .orderedSame }.reduce(0) { $0 + $1.value }
    }

    private var opponentTotal: Double {
        entries.filter { $0.member_name.localizedCaseInsensitiveCompare(rivalry.opponent_name) == .orderedSame }.reduce(0) { $0 + $1.value }
    }

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
                CompetitorScore(name: rivalry.initiator_name, value: initiatorTotal, isLeading: initiatorTotal >= opponentTotal)
                Spacer()
                Text("vs")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WarmPalette.ink3)
                Spacer()
                CompetitorScore(name: rivalry.opponent_name, value: opponentTotal, isLeading: opponentTotal >= initiatorTotal, trailing: true)
            }

            GeometryReader { geo in
                let total = max(initiatorTotal + opponentTotal, 1)
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(TabAccent.home.color)
                        .frame(width: geo.size.width * (initiatorTotal / total))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AccentTheme.saffron.color)
                        .frame(width: geo.size.width * (opponentTotal / total))
                }
            }
            .frame(height: 8)

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
        case .declined: .secondary
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
                .foregroundStyle(isLeading ? .primary : .secondary)
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
                .foregroundStyle(isLeading ? .green : .secondary)
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
