import SwiftUI
import SwiftData

struct DecisionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Decision.createdAt, order: .reverse)
    private var allDecisions: [Decision]

    @State private var showingNewDecision = false
    @State private var filterType: DecisionType?

    private var activeDecisions: [Decision] {
        allDecisions.filter { $0.status == .active }
    }

    private var resolvedDecisions: [Decision] {
        allDecisions.filter { $0.status == .resolved || $0.status == .expired }
    }

    private var filteredActive: [Decision] {
        guard let filter = filterType else { return activeDecisions }
        return activeDecisions.filter { $0.decisionType == filter }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    GlassEffectContainer(spacing: 6) {
                        HStack(spacing: 6) {
                            FilterChip(label: "All", isSelected: filterType == nil, tint: TabAccent.decisions.color) {
                                filterType = nil
                            }
                            ForEach(DecisionType.allCases) { type in
                                FilterChip(label: type.displayName, icon: type.icon, isSelected: filterType == type, tint: TabAccent.decisions.color) {
                                    filterType = filterType == type ? nil : type
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                // Active decisions
                if filteredActive.isEmpty && resolvedDecisions.isEmpty {
                    ContentUnavailableView {
                        Label("No Decisions Yet", systemImage: "bubble.left.and.bubble.right.fill")
                    } description: {
                        Text("Share something with your family for input!")
                    } actions: {
                        Button("Share Something") {
                            showingNewDecision = true
                        }
                        .buttonStyle(.flPrimary(tint: TabAccent.decisions.color))
                    }
                    .padding(.top, DesignTokens.Spacing.large)
                }

                ForEach(filteredActive) { decision in
                    NavigationLink {
                        DecisionDetailView(decision: decision)
                    } label: {
                        DecisionCard(decision: decision)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                }

                // Resolved
                if !resolvedDecisions.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Resolved")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)

                        ForEach(resolvedDecisions.prefix(5)) { decision in
                            NavigationLink {
                                DecisionDetailView(decision: decision)
                            } label: {
                                DecisionCard(decision: decision)
                            }
                            .buttonStyle(.plain)
                            .opacity(0.6)
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .background { AmbientBackground(style: .decisions) }
        .navigationTitle("What do you think?")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingNewDecision = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewDecision) {
            NewDecisionView()
        }
    }
}

// MARK: - Decision Card

struct DecisionCard: View {
    let decision: Decision
    @Query private var allReactions: [DecisionReaction]
    @Query private var allComments: [DecisionComment]

    private var reactions: [DecisionReaction] {
        allReactions.filter { $0.decisionID == decision.id }
    }

    private var comments: [DecisionComment] {
        allComments.filter { $0.decisionID == decision.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Image(systemName: decision.decisionType.icon)
                    .foregroundStyle(.teal)
                Text(decision.creatorName)
                    .font(.caption.weight(.semibold))
                Text(decision.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if decision.status == .resolved {
                    Text("Resolved")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, DesignTokens.Spacing.chipVerticalMed)
                        .padding(.vertical, DesignTokens.Spacing.chipVerticalTight)
                        .background(BadgeSemantic.done.color.opacity(DesignTokens.Opacity.badgeFill)) // DS-05: replaced raw opacity fill
                        .foregroundStyle(.green)
                        .clipShape(Capsule())
                }
            }

            // Title
            Text(decision.title)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.leading)

            // Body preview
            if let body = decision.body, !body.isEmpty {
                Text(body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Link
            if let url = decision.linkURL, !url.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                    Text(url)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.blue)
            }

            // Poll options preview
            if decision.decisionType == .poll && !decision.pollOptions.isEmpty {
                VStack(spacing: 4) {
                    ForEach(Array(decision.pollOptions.enumerated()), id: \.offset) { idx, option in
                        let voteCount = reactions.filter { $0.pollChoice == idx }.count
                        PollOptionRow(option: option, votes: voteCount, totalVotes: reactions.filter { $0.reactionType == "vote" }.count)
                    }
                }
            }

            // Reactions + comments summary
            HStack(spacing: 12) {
                let thumbsUp = reactions.filter { $0.reactionType == "thumbsUp" }.count
                let thumbsDown = reactions.filter { $0.reactionType == "thumbsDown" }.count
                let hearts = reactions.filter { $0.reactionType == "heart" }.count

                if thumbsUp > 0 { Label("\(thumbsUp)", systemImage: "hand.thumbsup.fill").font(.caption2) }
                if thumbsDown > 0 { Label("\(thumbsDown)", systemImage: "hand.thumbsdown.fill").font(.caption2) }
                if hearts > 0 { Label("\(hearts)", systemImage: "heart.fill").font(.caption2).foregroundStyle(.red) }

                Spacer()

                if !comments.isEmpty {
                    Label("\(comments.count)", systemImage: "bubble.left.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .flCard(tint: TabAccent.decisions.color)
    }
}

struct PollOptionRow: View {
    let option: String
    let votes: Int
    let totalVotes: Int

    private var progress: Double {
        guard totalVotes > 0 else { return 0 }
        return Double(votes) / Double(totalVotes)
    }

    var body: some View {
        HStack {
            Text(option)
                .font(.caption)
            Spacer()
            Text("\(votes)")
                .font(.caption.bold())
        }
        .padding(.horizontal, DesignTokens.Spacing.chipPadding)
        .padding(.vertical, DesignTokens.Spacing.chipVerticalPadding)
        .background {
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 4)
                    .fill(TabAccent.decisions.color.opacity(DesignTokens.Opacity.badgeFill)) // DS-05: replaced raw opacity fill
                    .frame(width: geo.size.width * progress)
            }
        }
        .background(Color(.quaternarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

#Preview {
    NavigationStack {
        DecisionsView()
    }
    .modelContainer(for: [Decision.self, DecisionReaction.self, DecisionComment.self])
}
