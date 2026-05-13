import SwiftUI

struct ChatSheet: View {
    @Environment(APIService.self) private var api
    @Environment(AuthService.self) private var auth
    @Environment(HouseholdService.self) private var household
    @Environment(ProfileImageCache.self) private var profileCache
    @Environment(\.dismiss) private var dismiss

    @State private var conversations: [APIService.ConversationResponse] = []
    @State private var groups: [APIService.GroupResponse] = []
    @State private var selectedThread: ChatThread?

    enum ChatThread: Equatable {
        case dm(partnerId: Int, name: String)
        case group(groupId: Int, name: String)
    }

    private var otherMembers: [APIService.ContactResponse] {
        guard let user = auth.currentUser else { return household.members }
        return household.members.filter {
            $0.name.localizedCaseInsensitiveCompare(user.name) != .orderedSame
            && $0.name.localizedCaseInsensitiveCompare(user.username) != .orderedSame
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Thread picker — groups first, then DMs
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        // Group threads
                        ForEach(groups) { group in
                            let isSelected = selectedThread == .group(groupId: group.id, name: group.name)
                            Button {
                                selectedThread = .group(groupId: group.id, name: group.name)
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: groupIcon(group.group_type))
                                        .font(.system(size: 18))
                                        .foregroundStyle(isSelected ? .white : groupColor(group.group_type))
                                        .frame(width: 44, height: 44)
                                        .background(
                                            isSelected ? groupColor(group.group_type) : groupColor(group.group_type).opacity(0.15),
                                            in: Circle()
                                        )
                                    Text(group.name.components(separatedBy: " ").first ?? group.name)
                                        .font(.system(size: 11, weight: isSelected ? .bold : .regular))
                                        .foregroundStyle(isSelected ? groupColor(group.group_type) : WarmPalette.ink3)
                                        .lineLimit(1)
                                }
                                .frame(width: 60)
                            }
                            .buttonStyle(.plain)
                        }

                        // Divider between groups and DMs
                        if !groups.isEmpty && !otherMembers.isEmpty {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(WarmPalette.ink1.opacity(0.1))
                                .frame(width: 1, height: 36)
                        }

                        // DM threads
                        ForEach(otherMembers) { member in
                            let partnerId = household.userId(for: member.name) ?? abs(member.id)
                            let isSelected = selectedThread == .dm(partnerId: partnerId, name: member.name)
                            let unread = conversations.first { $0.partner_id == partnerId }?.unread_count ?? 0
                            Button {
                                selectedThread = .dm(partnerId: partnerId, name: member.name)
                            } label: {
                                VStack(spacing: 4) {
                                    ZStack(alignment: .topTrailing) {
                                        if let img = profileCache.image(for: partnerId) {
                                            Image(uiImage: img)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 44, height: 44)
                                                .clipShape(Circle())
                                                .overlay {
                                                    Circle().stroke(isSelected ? TabAccent.home.color : .clear, lineWidth: 2)
                                                }
                                        } else {
                                            FamilyAvatar(
                                                initial: member.avatar_initial ?? String(member.name.prefix(1)).uppercased(),
                                                size: 44
                                            )
                                        }
                                        if unread > 0 {
                                            Text("\(unread)")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(.white)
                                                .frame(minWidth: 16, minHeight: 16)
                                                .background(AccentTheme.rose.color, in: Circle())
                                                .offset(x: 2, y: -2)
                                        }
                                    }
                                    Text(member.name.components(separatedBy: " ").first ?? member.name)
                                        .font(.system(size: 11, weight: isSelected ? .bold : .regular))
                                        .foregroundStyle(isSelected ? TabAccent.home.color : WarmPalette.ink3)
                                        .lineLimit(1)
                                }
                                .frame(width: 60)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 8)
                .background(WarmPalette.cardSurface)

                Divider()

                // Thread content
                switch selectedThread {
                case .dm(let partnerId, let name):
                    ConversationView(partnerId: partnerId, partnerName: name)
                case .group(let groupId, _):
                    GroupChatView(groupId: groupId)
                case nil:
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                            .font(.system(size: 32))
                            .foregroundStyle(WarmPalette.ink4)
                        Text("Select a chat")
                            .font(.system(size: 14))
                            .foregroundStyle(WarmPalette.ink3)
                    }
                    Spacer()
                }
            }
            .background { AmbientBackground(style: .home) }
            .navigationTitle(threadTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(WarmPalette.ink2)
                }
            }
            .task {
                conversations = (try? await api.fetchConversations()) ?? []
                groups = (try? await api.fetchGroups()) ?? []
                if selectedThread == nil {
                    // Auto-select: unread DM first, then first group
                    if let unread = conversations.first(where: { $0.unread_count > 0 }) {
                        selectedThread = .dm(partnerId: unread.partner_id, name: unread.partner_name)
                    } else if let first = groups.first {
                        selectedThread = .group(groupId: first.id, name: first.name)
                    } else if let first = otherMembers.first {
                        let pid = household.userId(for: first.name) ?? abs(first.id)
                        selectedThread = .dm(partnerId: pid, name: first.name)
                    }
                }
            }
        }
    }

    private var threadTitle: String {
        switch selectedThread {
        case .dm(_, let name): name
        case .group(_, let name): name
        case nil: "Messages"
        }
    }

    private func groupIcon(_ type: String) -> String {
        switch type {
        case "household": "house.fill"
        case "family": "person.3.fill"
        case "tribe": "globe"
        default: "person.2.fill"
        }
    }

    private func groupColor(_ type: String) -> Color {
        switch type {
        case "household": TabAccent.home.color
        case "family": AccentTheme.mauve.color
        case "tribe": AccentTheme.ocean.color
        default: WarmPalette.ink2
        }
    }
}

// MARK: - Group Chat View (uses existing feed posts)

struct GroupChatView: View {
    let groupId: Int
    @Environment(APIService.self) private var api
    @Environment(AuthService.self) private var auth

    @State private var posts: [APIService.FeedPostResponse] = []
    @State private var newMessage = ""
    @State private var pollTimer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(posts.reversed()) { post in
                            GroupMessageBubble(post: post, isOwn: post.author_name == auth.currentUser?.name)
                                .id(post.id)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .onChange(of: posts.count) {
                    if let last = posts.reversed().last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider()

            HStack(spacing: 10) {
                TextField("Message...", text: $newMessage)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.send)
                    .onSubmit { send() }

                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(newMessage.isEmpty ? WarmPalette.ink4 : TabAccent.home.color)
                }
                .disabled(newMessage.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
        .task { await loadPosts() }
        .onAppear {
            pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
                Task { @MainActor in await loadPosts() }
            }
        }
        .onDisappear {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }

    private func loadPosts() async {
        posts = (try? await api.fetchFeed(groupId: groupId)) ?? []
    }

    private func send() {
        let text = newMessage.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        Task {
            _ = try? await api.addFeedPost(groupId: groupId, data: [
                "post_type": "text",
                "title": String(text.prefix(60)),
                "body": text
            ])
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            newMessage = ""
            await loadPosts()
        }
    }
}

struct GroupMessageBubble: View {
    let post: APIService.FeedPostResponse
    let isOwn: Bool

    var body: some View {
        HStack {
            if isOwn { Spacer(minLength: 60) }
            VStack(alignment: isOwn ? .trailing : .leading, spacing: 4) {
                if !isOwn {
                    Text(post.author_name ?? "Someone")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WarmPalette.ink3)
                }

                // Decision/poll badge
                if post.post_type == "decision" || post.post_type == "poll" {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 10))
                        Text("Decision")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(TabAccent.decisions.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(TabAccent.decisions.color.opacity(0.1), in: Capsule())
                }

                if let body = post.body, !body.isEmpty {
                    Text(body)
                        .font(.system(size: 15))
                        .foregroundStyle(isOwn ? .white : WarmPalette.ink1)
                }

                if let date = post.created_at {
                    Text(relativeTime(date))
                        .font(.system(size: 10))
                        .foregroundStyle(isOwn ? .white.opacity(0.7) : WarmPalette.ink4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isOwn ? AnyShapeStyle(TabAccent.home.color) : AnyShapeStyle(WarmPalette.cardSurface),
                in: RoundedRectangle(cornerRadius: 16)
            )
            if !isOwn { Spacer(minLength: 60) }
        }
    }

    private func relativeTime(_ dateStr: String) -> String {
        guard let date = ISO8601DateFormatter.flexible.date(from: dateStr) else { return "" }
        return date.formatted(.relative(presentation: .named))
    }
}
