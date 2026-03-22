import SwiftUI
import SwiftData

struct DecisionDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let decision: Decision

    @Query private var allReactions: [DecisionReaction]
    @Query private var allComments: [DecisionComment]

    @State private var newComment = ""
    @State private var showingResolved = false

    private let currentUser = "Jesse"

    private var reactions: [DecisionReaction] {
        allReactions.filter { $0.decisionID == decision.id }
    }

    private var comments: [DecisionComment] {
        allComments.filter { $0.decisionID == decision.id }.sorted { $0.createdAt < $1.createdAt }
    }

    private var myReaction: String? {
        reactions.first { $0.memberName == currentUser && $0.reactionType != "vote" }?.reactionType
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: decision.decisionType.icon)
                            .foregroundStyle(.teal)
                        Text(decision.creatorName)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(decision.createdAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(decision.title)
                        .font(.title3.bold())

                    if let body = decision.body, !body.isEmpty {
                        Text(body)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let url = decision.linkURL, !url.isEmpty {
                        Link(destination: URL(string: url) ?? URL(string: "https://example.com")!) {
                            HStack {
                                Image(systemName: "link")
                                Text(url)
                                    .lineLimit(1)
                            }
                            .font(.subheadline)
                            .padding(DesignTokens.Spacing.inset)
                            .background(TabAccent.decisions.color.opacity(DesignTokens.Opacity.cardTint)) // DS-05: replaced raw opacity fill
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding(.horizontal)

                // Poll
                if decision.decisionType == .poll && !decision.pollOptions.isEmpty {
                    VStack(spacing: 8) {
                        let totalVotes = reactions.filter { $0.reactionType == "vote" }.count
                        ForEach(Array(decision.pollOptions.enumerated()), id: \.offset) { idx, option in
                            let voteCount = reactions.filter { $0.pollChoice == idx }.count
                            let myVote = reactions.first { $0.memberName == currentUser && $0.reactionType == "vote" }?.pollChoice
                            Button {
                                vote(for: idx)
                            } label: {
                                HStack {
                                    Text(option)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text("\(voteCount)")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.teal)
                                    if myVote == idx {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.teal)
                                    }
                                }
                                .padding(DesignTokens.Spacing.cardGap)
                                .background {
                                    GeometryReader { geo in
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(TabAccent.decisions.color.opacity(DesignTokens.Opacity.cardTint)) // DS-05: replaced raw opacity fill
                                            .frame(width: totalVotes > 0 ? geo.size.width * Double(voteCount) / Double(totalVotes) : 0)
                                    }
                                }
                                .background(Color(.tertiarySystemFill))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .disabled(decision.status != .active)
                        }
                    }
                    .padding(.horizontal)
                }

                // Reactions
                if decision.decisionType != .poll {
                    HStack(spacing: 16) {
                        ReactionButton(emoji: "hand.thumbsup.fill", type: "thumbsUp", count: reactions.filter { $0.reactionType == "thumbsUp" }.count, isSelected: myReaction == "thumbsUp") {
                            react("thumbsUp")
                        }
                        ReactionButton(emoji: "hand.thumbsdown.fill", type: "thumbsDown", count: reactions.filter { $0.reactionType == "thumbsDown" }.count, isSelected: myReaction == "thumbsDown") {
                            react("thumbsDown")
                        }
                        ReactionButton(emoji: "heart.fill", type: "heart", count: reactions.filter { $0.reactionType == "heart" }.count, isSelected: myReaction == "heart") {
                            react("heart")
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                }

                Divider()

                // Comments
                VStack(alignment: .leading, spacing: 12) {
                    Text("Comments (\(comments.count))")
                        .font(.headline)
                        .padding(.horizontal)

                    ForEach(comments) { comment in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "person.circle.fill")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(comment.memberName)
                                        .font(.caption.weight(.semibold))
                                    Text(comment.createdAt, style: .relative)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                Text(comment.text)
                                    .font(.subheadline)
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Add comment
                    if decision.status == .active {
                        HStack {
                            TextField("Add a comment...", text: $newComment)
                                .textFieldStyle(.roundedBorder)
                            Button {
                                addComment()
                            } label: {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.teal)
                            }
                            .disabled(newComment.isEmpty)
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
        .navigationTitle(decision.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if decision.status == .active && decision.creatorName == currentUser {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Resolve") {
                        decision.status = .resolved
                    }
                }
            }
        }
    }

    private func react(_ type: String) {
        // Remove existing non-vote reaction from this user
        if let existing = reactions.first(where: { $0.memberName == currentUser && $0.reactionType != "vote" }) {
            modelContext.delete(existing)
            if existing.reactionType == type { return } // toggle off
        }
        let reaction = DecisionReaction(decisionID: decision.id, memberName: currentUser, reactionType: type)
        modelContext.insert(reaction)
    }

    private func vote(for option: Int) {
        // Remove existing vote
        if let existing = reactions.first(where: { $0.memberName == currentUser && $0.reactionType == "vote" }) {
            modelContext.delete(existing)
        }
        let reaction = DecisionReaction(decisionID: decision.id, memberName: currentUser, reactionType: "vote", pollChoice: option)
        modelContext.insert(reaction)
    }

    private func addComment() {
        let comment = DecisionComment(decisionID: decision.id, memberName: currentUser, text: newComment)
        modelContext.insert(comment)
        newComment = ""
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
            HStack(spacing: 4) {
                Image(systemName: emoji)
                    .font(.body)
                if count > 0 {
                    Text("\(count)")
                        .font(.caption.bold())
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.cardGap)
            .padding(.vertical, DesignTokens.Spacing.chipVerticalMed)
            .glassEffect(.regular.tint(isSelected ? .teal : .clear).interactive(), in: .capsule)
        }
        .foregroundStyle(isSelected ? .teal : .secondary)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Decision.self, DecisionReaction.self, DecisionComment.self, configurations: config)
    let decision = Decision(title: "Should we get a trampoline?", decisionType: .poll, body: "The kids have been asking", pollOptions: ["Yes!", "No way", "Maybe later"])
    container.mainContext.insert(decision)

    return NavigationStack {
        DecisionDetailView(decision: decision)
    }
    .modelContainer(container)
}
