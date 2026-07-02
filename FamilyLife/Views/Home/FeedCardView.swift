import SwiftUI

struct FeedCard: View {
    let prepared: PreparedFeedItem
    @Binding var selectedTab: MainTab
    var onEventTap: ((Int) -> Void)?
    var onRivalryTap: ((Int) -> Void)?
    var onCoverageTap: (() -> Void)?
    var onGroupTap: ((APIService.GroupResponse) -> Void)?

    @Environment(APIService.self) private var api
    @Environment(AuthService.self) private var auth
    @Environment(HouseholdService.self) private var household
    @Environment(ProfileImageCache.self) private var profileCache

    @State private var showingSendTo = false
    @State private var isLiked = false
    @State private var likeCount = 0
    @State private var comments: [APIService.FeedCommentResponse] = []
    @State private var isExpanded = false
    @State private var newComment = ""
    @State private var isSendingComment = false
    @State private var commentCount = 0
    @State private var mentionSuggestions: [APIService.ContactResponse] = []
    @State private var metaLoaded = false
    @State private var photo: UIImage?

    private var item: APIService.ActivityItem { prepared.item }
    private var displayLikeCount: Int { metaLoaded ? likeCount : (item.reaction_count ?? 0) }
    private var displayCommentCount: Int { metaLoaded ? commentCount : (item.comment_count ?? 0) }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — always visible
            header

            // Title — show for all items except plain text posts (where title is just truncated body)
            if let title = item.title, !title.isEmpty {
                let isPlainTextPost = prepared.isPost && (item.status == nil || item.status == "text")
                if !isPlainTextPost {
                    // If nothing follows the title (a bare event with no date/body and
                    // no counts row), give it real bottom room so it isn't cramped —
                    // matching the 14pt top inset from the header.
                    let bodyFollows = prepared.body != nil || (item.body.map { !$0.isEmpty } ?? false)
                    let countsFollow = prepared.isPost && !isExpanded
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WarmPalette.ink1)
                        .padding(.horizontal, 14)
                        .padding(.bottom, (bodyFollows || countsFollow) ? 4 : 14)
                }
            }

            // Body text — for posts (attributed) and non-posts (plain)
            if let body = prepared.body {
                Text(body)
                    .font(.system(size: 15))
                    .foregroundStyle(WarmPalette.ink1)
                    .lineSpacing(3)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            } else if let bodyText = item.body, !bodyText.isEmpty {
                Text(bodyText)
                    .font(.system(size: 14))
                    .foregroundStyle(WarmPalette.ink2)
                    .lineSpacing(2)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }

            // Photo — the list only carries a flag; the image is fetched lazily
            // per post and cached so scrolling doesn't refetch.
            if prepared.isPost && (item.has_photo ?? 0) == 1 {
                feedPhoto
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
        .contextMenu {
            Button { showingSendTo = true } label: {
                Label("Send to...", systemImage: "arrowshape.turn.up.right")
            }
        }
        .sheet(isPresented: $showingSendTo) {
            SendToSheet(quotedItem: QuotedItem(
                type: item.feed_type,
                id: item.ref_id,
                title: item.title ?? item.body ?? "Feed item"
            ))
        }
        .onTapGesture { tapped() }
    }

    // MARK: - Header (no Button — just a view)

    // The post represents the group/household itself (a bare "Family" event,
    // a group decision) rather than an individual — show the group's image.
    private var groupAuthored: Bool {
        guard let gid = item.group_id, gid > 0 else { return false }
        guard let author = item.author, !author.isEmpty else { return true }
        if author.localizedCaseInsensitiveCompare("Family") == .orderedSame { return true }
        if let gn = item.group_name, author.localizedCaseInsensitiveCompare(gn) == .orderedSame { return true }
        return false
    }

    private var header: some View {
        HStack(spacing: 10) {
            Group {
                if groupAuthored, let gid = item.group_id {
                    GroupAvatar(groupId: gid, name: item.group_name ?? item.author ?? "Family", size: 32)
                } else {
                    UserAvatar(name: item.author ?? "?", userId: item.author_id, size: 32)
                        .onAppear {
                            if let authorId = item.author_id {
                                profileCache.fetchIfNeeded(userId: authorId, api: api)
                            }
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
                HStack(spacing: 4) {
                    Text(prepared.time)
                        .font(.system(size: 11))
                        .foregroundStyle(WarmPalette.ink4)
                    if let groupName = item.group_name {
                        Text("\u{00B7}")
                            .foregroundStyle(WarmPalette.ink4)
                        Button {
                            if let gid = item.group_id {
                                onGroupTap?(APIService.GroupResponse(
                                    id: gid, name: groupName,
                                    group_type: "", description: nil,
                                    invite_code: nil, role: nil,
                                    member_count: nil, created_by: nil,
                                    created_at: nil
                                ))
                            }
                        } label: {
                            Text(groupName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(AccentTheme.mauve.color)
                        }
                        .buttonStyle(.plain)
                    }
                }
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
                UserAvatar(name: auth.currentUser?.name ?? "?", userId: auth.currentUser?.id, size: 24)

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
            UserAvatar(name: comment.user_name ?? "?", userId: comment.user_id, size: 22)

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
        // Optimistic: show the comment immediately with a temporary id; the
        // refetch reconciles it on success, and we roll back on failure.
        let temp = APIService.FeedCommentResponse(
            id: Int.random(in: Int.min ..< 0), user_id: auth.currentUser?.id,
            user_name: auth.currentUser?.name, user_avatar: nil, text: text, created_at: nil
        )
        withAnimation(.spring(response: 0.3)) {
            comments.append(temp)
            commentCount += 1
        }
        do {
            try await api.addFeedComment(postId: item.ref_id, text: text)
            let fetched = try await api.fetchFeedComments(postId: item.ref_id)
            withAnimation(.spring(response: 0.3)) {
                comments = fetched
                commentCount = fetched.count
            }
        } catch {
            guard !error.isCancellation else { return }
            withAnimation(.spring(response: 0.3)) {
                comments.removeAll { $0.id == temp.id }
                commentCount = max(0, commentCount - 1)
            }
            newComment = text
        }
        isSendingComment = false
    }

    // MARK: - Photo (lazy)

    @ViewBuilder
    private var feedPhoto: some View {
        Group {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(WarmPalette.ink1.opacity(0.05))
                    .frame(height: 200)
                    .overlay { ProgressView() }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .task(id: item.ref_id) { await loadPhoto() }
    }

    private func loadPhoto() async {
        if let cached = FeedPhotoCache.shared.object(forKey: NSNumber(value: item.ref_id)) {
            photo = cached
            return
        }
        guard let b64 = try? await api.fetchFeedPhoto(postId: item.ref_id),
              let data = Data(base64Encoded: b64 ?? ""),
              let img = UIImage(data: data) else { return }
        FeedPhotoCache.shared.setObject(img, forKey: NSNumber(value: item.ref_id))
        photo = img
    }

    // MARK: - Helpers

    private func tapped() {
        switch item.feed_type {
        case "decision": break // decisions accessed via chat/feed
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
        case "post":
            // Use post_type (stored in status) for more specific badges
            switch item.status {
            case "event": "Event"
            case "rivalry": "Challenge"
            case "decision", "poll": "Decision"
            case "photo": "Photo"
            case "link": "Link"
            case "milestone": "Milestone"
            default: "Post"
            }
        default: "Update"
        }
    }
}

/// Process-wide cache for lazily-fetched feed photos, so scrolling the Home
/// feed doesn't refetch the same image.
final class FeedPhotoCache {
    static let shared = NSCache<NSNumber, UIImage>()
    private init() {}
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
                    comment_count: 1,
                    group_id: 1,
                    group_name: "Fairbanks",
                    has_photo: 0
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
