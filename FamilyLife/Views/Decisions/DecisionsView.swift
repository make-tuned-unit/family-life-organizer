import SwiftUI

struct DecisionsView: View {
    var showsDismissButton = false

    @Environment(\.dismiss) private var dismiss
    @Environment(APIService.self) private var api

    @State private var decisions: [DecisionResponse] = []
    @State private var showingNewDecision = false
    @State private var filterType: DecisionType?
    @State private var error: String?
    @State private var isLoading = false

    private var activeDecisions: [DecisionResponse] {
        let now = Date()
        return decisions.filter { decision in
            guard decision.status == DecisionStatus.active.rawValue else { return false }
            // Filter out decisions past their expiry
            if let expiresStr = decision.expires_at,
               let expiresDate = ISO8601DateFormatter.flexible.date(from: expiresStr),
               expiresDate < now {
                return false
            }
            return true
        }
    }

    private var resolvedDecisions: [DecisionResponse] {
        let now = Date()
        return decisions.filter { decision in
            decision.status == DecisionStatus.resolved.rawValue
            || decision.status == DecisionStatus.expired.rawValue
            || (decision.status == DecisionStatus.active.rawValue
                && decision.expires_at.flatMap { ISO8601DateFormatter.flexible.date(from: $0) }.map { $0 < now } == true)
        }
    }

    private var filteredActive: [DecisionResponse] {
        guard let filterType else { return activeDecisions }
        return activeDecisions.filter { $0.decision_type == filterType.rawValue }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                headerSection
                filterChips
                askAIBanner
                activeList
                resolvedList
            }
            .padding(.bottom, DesignTokens.Spacing.bottomBuffer)
        }
        .background { AmbientBackground(style: .decisions) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .toolbar {
            if showsDismissButton {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(WarmPalette.ink2)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                GlassIconButton(systemName: "plus") {
                    showingNewDecision = true
                }
            }
        }
        .sheet(isPresented: $showingNewDecision) {
            NewDecisionView { await loadDecisions() }
        }
        .refreshable { await loadDecisions() }
        .overlay {
            if isLoading && decisions.isEmpty { ProgressView() }
        }
        .alert("Couldn't load decisions", isPresented: errorAlertIsPresented) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "An unexpected error occurred.")
        }
        .task { await loadDecisions() }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(activeDecisions.count) ACTIVE")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WarmPalette.ink3)
                    .tracking(0.4)
                Text("Decisions")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(WarmPalette.ink1)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                WarmChip(label: "All", isActive: filterType == nil) {
                    filterType = nil
                }
                ForEach(DecisionType.allCases) { type in
                    WarmChip(label: type.displayName, isActive: filterType == type) {
                        filterType = filterType == type ? nil : type
                    }
                }
            }
            .padding(.horizontal, 22)
        }
        .padding(.bottom, 14)
    }

    // MARK: - Ask AI Banner

    private var askAIBanner: some View {
        Button { showingNewDecision = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(TabAccent.decisions.color)
                    .frame(width: 36, height: 36)
                    .background(TabAccent.decisions.color.opacity(0.15))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("What's for dinner?")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WarmPalette.ink1)
                    Text("Post a recipe idea or ask AI for suggestions")
                        .font(.system(size: 13))
                        .foregroundStyle(WarmPalette.ink3)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WarmPalette.ink4)
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
        .padding(.bottom, 14)
    }

    // MARK: - Active Decisions

    @ViewBuilder
    private var activeList: some View {
        if filteredActive.isEmpty && resolvedDecisions.isEmpty && !isLoading {
            WarmEmptyState(
                title: "No decisions yet",
                systemImage: "bubble.left.and.bubble.right.fill",
                description: "Share something with your family for input"
            )
        } else {
            ForEach(filteredActive) { decision in
                NavigationLink {
                    DecisionDetailView(decision: decision)
                } label: {
                    DecisionCard(decision: decision)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                .padding(.bottom, 10)
            }
        }
    }

    // MARK: - Resolved

    @ViewBuilder
    private var resolvedList: some View {
        if !resolvedDecisions.isEmpty {
            WarmSectionHeader(title: "Resolved")
                .padding(.top, 8)
                .padding(.bottom, 8)

            ForEach(resolvedDecisions.prefix(5)) { decision in
                NavigationLink {
                    DecisionDetailView(decision: decision)
                } label: {
                    DecisionCard(decision: decision)
                }
                .buttonStyle(.plain)
                .opacity(0.6)
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                .padding(.bottom, 10)
            }
        }
    }

    private func loadDecisions() async {
        isLoading = true
        error = nil
        do {
            decisions = try await api.fetchDecisions()
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private var errorAlertIsPresented: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    }
}

// MARK: - Decision Card (warm glass)

struct DecisionCard: View {
    @Environment(APIService.self) private var api
    let decision: DecisionResponse

    @State private var reactions: [DecisionReactionResponse] = []
    @State private var comments: [DecisionCommentResponse] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Meta row
            HStack(spacing: 8) {
                Image(systemName: decision.decisionType.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(TabAccent.decisions.color)
                Text(decision.creator_name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WarmPalette.ink1)
                if let createdAt = decision.relativeCreatedAtText {
                    Text(createdAt)
                        .font(.system(size: 11))
                        .foregroundStyle(WarmPalette.ink3)
                }
                Spacer()
                if decision.status == DecisionStatus.resolved.rawValue {
                    Text("Resolved")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WarmPalette.good)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(WarmPalette.good.opacity(0.15), in: Capsule())
                }
            }

            // Title
            Text(decision.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WarmPalette.ink1)
                .multilineTextAlignment(.leading)

            // Body
            if let body = decision.body, !body.isEmpty {
                Text(body)
                    .font(.system(size: 13))
                    .foregroundStyle(WarmPalette.ink2)
                    .lineLimit(2)
            }

            // Link
            if let url = decision.link_url, !url.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                    Text(url)
                        .lineLimit(1)
                }
                .font(.system(size: 13))
                .foregroundStyle(AccentTheme.ocean.color)
            }

            // Poll
            if decision.decisionType == .poll && !decision.poll_options.isEmpty {
                VStack(spacing: 4) {
                    ForEach(Array(decision.poll_options.enumerated()), id: \.offset) { idx, option in
                        let voteCount = reactions.filter { $0.poll_choice == idx }.count
                        PollOptionRow(option: option, votes: voteCount, totalVotes: reactions.filter { $0.reaction_type == "vote" }.count)
                    }
                }
            }

            // Reactions footer
            HStack(spacing: 12) {
                let thumbsUp = reactions.filter { $0.reaction_type == "thumbsUp" }.count
                let thumbsDown = reactions.filter { $0.reaction_type == "thumbsDown" }.count
                let hearts = reactions.filter { $0.reaction_type == "heart" }.count

                if thumbsUp > 0 { Label("\(thumbsUp)", systemImage: "hand.thumbsup.fill").font(.system(size: 11)) }
                if thumbsDown > 0 { Label("\(thumbsDown)", systemImage: "hand.thumbsdown.fill").font(.system(size: 11)) }
                if hearts > 0 { Label("\(hearts)", systemImage: "heart.fill").font(.system(size: 11)).foregroundStyle(AccentTheme.rose.color) }

                Spacer()

                if !comments.isEmpty {
                    Label("\(comments.count)", systemImage: "bubble.left.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(WarmPalette.ink3)
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .task { await loadMeta() }
    }

    private func loadMeta() async {
        do {
            async let fetchedReactions = api.fetchDecisionReactions(id: decision.id)
            async let fetchedComments = api.fetchDecisionComments(id: decision.id)
            reactions = try await fetchedReactions
            comments = try await fetchedComments
        } catch {}
    }
}

// MARK: - Extensions (unchanged)

extension DecisionResponse {
    var decisionType: DecisionType {
        DecisionType(rawValue: decision_type) ?? .text
    }

    var relativeCreatedAtText: String? {
        guard let created_at, let date = ISO8601DateFormatter.flexible.date(from: created_at) else { return nil }
        return date.formatted(.relative(presentation: .named))
    }

    var createdDate: Date? {
        guard let created_at else { return nil }
        return ISO8601DateFormatter.flexible.date(from: created_at)
    }
}

extension DecisionCommentResponse {
    var createdDate: Date? {
        guard let created_at else { return nil }
        return ISO8601DateFormatter.flexible.date(from: created_at)
    }
}

struct PollOptionRow: View {
    let option: String
    let votes: Int
    let totalVotes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(option)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WarmPalette.ink1)
                Spacer()
                Text("\(votes)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WarmPalette.ink3)
            }
            WarmProgressBar(progress: fillFraction, color: TabAccent.decisions.color, height: 6)
        }
        .padding(.vertical, 2)
    }

    private var fillFraction: Double {
        guard totalVotes > 0 else { return 0 }
        return Double(votes) / Double(totalVotes)
    }
}

struct ReactionButton: View {
    let emoji: String
    let type: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: emoji)
                    .font(.system(size: 14, weight: .semibold))
                Text("\(count)")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(isSelected ? WarmPalette.cream1 : TabAccent.decisions.color)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isSelected ? TabAccent.decisions.color : TabAccent.decisions.color.opacity(0.12))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        DecisionsView()
            .environment(APIService())
    }
}
