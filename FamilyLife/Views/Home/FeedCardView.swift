import SwiftUI

struct FeedCard: View {
    let prepared: PreparedFeedItem
    @Binding var selectedTab: MainTab
    var onEventTap: ((Int) -> Void)?
    var onRivalryTap: ((Int) -> Void)?
    var onCoverageTap: (() -> Void)?

    @Environment(APIService.self) private var api
    @Environment(AuthService.self) private var auth
    @Environment(HouseholdService.self) private var household
    @Environment(ProfileImageCache.self) private var profileCache

    @State private var isLiked = false
    @State private var likeCount = 0
    @State private var comments: [APIService.FeedCommentResponse] = []
    @State private var isExpanded = false
    @State private var newComment = ""
    @State private var isSendingComment = false
    @State private var commentCount = 0
    @State private var mentionSuggestions: [APIService.ContactResponse] = []
    @State private var metaLoaded = false

    private var item: APIService.ActivityItem { prepared.item }
    private var displayLikeCount: Int { metaLoaded ? likeCount : (item.reaction_count ?? 0) }
    private var displayCommentCount: Int { metaLoaded ? commentCount : (item.comment_count ?? 0) }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — always visible
            header

            // Body text — always visible for posts
            if let body = prepared.body {
                Text(body)
                    .font(.system(size: 15))
                    .foregroundStyle(WarmPalette.ink1)
                    .lineSpacing(3)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }

            // Inline counts — always visible for posts, no buttons during scroll
            if prepared.isPost && !isExpanded {
                countsRow
            }

            // Action bar + comments — only when expanded (not in scroll tree otherwise)
            if isExpanded && prepared.isPost {
                actionBar
                commentsSection
            }
        }
        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .onTapGesture { tapped() }
    }

    // MARK: - Header (no Button — just a view)

    private var header: some View {
        HStack(spacing: 10) {
            if prepared.isOwnPost {
                ProfileAvatar(size: 32)
            } else if let authorId = item.author_id, let img = profileCache.image(for: authorId) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                    .onAppear { profileCache.fetchIfNeeded(userId: authorId, api: api) }
            } else {
                FamilyAvatar(
                    initial: String(item.author?.prefix(1) ?? "?").uppercased(),
                    size: 32
                )
                .onAppear {
                    if let authorId = item.author_id {
                        profileCache.fetchIfNeeded(userId: authorId, api: api)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.author ?? "Someone")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WarmPalette.ink1)
                    Text(typeBadge)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(prepared.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(prepared.accentColor.opacity(0.1), in: Capsule())
                }
                Text(prepared.time)
                    .font(.system(size: 11))
                    .foregroundStyle(WarmPalette.ink4)
            }

            Spacer()

            if !prepared.isPost {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(WarmPalette.ink4)
            }
        }
        .padding(14)
    }

    // MARK: - Counts Row (lightweight, no buttons)

    private var countsRow: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.system(size: 12))
                    .foregroundStyle(isLiked ? WarmPalette.bad : WarmPalette.ink4)
                if displayLikeCount > 0 {
                    Text("\(displayLikeCount)")
                        .font(.system(size: 11))
                        .foregroundStyle(WarmPalette.ink4)
                }
            }
            HStack(spacing: 4) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 12))
                    .foregroundStyle(WarmPalette.ink4)
                if displayCommentCount > 0 {
                    Text("\(displayCommentCount)")
                        .font(.system(size: 11))
                        .foregroundStyle(WarmPalette.ink4)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    // MARK: - Action Bar (only when expanded)

    private var actionBar: some View {
        HStack(spacing: 0) {
            Button { toggleLike() } label: {
                HStack(spacing: 5) {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 14))
                        .foregroundStyle(isLiked ? WarmPalette.bad : WarmPalette.ink3)
                    if displayLikeCount > 0 {
                        Text("\(displayLikeCount)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(isLiked ? WarmPalette.bad : WarmPalette.ink3)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }

            Rectangle()
                .fill(WarmPalette.ink1.opacity(0.06))
                .frame(width: 0.5, height: 20)

            Button {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded = false
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 12))
                        .foregroundStyle(WarmPalette.ink3)
                    Text("Close")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WarmPalette.ink3)
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

    // MARK: - Comments Section

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !comments.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(comments) { comment in
                        commentRow(comment)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 4)
            }

            if !mentionSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(mentionSuggestions, id: \.name) { member in
                        Button { insertMention(member.name) } label: {
                            HStack(spacing: 8) {
                                FamilyAvatar(
                                    initial: member.avatar_initial ?? String(member.name.prefix(1)).uppercased(),
                                    size: 20
                                )
                                Text(member.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(WarmPalette.ink1)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
                .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 14)
            }

            HStack(spacing: 10) {
                ProfileAvatar(size: 24)

                TextField("Add a comment...", text: $newComment)
                    .font(.system(size: 14))
                    .textFieldStyle(.plain)
                    .onChange(of: newComment) { updateMentionSuggestions() }

                if !newComment.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button {
                        Task { await sendComment() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(prepared.accentColor)
                    }
                    .disabled(isSendingComment)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private func commentRow(_ comment: APIService.FeedCommentResponse) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if isCommentByCurrentUser(comment) {
                ProfileAvatar(size: 22)
            } else {
                FamilyAvatar(
                    initial: String(comment.user_name?.prefix(1) ?? "?").uppercased(),
                    size: 22
                )
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(comment.user_name ?? "Someone")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WarmPalette.ink1)
                    if let created = comment.created_at {
                        Text(HomeViewModel.formatRelativeTime(created))
                            .font(.system(size: 11))
                            .foregroundStyle(WarmPalette.ink4)
                    }
                }
                Text(Self.buildCommentBody(comment.text, accent: prepared.accentColor))
                    .font(.system(size: 14))
                    .foregroundStyle(WarmPalette.ink2)
                    .lineSpacing(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func isCommentByCurrentUser(_ comment: APIService.FeedCommentResponse) -> Bool {
        guard let name = comment.user_name else { return false }
        return name.localizedCaseInsensitiveCompare(auth.currentUser?.name ?? "") == .orderedSame
            || name.localizedCaseInsensitiveCompare(auth.currentUser?.username ?? "") == .orderedSame
    }

    // MARK: - Attributed text (comments only)

    private static func buildCommentBody(_ text: String, accent: Color) -> AttributedString {
        var result = AttributedString(text)
        let nsText = text as NSString
        let matches = HomeViewModel.mentionRegex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            guard let swiftRange = Range(match.range, in: text),
                  let attrRange = result.range(of: String(text[swiftRange])) else { continue }
            result[attrRange].foregroundColor = UIColor(accent)
            result[attrRange].font = .systemFont(ofSize: 14, weight: .semibold)
        }
        return result
    }

    // MARK: - Data

    private func loadMeta() async {
        guard prepared.isPost, item.ref_id > 0, !metaLoaded else { return }
        do {
            async let reactionsReq = api.fetchFeedReactions(postId: item.ref_id)
            async let commentsReq = api.fetchFeedComments(postId: item.ref_id)
            let (reactions, fetchedComments) = try await (reactionsReq, commentsReq)
            likeCount = reactions.count
            isLiked = reactions.contains { $0.user_name == auth.currentUser?.name || $0.user_name == auth.currentUser?.username }
            comments = fetchedComments
            commentCount = fetchedComments.count
            metaLoaded = true
        } catch {
            guard !error.isCancellation else { return }
        }
    }

    private func toggleLike() {
        guard prepared.isPost, item.ref_id > 0 else { return }
        Task {
            if !metaLoaded { await loadMeta() }
            guard metaLoaded else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isLiked.toggle()
                likeCount += isLiked ? 1 : -1
            }
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

    private func tapped() {
        switch item.feed_type {
        case "decision": selectedTab = .decisions
        case "event": onEventTap?(item.ref_id)
        case "rivalry": onRivalryTap?(item.ref_id)
        case "coverage": onCoverageTap?()
        case "post", "comment", "reaction":
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                isExpanded.toggle()
            }
            if isExpanded && !metaLoaded {
                Task { await loadMeta() }
            }
        default: break
        }
    }

    private func updateMentionSuggestions() {
        guard let atRange = newComment.range(of: "@", options: .backwards) else {
            mentionSuggestions = []
            return
        }
        let afterAt = String(newComment[atRange.upperBound...])
        let query = afterAt.lowercased().trimmingCharacters(in: .whitespaces)

        let matches = household.members.filter {
            query.isEmpty || $0.name.lowercased().hasPrefix(query)
        }

        if !query.isEmpty && matches.isEmpty {
            mentionSuggestions = []
        } else if afterAt.hasSuffix(" ") && matches.contains(where: { $0.name.lowercased() == query }) {
            mentionSuggestions = []
        } else {
            mentionSuggestions = matches
        }
    }

    private func insertMention(_ name: String) {
        guard let atRange = newComment.range(of: "@", options: .backwards) else { return }
        newComment = String(newComment[..<atRange.lowerBound]) + "@\(name) "
        mentionSuggestions = []
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
}

#Preview {
    VStack(spacing: 12) {
        FeedCard(
            prepared: PreparedFeedItem(
                item: APIService.ActivityItem(
                    feed_type: "post",
                    ref_id: 1,
                    title: "Beautiful day for a walk",
                    body: "Took the kids to Point Pleasant Park.",
                    author: "Jesse",
                    author_id: 1,
                    status: nil,
                    created_at: ISO8601DateFormatter().string(from: Date()),
                    reaction_count: 2,
                    comment_count: 1
                ),
                body: AttributedString("Took the kids to Point Pleasant Park."),
                time: "2 hours ago",
                isPost: true,
                accentColor: AccentTheme.ocean.color,
                isOwnPost: true
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
