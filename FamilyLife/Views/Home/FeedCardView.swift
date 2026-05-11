import SwiftUI

// MARK: - Interactive Feed Card

struct FeedCard: View {
    let item: APIService.ActivityItem
    @Binding var selectedTab: MainTab
    var onEventTap: ((Int) -> Void)?

    @Environment(APIService.self) private var api
    @Environment(AuthService.self) private var auth
    @Environment(HouseholdService.self) private var household

    @State private var isLiked = false
    @State private var likeCount = 0
    @State private var comments: [APIService.FeedCommentResponse] = []
    @State private var showingComments = false
    @State private var newComment = ""
    @State private var isSendingComment = false
    @State private var commentCount = 0

    private var isPost: Bool { item.feed_type == "post" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            cardHeader

            // Body content
            if let body = item.body, !body.isEmpty, isPost {
                Text(attributedBody(body))
                    .font(.system(size: 15))
                    .foregroundStyle(WarmPalette.ink1)
                    .lineSpacing(3)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }

            // Action bar
            actionBar

            // Expandable comments
            if showingComments {
                commentsSection
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 18))
    }

    // MARK: - Header

    private var cardHeader: some View {
        Button { navigate() } label: {
            HStack(spacing: 10) {
                if isCurrentUserAuthor {
                    ProfileAvatar(size: 32)
                } else {
                    FamilyAvatar(
                        initial: String(item.author?.prefix(1) ?? "?").uppercased(),
                        size: 32
                    )
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.author ?? "Someone")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(WarmPalette.ink1)
                        Text(typeBadge)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(accentColor.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    Text(relativeTime)
                        .font(.system(size: 11))
                        .foregroundStyle(WarmPalette.ink4)
                }

                Spacer()

                if !isPost {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(WarmPalette.ink4)
                }
            }
            .padding(14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 0) {
            // Like
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    toggleLike()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 14))
                        .foregroundStyle(isLiked ? WarmPalette.bad : WarmPalette.ink3)
                        .scaleEffect(isLiked ? 1.1 : 1.0)
                    if likeCount > 0 {
                        Text("\(likeCount)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(isLiked ? WarmPalette.bad : WarmPalette.ink3)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }

            divider

            // Comment
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    showingComments.toggle()
                }
                if showingComments && comments.isEmpty {
                    Task { await loadMeta() }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 14))
                        .foregroundStyle(showingComments ? accentColor : WarmPalette.ink3)
                    if commentCount > 0 {
                        Text("\(commentCount)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(showingComments ? accentColor : WarmPalette.ink3)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(WarmPalette.ink1.opacity(0.06))
                .frame(height: 0.5)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(WarmPalette.ink1.opacity(0.06))
            .frame(width: 0.5, height: 20)
    }

    // MARK: - Comments Section

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(WarmPalette.ink1.opacity(0.06))
                .frame(height: 0.5)

            if !comments.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(comments) { comment in
                        commentRow(comment)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 4)
            }

            // Compose
            HStack(spacing: 10) {
                ProfileAvatar(size: 24)

                TextField("Add a comment...", text: $newComment)
                    .font(.system(size: 14))
                    .textFieldStyle(.plain)

                if !newComment.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button {
                        Task { await sendComment() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(accentColor)
                    }
                    .disabled(isSendingComment)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .animation(.spring(response: 0.25), value: newComment.isEmpty)
        }
    }

    private func commentRow(_ comment: APIService.FeedCommentResponse) -> some View {
        HStack(alignment: .top, spacing: 10) {
            FamilyAvatar(
                initial: String(comment.user_name?.prefix(1) ?? "?").uppercased(),
                size: 22
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(comment.user_name ?? "Someone")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WarmPalette.ink1)
                    if let created = comment.created_at {
                        Text(relativeTimeFrom(created))
                            .font(.system(size: 11))
                            .foregroundStyle(WarmPalette.ink4)
                    }
                }
                Text(attributedBody(comment.text))
                    .font(.system(size: 14))
                    .foregroundStyle(WarmPalette.ink2)
                    .lineSpacing(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    // MARK: - Attributed text with @mentions

    private func attributedBody(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        let memberNames = household.members.map(\.name)
        let allNames = memberNames + [auth.currentUser?.name].compactMap { $0 }

        for name in allNames {
            let tag = "@\(name)"
            var searchStart = result.startIndex
            while let range = result[searchStart...].range(of: tag) {
                result[range].foregroundColor = UIColor(accentColor)
                result[range].font = .systemFont(ofSize: 14, weight: .semibold)
                searchStart = range.upperBound
            }
        }
        return result
    }

    // MARK: - Data

    private func loadMeta() async {
        guard isPost, item.ref_id > 0 else { return }
        do {
            let reactions = try await api.fetchFeedReactions(postId: item.ref_id)
            likeCount = reactions.count
            isLiked = reactions.contains { $0.user_name == auth.currentUser?.name || $0.user_name == auth.currentUser?.username }
            let fetchedComments = try await api.fetchFeedComments(postId: item.ref_id)
            comments = fetchedComments
            commentCount = fetchedComments.count
        } catch {
            guard !error.isCancellation else { return }
        }
    }

    private func toggleLike() {
        isLiked.toggle()
        likeCount += isLiked ? 1 : -1
        Task {
            do {
                if isLiked {
                    try await api.addFeedReaction(postId: item.ref_id)
                } else {
                    try await api.removeFeedReaction(postId: item.ref_id)
                }
            } catch {
                guard !error.isCancellation else { return }
                isLiked.toggle()
                likeCount += isLiked ? 1 : -1
            }
        }
    }

    private func sendComment() async {
        let text = newComment.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        isSendingComment = true
        newComment = ""
        do {
            try await api.addFeedComment(postId: item.ref_id, text: text)
            let fetched = try await api.fetchFeedComments(postId: item.ref_id)
            withAnimation(.spring(response: 0.3)) {
                comments = fetched
                commentCount = fetched.count
            }
        } catch {
            guard !error.isCancellation else { return }
            newComment = text
        }
        isSendingComment = false
    }

    // MARK: - Helpers

    private var isCurrentUserAuthor: Bool {
        guard let author = item.author else { return false }
        return author.localizedCaseInsensitiveCompare(auth.currentUser?.name ?? "") == .orderedSame
            || author.localizedCaseInsensitiveCompare(auth.currentUser?.username ?? "") == .orderedSame
    }

    private var relativeTime: String {
        guard let created = item.created_at,
              let date = ISO8601DateFormatter.flexible.date(from: created) else {
            return ""
        }
        return date.formatted(.relative(presentation: .named))
    }

    private func relativeTimeFrom(_ dateStr: String) -> String {
        guard let date = ISO8601DateFormatter.flexible.date(from: dateStr) else { return "" }
        return date.formatted(.relative(presentation: .named))
    }

    private var accentColor: Color {
        switch item.feed_type {
        case "decision": TabAccent.decisions.color
        case "event": TabAccent.calendar.color
        case "coverage": TabAccent.care.color
        case "rivalry": AccentTheme.saffron.color
        case "post": AccentTheme.ocean.color
        default: WarmPalette.ink3
        }
    }

    private var typeBadge: String {
        switch item.feed_type {
        case "decision": "Decision"
        case "event": "Event"
        case "coverage": "Coverage"
        case "rivalry": "Challenge"
        case "post": "Post"
        default: "Update"
        }
    }

    private func navigate() {
        switch item.feed_type {
        case "decision": selectedTab = .decisions
        case "event": onEventTap?(item.ref_id)
        default: break
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        FeedCard(
            item: APIService.ActivityItem(
                feed_type: "post",
                ref_id: 1,
                title: "Beautiful day for a walk",
                body: "Took the kids to Point Pleasant Park. @Sophie you should bring Rowan next time!",
                author: "Jesse",
                status: nil,
                created_at: ISO8601DateFormatter().string(from: Date())
            ),
            selectedTab: .constant(.home)
        )
    }
    .padding()
    .background { AmbientBackground(style: .home) }
    .environment(APIService())
    .environment(AuthService())
    .environment(HouseholdService())
}
