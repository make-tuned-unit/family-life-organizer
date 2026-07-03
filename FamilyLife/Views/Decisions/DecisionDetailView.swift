import SwiftUI

struct DecisionDetailView: View {
    @Environment(APIService.self) private var api
    let decision: DecisionResponse
    var onChanged: (() async -> Void)?

    @State private var reactions: [DecisionReactionResponse] = []
    @State private var comments: [DecisionCommentResponse] = []
    @State private var newComment = ""
    @State private var currentDecision: DecisionResponse
    @State private var error: String?
    @State private var showingDeleteConfirm = false
    @State private var showingSendTo = false

    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    init(decision: DecisionResponse, onChanged: (() async -> Void)? = nil) {
        self.decision = decision
        self.onChanged = onChanged
        _currentDecision = State(initialValue: decision)
    }

    private var isCurrentUserCreator: Bool {
        currentDecision.creator_name.localizedCaseInsensitiveCompare(auth.currentUser?.name ?? "") == .orderedSame
            || currentDecision.creator_name.localizedCaseInsensitiveCompare(auth.currentUser?.username ?? "") == .orderedSame
    }

    private var myReaction: String? {
        reactions.first { $0.member_name == (auth.currentUser?.username ?? "Me") && $0.reaction_type != "vote" }?.reaction_type
    }

    private var statusBadge: some View {
        Group {
            if currentDecision.status == DecisionStatus.resolved.rawValue {
                Label("Resolved", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WarmPalette.good)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(WarmPalette.good.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            } else if let expiresStr = currentDecision.expires_at,
                      let expiresDate = ISO8601DateFormatter.flexible.date(from: expiresStr) {
                if expiresDate < Date() {
                    Label("Expired", systemImage: "clock.badge.xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WarmPalette.ink3)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(WarmPalette.ink1.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                } else {
                    Label("Expires \(expiresDate, style: .relative)", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(WarmPalette.ink3)
                }
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if currentDecision.status != DecisionStatus.active.rawValue || currentDecision.expires_at != nil {
                    statusBadge
                        .padding(.horizontal)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        UserAvatar(name: currentDecision.creator_name, size: 24)
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

                    if let photoData = currentDecision.photo_data,
                       let data = Data(base64Encoded: photoData),
                       let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .frame(maxWidth: .infinity)
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
                                .submitLabel(.send)
                                .onSubmit {
                                    guard !newComment.isEmpty else { return }
                                    Task { await addComment() }
                                }
                            Button {
                                Task { await addComment() }
                            } label: {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(newComment.isEmpty ? WarmPalette.ink4 : TabAccent.home.color)
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
            if isCurrentUserCreator {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if currentDecision.status == DecisionStatus.active.rawValue {
                            Button {
                                Task { await resolveDecision() }
                            } label: {
                                Label("Mark Resolved", systemImage: "checkmark.circle")
                            }
                        }
                        Button { showingSendTo = true } label: {
                            Label("Send to...", systemImage: "arrowshape.turn.up.right")
                        }
                        Button(role: .destructive) {
                            showingDeleteConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(WarmPalette.ink2)
                    }
                }
            }
        }
        .sheet(isPresented: $showingSendTo) {
            SendToSheet(quotedItem: QuotedItem(
                type: "decision",
                id: currentDecision.id,
                title: currentDecision.title
            ))
        }
        .confirmationDialog("Delete this decision?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    do {
                        try await api.deleteDecision(id: currentDecision.id)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        await onChanged?()
                        dismiss()
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("This will permanently remove the decision and all its reactions and comments.")
        }
        .inlineError(error) { error = nil }
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
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }

    private func react(_ type: String) async {
        do {
            try await api.setDecisionReaction(id: currentDecision.id, data: [
                "member_name": auth.currentUser?.username ?? "Me",
                "reaction_type": type
            ])
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            await reload()
        } catch {
            guard !error.isCancellation else { return }
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
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            await reload()
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }

    private func addComment() async {
        do {
            try await api.addDecisionComment(id: currentDecision.id, data: [
                "member_name": auth.currentUser?.username ?? "Me",
                "text": newComment
            ])
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            newComment = ""
            await reload()
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }

    private func resolveDecision() async {
        do {
            try await api.updateDecision(id: currentDecision.id, data: [
                "status": DecisionStatus.resolved.rawValue
            ])
            UINotificationFeedbackGenerator().notificationOccurred(.success)
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
                expires_at: currentDecision.expires_at,
                group_id: currentDecision.group_id,
                person_id: currentDecision.person_id
            )
            await onChanged?()
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
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
                expires_at: "2026-04-15T00:00:00Z",
                group_id: nil,
                person_id: nil
            )
        )
        .environment(APIService())
    }
}
