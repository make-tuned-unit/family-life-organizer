import SwiftUI

struct FamilyGroupsView: View {
    @Environment(APIService.self) private var api
    @Environment(AuthService.self) private var auth
    @State private var groups: [APIService.GroupResponse] = []
    @State private var contacts: [APIService.ContactResponse] = []
    @State private var isLoading = false
    @State private var showingNewGroup = false
    @State private var showingAddContact = false
    @State private var showingJoinGroup = false
    @State private var selectedGroup: APIService.GroupResponse?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                headerSection
                householdSection
                groupsSection
                contactsSection
            }
            .padding(.bottom, DesignTokens.Spacing.bottomBuffer)
        }
        .background { AmbientBackground(style: .home) }
        .navigationTitle("Family")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showingNewGroup = true } label: {
                        Label("New Group", systemImage: "person.3.fill")
                    }
                    Button { showingAddContact = true } label: {
                        Label("Add Family Member", systemImage: "person.badge.plus")
                    }
                    Button { showingJoinGroup = true } label: {
                        Label("Join with Code", systemImage: "ticket.fill")
                    }
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(WarmPalette.ink2)
                }
            }
        }
        .sheet(isPresented: $showingNewGroup) {
            NewGroupSheet { await loadAll() }
        }
        .sheet(isPresented: $showingAddContact) {
            AddContactSheet { await loadAll() }
        }
        .sheet(isPresented: $showingJoinGroup) {
            JoinGroupSheet { await loadAll() }
        }
        .sheet(item: $selectedGroup) { group in
            NavigationStack {
                GroupDetailView(group: group)
            }
        }
        .overlay {
            if isLoading && groups.isEmpty { ProgressView() }
        }
        .refreshable { await loadAll() }
        .task { await loadAll() }
    }

    private func loadAll() async {
        isLoading = true
        do {
            async let g = api.fetchGroups()
            async let c = api.fetchContacts()
            groups = try await g
            contacts = try await c
        } catch {}
        isLoading = false
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("YOUR PEOPLE")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WarmPalette.ink3)
                    .tracking(0.4)
                Text("Family")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(WarmPalette.ink1)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 16)
    }

    // MARK: - Household

    @ViewBuilder
    private var householdSection: some View {
        let household = groups.first { $0.group_type == "household" }
        if let household {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(AccentTheme.sage.color)
                        .frame(width: 36, height: 36)
                        .background(AccentTheme.sage.color.opacity(0.15))
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(household.name)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(WarmPalette.ink1)
                        Text("\(household.member_count ?? 1) members")
                            .font(.system(size: 13))
                            .foregroundStyle(WarmPalette.ink3)
                    }
                    Spacer()
                    if let code = household.invite_code {
                        Button {
                            UIPasteboard.general.string = code
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 11))
                                Text(code)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            }
                            .foregroundStyle(WarmPalette.ink2)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .glassEffect(.regular.tint(.white.opacity(0.05)), in: .capsule)
                        }
                    }
                }
                Text("Share the invite code with your partner to join your household.")
                    .font(.system(size: 13))
                    .foregroundStyle(WarmPalette.ink3)
            }
            .padding(16)
            .glassEffect(.regular.tint(AccentTheme.sage.color.opacity(0.04)), in: .rect(cornerRadius: DesignTokens.CornerRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                    .stroke(AccentTheme.sage.color.opacity(0.15), lineWidth: 1)
            )
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            .padding(.bottom, 14)
        }
    }

    // MARK: - Groups

    private var groupsSection: some View {
        VStack(spacing: 0) {
            let nonHousehold = groups.filter { $0.group_type != "household" }
            if !nonHousehold.isEmpty {
                WarmSectionHeader(title: "Groups", trailing: "\(nonHousehold.count)")
                    .padding(.bottom, 8)

                ForEach(nonHousehold) { group in
                    Button { selectedGroup = group } label: {
                        GroupRow(group: group)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    // MARK: - Contacts

    private var contactsSection: some View {
        VStack(spacing: 0) {
            if !contacts.isEmpty {
                WarmSectionHeader(title: "Family Members", trailing: "\(contacts.count)")
                    .padding(.bottom, 8)
                    .padding(.top, 4)

                ForEach(contacts) { contact in
                    ContactRow(contact: contact)
                        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                        .padding(.bottom, 6)
                }
            } else if !isLoading {
                VStack(spacing: 8) {
                    Button { showingAddContact = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 16))
                            Text("Add your first family member")
                                .font(.system(size: 15, weight: .medium))
                        }
                        .foregroundStyle(AccentTheme.sage.color)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: DesignTokens.CornerRadius.card))
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                .padding(.top, 8)
            }
        }
    }
}

// MARK: - Group Row

struct GroupRow: View {
    let group: APIService.GroupResponse

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: group.group_type == "tribe" ? "globe" : "person.3.fill")
                .font(.system(size: 16))
                .foregroundStyle(group.group_type == "tribe" ? AccentTheme.ocean.color : AccentTheme.mauve.color)
                .frame(width: 32, height: 32)
                .background((group.group_type == "tribe" ? AccentTheme.ocean.color : AccentTheme.mauve.color).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WarmPalette.ink1)
                HStack(spacing: 6) {
                    Text(group.group_type.capitalized)
                    Text("\(group.member_count ?? 0) members")
                }
                .font(.system(size: 13))
                .foregroundStyle(WarmPalette.ink3)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WarmPalette.ink4)
        }
        .padding(14)
        .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 16))
    }
}

// MARK: - Contact Row

struct ContactRow: View {
    let contact: APIService.ContactResponse

    var body: some View {
        HStack(spacing: 12) {
            FamilyAvatar(initial: contact.avatar_initial ?? String(contact.name.prefix(1)).uppercased(), size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WarmPalette.ink1)
                if let relationship = contact.relationship, !relationship.isEmpty {
                    Text(relationship.capitalized)
                        .font(.system(size: 13))
                        .foregroundStyle(WarmPalette.ink3)
                }
            }
            Spacer()
            if let phone = contact.phone, !phone.isEmpty {
                Image(systemName: "phone.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(WarmPalette.ink4)
            }
        }
        .padding(12)
        .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 14))
    }
}

// MARK: - Group Detail

struct GroupDetailView: View {
    let group: APIService.GroupResponse
    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss
    @State private var members: [APIService.GroupMemberResponse] = []
    @State private var feed: [APIService.FeedPostResponse] = []
    @State private var showingNewPost = false
    @State private var selectedTab = 0

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    Text(group.name)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(WarmPalette.ink1)
                    Text("\(group.group_type.capitalized) - \(members.count) members")
                        .font(.system(size: 13))
                        .foregroundStyle(WarmPalette.ink3)
                    if let code = group.invite_code {
                        HStack(spacing: 6) {
                            Text("Invite: \(code)")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                            Button {
                                UIPasteboard.general.string = code
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 11))
                            }
                        }
                        .foregroundStyle(WarmPalette.ink3)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .glassEffect(.regular.tint(.white.opacity(0.05)), in: .capsule)
                    }
                }
                .padding(.top, 14)
                .padding(.bottom, 16)

                // Tab selector
                HStack(spacing: 0) {
                    ForEach(["Feed", "Members"], id: \.self) { tab in
                        let index = tab == "Feed" ? 0 : 1
                        Text(tab)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(selectedTab == index ? WarmPalette.cream1 : WarmPalette.ink2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(selectedTab == index ? WarmPalette.ink1 : .clear)
                            .clipShape(Capsule())
                            .onTapGesture { withAnimation { selectedTab = index } }
                    }
                }
                .padding(4)
                .glassEffect(.regular.tint(.white.opacity(0.05)), in: .capsule)
                .padding(.horizontal, 22)
                .padding(.bottom, 14)

                if selectedTab == 0 {
                    feedSection
                } else {
                    membersSection
                }
            }
            .padding(.bottom, DesignTokens.Spacing.bottomBuffer)
        }
        .background { AmbientBackground(style: .decisions) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
                    .foregroundStyle(WarmPalette.ink2)
            }
            ToolbarItem(placement: .topBarTrailing) {
                GlassIconButton(systemName: "plus") { showingNewPost = true }
            }
        }
        .sheet(isPresented: $showingNewPost) {
            NewFeedPostSheet(groupId: group.id) { await loadFeed() }
        }
        .task {
            async let m: () = loadMembers()
            async let f: () = loadFeed()
            _ = await (m, f)
        }
    }

    // MARK: - Feed

    private var feedSection: some View {
        VStack(spacing: 10) {
            if feed.isEmpty {
                WarmEmptyState(
                    title: "No posts yet",
                    systemImage: "bubble.left.and.bubble.right",
                    description: "Share something with this group"
                )
            } else {
                ForEach(feed) { post in
                    FeedPostCard(post: post)
                        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                }
            }
        }
    }

    // MARK: - Members

    private var membersSection: some View {
        VStack(spacing: 8) {
            ForEach(members) { member in
                HStack(spacing: 12) {
                    FamilyAvatar(initial: member.initial, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(WarmPalette.ink1)
                        HStack(spacing: 6) {
                            if let rel = member.relationship {
                                Text(rel.capitalized)
                            }
                            Text(member.role)
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(WarmPalette.ink3)
                    }
                    Spacer()
                    if member.user_id != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(WarmPalette.good)
                    }
                }
                .padding(12)
                .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 14))
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            }
        }
    }

    private func loadMembers() async {
        do { members = try await api.fetchGroupMembers(groupId: group.id) } catch {}
    }

    private func loadFeed() async {
        do { feed = try await api.fetchFeed(groupId: group.id) } catch {}
    }
}

// MARK: - Feed Post Card

struct FeedPostCard: View {
    let post: APIService.FeedPostResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Author + time
            HStack(spacing: 10) {
                FamilyAvatar(initial: String(post.author_name?.prefix(1) ?? "?").uppercased(), size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(post.author_name ?? "Unknown")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WarmPalette.ink1)
                    if let date = post.created_at {
                        Text(String(date.prefix(10)))
                            .font(.system(size: 11))
                            .foregroundStyle(WarmPalette.ink3)
                    }
                }
                Spacer()
                postTypeBadge
            }

            // Content
            if let title = post.title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(WarmPalette.ink1)
            }
            if let body = post.body, !body.isEmpty {
                Text(body)
                    .font(.system(size: 15))
                    .foregroundStyle(WarmPalette.ink2)
            }
            if let url = post.link_url, !url.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: 12))
                    Text(url)
                        .font(.system(size: 13))
                        .lineLimit(1)
                }
                .foregroundStyle(AccentTheme.ocean.color)
            }

            // Reactions + comments count
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "heart")
                        .font(.system(size: 13))
                    Text("\(post.reaction_count)")
                        .font(.system(size: 13))
                }
                HStack(spacing: 4) {
                    Image(systemName: "bubble.right")
                        .font(.system(size: 13))
                    Text("\(post.comment_count)")
                        .font(.system(size: 13))
                }
                Spacer()
            }
            .foregroundStyle(WarmPalette.ink3)
        }
        .padding(16)
        .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 20))
    }

    @ViewBuilder
    private var postTypeBadge: some View {
        let (icon, label, color): (String, String, Color) = switch post.post_type {
        case "photo": ("photo", "Photo", AccentTheme.saffron.color)
        case "link": ("link", "Link", AccentTheme.ocean.color)
        case "event": ("calendar", "Event", AccentTheme.mauve.color)
        case "decision": ("bubble.left.and.bubble.right", "Decision", TabAccent.decisions.color)
        case "rivalry": ("flame", "Challenge", AccentTheme.rose.color)
        case "poll": ("chart.bar", "Poll", AccentTheme.sage.color)
        default: ("text.bubble", "Post", WarmPalette.ink3)
        }
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(label)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .glassEffect(.regular.tint(color.opacity(0.08)), in: .capsule)
    }
}

// MARK: - New Feed Post Sheet

struct NewFeedPostSheet: View {
    let groupId: Int
    let onComplete: () async -> Void
    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss
    @State private var postType = "text"
    @State private var title = ""
    @State private var bodyText = ""
    @State private var linkUrl = ""

    private let types = [
        ("text", "Text", "text.bubble"),
        ("photo", "Photo", "photo"),
        ("link", "Link", "link"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Type", selection: $postType) {
                        ForEach(types, id: \.0) { t in
                            Label(t.1, systemImage: t.2).tag(t.0)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Content") {
                    TextField("Title (optional)", text: $title)
                    TextField("What's on your mind?", text: $bodyText, axis: .vertical)
                        .lineLimit(3...8)
                    if postType == "link" {
                        TextField("URL", text: $linkUrl)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground(style: .decisions) }
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(WarmPalette.ink2)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") {
                        Task {
                            var data: [String: Any] = ["post_type": postType, "body": bodyText]
                            if !title.isEmpty { data["title"] = title }
                            if !linkUrl.isEmpty { data["link_url"] = linkUrl }
                            let _ = try? await api.addFeedPost(groupId: groupId, data: data)
                            await onComplete()
                            dismiss()
                        }
                    }
                    .disabled(bodyText.isEmpty)
                }
            }
        }
    }
}

// MARK: - New Group Sheet

struct NewGroupSheet: View {
    let onComplete: () async -> Void
    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var groupType = "family"

    var body: some View {
        NavigationStack {
            Form {
                Section("Group") {
                    TextField("Group name", text: $name)
                    Picker("Type", selection: $groupType) {
                        Text("Family").tag("family")
                        Text("Tribe").tag("tribe")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground(style: .home) }
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(WarmPalette.ink2)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            let _ = try? await api.createGroup(["name": name, "group_type": groupType])
                            await onComplete()
                            dismiss()
                        }
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}

// MARK: - Add Contact Sheet

struct AddContactSheet: View {
    let onComplete: () async -> Void
    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var relationship = "mom"
    @State private var phone = ""
    @State private var email = ""
    @State private var birthday = ""

    private let relationships = ["wife", "husband", "partner", "mom", "dad", "sister", "brother", "mother-in-law", "father-in-law", "sister-in-law", "brother-in-law", "grandparent", "aunt", "uncle", "cousin", "friend", "other"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Person") {
                    TextField("Name", text: $name)
                    Picker("Relationship", selection: $relationship) {
                        ForEach(relationships, id: \.self) { rel in
                            Text(rel.capitalized).tag(rel)
                        }
                    }
                }
                Section("Contact Info") {
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                }
                Section("Details") {
                    TextField("Birthday (YYYY-MM-DD)", text: $birthday)
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground(style: .home) }
            .navigationTitle("Add Family Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(WarmPalette.ink2)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            var data: [String: Any] = ["name": name, "relationship": relationship]
                            if !phone.isEmpty { data["phone"] = phone }
                            if !email.isEmpty { data["email"] = email }
                            if !birthday.isEmpty { data["birthday"] = birthday }
                            let _ = try? await api.addContact(data)
                            await onComplete()
                            dismiss()
                        }
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}

// MARK: - Join Group Sheet

struct JoinGroupSheet: View {
    let onComplete: () async -> Void
    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Invite Code") {
                    TextField("Enter code", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                if let error {
                    Section { Text(error).foregroundStyle(WarmPalette.bad) }
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground(style: .home) }
            .navigationTitle("Join Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(WarmPalette.ink2)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join") {
                        Task {
                            do {
                                let _ = try await api.joinGroup(inviteCode: code)
                                await onComplete()
                                dismiss()
                            } catch {
                                self.error = "Invalid invite code"
                            }
                        }
                    }
                    .disabled(code.isEmpty)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        FamilyGroupsView()
    }
    .environment(APIService())
    .environment(AuthService())
}
