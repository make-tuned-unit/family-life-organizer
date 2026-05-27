import SwiftUI
import PhotosUI

struct ChatSheet: View {
    var initialThread: ChatThread?

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
                        .id(partnerId)
                case .group(let groupId, _):
                    GroupChatView(groupId: groupId)
                        .id(groupId)
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
                    if let initial = initialThread {
                        selectedThread = initial
                    } else if let unread = conversations.first(where: { $0.unread_count > 0 }) {
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
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var pendingImageData: Data?
    @State private var showingNewDecision = false
    @State private var openDecisions: [DecisionResponse] = []
    @State private var fullscreenImage: UIImage?

    private var canSend: Bool {
        !newMessage.trimmingCharacters(in: .whitespaces).isEmpty || pendingImageData != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Open decisions bar
            if !openDecisions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(openDecisions) { decision in
                            NavigationLink {
                                DecisionDetailView(decision: decision)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "chart.bar.fill")
                                        .font(.system(size: 10))
                                    Text(decision.title)
                                        .font(.system(size: 12, weight: .medium))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(TabAccent.decisions.color)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(TabAccent.decisions.color.opacity(0.1), in: Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                }
                .padding(.vertical, 6)
                .background(WarmPalette.cardSurface.opacity(0.8))
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(posts.reversed()) { post in
                            GroupMessageBubble(post: post, isOwn: post.author_name == auth.currentUser?.name) { image in
                                fullscreenImage = image
                            }
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

            // Compose bar
            VStack(spacing: 0) {
                // Image preview
                if let imageData = pendingImageData, let uiImage = UIImage(data: imageData) {
                    HStack {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Spacer()
                        Button { pendingImageData = nil } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(WarmPalette.ink4)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                }

                HStack(spacing: 8) {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Image(systemName: "photo")
                            .font(.system(size: 18))
                            .foregroundStyle(WarmPalette.ink3)
                    }
                    .onChange(of: selectedPhoto) {
                        Task {
                            if let data = try? await selectedPhoto?.loadTransferable(type: Data.self) {
                                pendingImageData = UIImage(data: data)?.jpegData(compressionQuality: 0.5)
                            }
                        }
                    }

                    Button { showingNewDecision = true } label: {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(TabAccent.decisions.color)
                    }

                    TextField("Message...", text: $newMessage)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.send)
                        .onSubmit { send() }

                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(canSend ? TabAccent.home.color : WarmPalette.ink4)
                    }
                    .disabled(!canSend)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .background(.ultraThinMaterial)
        }
        .sheet(isPresented: $showingNewDecision) {
            NewDecisionView(preselectedGroupId: groupId) {
                await loadDecisions()
                await loadPosts()
            }
        }
        .fullScreenCover(item: Binding(
            get: { fullscreenImage.map { IdentifiableImage(image: $0) } },
            set: { fullscreenImage = $0?.image }
        )) { item in
            ImagePreviewView(image: item.image) { fullscreenImage = nil }
        }
        .task {
            await loadPosts()
            await loadDecisions()
        }
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

    private func loadDecisions() async {
        do {
            let all = try await api.fetchDecisions()
            let now = Date()
            openDecisions = all.filter { decision in
                decision.status == DecisionStatus.active.rawValue
                && decision.group_id == groupId
                && !isExpired(decision, now: now)
            }
        } catch {}
    }

    private func isExpired(_ decision: DecisionResponse, now: Date) -> Bool {
        guard let expiresStr = decision.expires_at,
              let expiresDate = ISO8601DateFormatter.flexible.date(from: expiresStr) else {
            return false
        }
        return expiresDate <= now
    }

    private func send() {
        let text = newMessage.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty || pendingImageData != nil else { return }
        let imageBase64 = pendingImageData?.base64EncodedString()
        Task {
            var data: [String: Any] = [
                "post_type": imageBase64 != nil ? "photo" : "text",
                "body": text.isEmpty ? "Shared a photo" : text
            ]
            if !text.isEmpty { data["title"] = String(text.prefix(60)) }
            if let imageBase64 { data["photo_url"] = imageBase64 }
            _ = try? await api.addFeedPost(groupId: groupId, data: data)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            newMessage = ""
            pendingImageData = nil
            selectedPhoto = nil
            await loadPosts()
        }
    }
}

// MARK: - Inline Poll Card (self-contained: loads decision + reactions, handles voting)

struct InlinePollCard: View {
    let decisionId: Int
    let title: String
    var isOwn: Bool = false
    @Environment(APIService.self) private var api
    @Environment(AuthService.self) private var auth
    @State private var decision: DecisionResponse?
    @State private var reactions: [DecisionReactionResponse] = []
    @State private var loaded = false

    private var myVote: Int? {
        reactions.first {
            $0.member_name == (auth.currentUser?.username ?? "") && $0.reaction_type == "vote"
        }?.poll_choice
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(TabAccent.decisions.color)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WarmPalette.ink1)
            }

            if let decision, !decision.poll_options.isEmpty {
                let totalVotes = reactions.filter { $0.reaction_type == "vote" }.count
                ForEach(Array(decision.poll_options.enumerated()), id: \.offset) { idx, option in
                    let count = reactions.filter { $0.poll_choice == idx }.count
                    Button {
                        Task { await vote(for: idx) }
                    } label: {
                        HStack {
                            Text(option)
                                .font(.system(size: 13))
                                .foregroundStyle(WarmPalette.ink1)
                            Spacer()
                            Text("\(count)")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(TabAccent.home.color)
                            if myVote == idx {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(TabAccent.home.color)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background {
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(TabAccent.decisions.color.opacity(0.12))
                                    .frame(width: totalVotes > 0 ? geo.size.width * CGFloat(count) / CGFloat(totalVotes) : 0)
                            }
                        }
                        .background(WarmPalette.ink1.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            } else if !loaded {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isOwn ? AnyShapeStyle(Color.white.opacity(0.95)) : AnyShapeStyle(TabAccent.decisions.color.opacity(0.08)),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .task { await load() }
    }

    private func load() async {
        do {
            decision = try await api.fetchDecision(id: decisionId)
            reactions = try await api.fetchDecisionReactions(id: decisionId)
            loaded = true
        } catch {
            loaded = true
        }
    }

    private func vote(for option: Int) async {
        do {
            try await api.setDecisionReaction(id: decisionId, data: [
                "member_name": auth.currentUser?.username ?? "Me",
                "reaction_type": "vote",
                "poll_choice": option
            ])
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            reactions = (try? await api.fetchDecisionReactions(id: decisionId)) ?? reactions
        } catch {}
    }
}

struct GroupMessageBubble: View {
    let post: APIService.FeedPostResponse
    let isOwn: Bool
    var onImageTap: ((UIImage) -> Void)?

    var body: some View {
        HStack {
            if isOwn { Spacer(minLength: 60) }
            VStack(alignment: isOwn ? .trailing : .leading, spacing: 4) {
                if !isOwn {
                    Text(post.author_name ?? "Someone")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WarmPalette.ink3)
                }

                // Inline decision/poll card
                if (post.post_type == "decision" || post.post_type == "poll"), let refId = post.reference_id {
                    InlinePollCard(decisionId: refId, title: post.title ?? "Decision", isOwn: isOwn)
                }

                // Photo
                if let photoBase64 = post.photo_url,
                   let data = Data(base64Encoded: photoBase64),
                   let uiImage = UIImage(data: data) {
                    Button { onImageTap?(uiImage) } label: {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 200, maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }

                if let body = post.body, !body.isEmpty, body != "Shared a photo" {
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
