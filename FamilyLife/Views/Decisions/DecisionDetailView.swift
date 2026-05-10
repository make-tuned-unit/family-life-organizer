import SwiftUI

struct DecisionDetailView: View {
    @Environment(APIService.self) private var api
    let decision: DecisionResponse

    @State private var reactions: [DecisionReactionResponse] = []
    @State private var comments: [DecisionCommentResponse] = []
    @State private var newComment = ""
    @State private var currentDecision: DecisionResponse
    @State private var error: String?

    @Environment(AuthService.self) private var auth

    init(decision: DecisionResponse) {
        self.decision = decision
        _currentDecision = State(initialValue: decision)
    }

    private var myReaction: String? {
        reactions.first { $0.member_name == (auth.currentUser?.username ?? "Me") && $0.reaction_type != "vote" }?.reaction_type
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: currentDecision.decisionType.icon)
                            .foregroundStyle(TabAccent.home.color)
                        Text(currentDecision.creator_name)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        if let created = currentDecision.createdDate {
                            Text(created, style: .relative)
                                .font(.caption)
                                .foregroundStyle(WarmPalette.ink3)
                        }
                    }

                    Text(currentDecision.title)
                        .font(.title3.bold())

                    if let body = currentDecision.body, !body.isEmpty {
                        Text(body)
                            .font(.subheadline)
                            .foregroundStyle(WarmPalette.ink3)
                    }

                    if let url = currentDecision.link_url, !url.isEmpty, let parsedURL = URL(string: url) {
                        Link(destination: parsedURL) {
                            HStack {
                                Image(systemName: "link")
                                Text(url)
                                    .lineLimit(1)
                            }
                            .font(.subheadline)
                            .padding(DesignTokens.Spacing.inset)
                            .background(TabAccent.decisions.color.opacity(DesignTokens.Opacity.cardTint))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding(.horizontal)

                if currentDecision.decisionType == .poll && !currentDecision.poll_options.isEmpty {
                    VStack(spacing: 8) {
                        let totalVotes = reactions.filter { $0.reaction_type == "vote" }.count
                        let myVote = reactions.first { $0.member_name == (auth.currentUser?.username ?? "Me") && $0.reaction_type == "vote" }?.poll_choice
                        ForEach(Array(currentDecision.poll_options.enumerated()), id: \.offset) { idx, option in
                            let voteCount = reactions.filter { $0.poll_choice == idx }.count
                            Button {
                                Task { await vote(for: idx) }
                            } label: {
                                HStack {
                                    Text(option)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text("\(voteCount)")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(TabAccent.home.color)
                                    if myVote == idx {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(TabAccent.home.color)
                                    }
                                }
                                .padding(DesignTokens.Spacing.cardGap)
                                .background {
                                    GeometryReader { geo in
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(TabAccent.decisions.color.opacity(DesignTokens.Opacity.cardTint))
                                            .frame(width: totalVotes > 0 ? geo.size.width * Double(voteCount) / Double(totalVotes) : 0)
                                    }
                                }
                                .background(WarmPalette.ink1.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .disabled(currentDecision.status != DecisionStatus.active.rawValue)
                        }
                    }
                    .padding(.horizontal)
                }

                if currentDecision.decisionType != .poll {
                    HStack(spacing: 16) {
                        ReactionButton(emoji: "hand.thumbsup.fill", type: "thumbsUp", count: reactions.filter { $0.reaction_type == "thumbsUp" }.count, isSelected: myReaction == "thumbsUp") {
                            Task { await react("thumbsUp") }
                        }
                        ReactionButton(emoji: "hand.thumbsdown.fill", type: "thumbsDown", count: reactions.filter { $0.reaction_type == "thumbsDown" }.count, isSelected: myReaction == "thumbsDown") {
                            Task { await react("thumbsDown") }
                        }
                        ReactionButton(emoji: "heart.fill", type: "heart", count: reactions.filter { $0.reaction_type == "heart" }.count, isSelected: myReaction == "heart") {
                            Task { await react("heart") }
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Comments (\(comments.count))")
                        .font(.headline)
                        .padding(.horizontal)

                    ForEach(comments) { comment in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "person.circle.fill")
                                .foregroundStyle(WarmPalette.ink3)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(comment.member_name)
                                        .font(.caption.weight(.semibold))
                                    if let date = comment.createdDate {
                                        Text(date, style: .relative)
                                            .font(.caption2)
                                            .foregroundStyle(WarmPalette.ink4)
                                    }
                                }
                                Text(comment.text)
                                    .font(.subheadline)
                            }
                        }
                        .padding(.horizontal)
                    }

                    if currentDecision.status == DecisionStatus.active.rawValue {
                        HStack {
                            TextField("Add a comment...", text: $newComment)
                                
                            Button {
                                Task { await addComment() }
                            } label: {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(TabAccent.home.color)
                            }
                            .disabled(newComment.isEmpty)
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
        .background { AmbientBackground(style: .decisions) }
        .navigationTitle(currentDecision.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if currentDecision.status == DecisionStatus.active.rawValue && currentDecision.creator_name == (auth.currentUser?.username ?? "Me") {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Resolve") {
                        Task { await resolveDecision() }
                    }
                }
            }
        }
        .alert("Couldn’t update decision", isPresented: errorAlertIsPresented) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "An unexpected error occurred.")
        }
        .task {
            await reload()
        }
    }

    private func reload() async {
        do {
            async let fetchedReactions = api.fetchDecisionReactions(id: currentDecision.id)
            async let fetchedComments = api.fetchDecisionComments(id: currentDecision.id)
            reactions = try await fetchedReactions
            comments = try await fetchedComments
        } catch is CancellationError {
            // View dismissed — ignore
            } catch {
            self.error = error.localizedDescription
        }
    }

    private func react(_ type: String) async {
        do {
            try await api.setDecisionReaction(id: currentDecision.id, data: [
                "member_name": auth.currentUser?.username ?? "Me",
                "reaction_type": type
            ])
            await reload()
        } catch is CancellationError {
            // View dismissed — ignore
            } catch {
            self.error = error.localizedDescription
        }
    }

    private func vote(for option: Int) async {
        do {
            try await api.setDecisionReaction(id: currentDecision.id, data: [
                "member_name": auth.currentUser?.username ?? "Me",
                "reaction_type": "vote",
                "poll_choice": option
            ])
            await reload()
        } catch is CancellationError {
            // View dismissed — ignore
            } catch {
            self.error = error.localizedDescription
        }
    }

    private func addComment() async {
        do {
            try await api.addDecisionComment(id: currentDecision.id, data: [
                "member_name": auth.currentUser?.username ?? "Me",
                "text": newComment
            ])
            newComment = ""
            await reload()
        } catch is CancellationError {
            // View dismissed — ignore
            } catch {
            self.error = error.localizedDescription
        }
    }

    private func resolveDecision() async {
        do {
            try await api.updateDecision(id: currentDecision.id, data: [
                "status": DecisionStatus.resolved.rawValue
            ])
            currentDecision = DecisionResponse(
                id: currentDecision.id,
                title: currentDecision.title,
                decision_type: currentDecision.decision_type,
                body: currentDecision.body,
                link_url: currentDecision.link_url,
                photo_data: currentDecision.photo_data,
                poll_options: currentDecision.poll_options,
                creator_name: currentDecision.creator_name,
                status: DecisionStatus.resolved.rawValue,
                created_at: currentDecision.created_at,
                expires_at: currentDecision.expires_at
            )
        } catch is CancellationError {
            // View dismissed — ignore
            } catch {
            self.error = error.localizedDescription
        }
    }

    private var errorAlertIsPresented: Binding<Bool> {
        Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )
    }
}

#Preview {
    NavigationStack {
        DecisionDetailView(
            decision: DecisionResponse(
                id: 1,
                title: "Should we get a trampoline?",
                decision_type: "poll",
                body: "The kids have been asking",
                link_url: nil,
                photo_data: nil,
                poll_options: ["Yes", "No", "Maybe later"],
                creator_name: "Jesse",
                status: "active",
                created_at: "2026-04-08T00:00:00Z",
                expires_at: "2026-04-15T00:00:00Z"
            )
        )
        .environment(APIService())
    }
}
