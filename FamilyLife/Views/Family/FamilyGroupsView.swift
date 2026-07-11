import SwiftUI
import PhotosUI

struct FamilyGroupsView: View {
    @Environment(APIService.self) private var api
    @Environment(AuthService.self) private var auth
    @Environment(HouseholdService.self) private var household
    @Environment(ProfileImageCache.self) private var profileCache
    @State private var groups: [APIService.GroupResponse] = []
    @State private var householdMemberNames: Set<String> = []
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
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
            AddContactSheet {
                await household.reload(api: api, currentUserId: auth.currentUser?.id)
                await loadAll()
            }
        }
        .sheet(isPresented: $showingJoinGroup) {
            JoinGroupSheet { await loadAll() }
        }
        .sheet(item: $selectedGroup) { group in
            NavigationStack {
                GroupDetailView(group: group) {
                    await loadAll()
                    await household.reload(api: api, currentUserId: auth.currentUser?.id)
                }
            }
        }
        .overlay {
            if isLoading && groups.isEmpty { FLLoadingState(message: "Loading your people…") }
        }
        .refreshable { await loadAll() }
        .task { await loadAll() }
    }

    private func loadAll() async {
        isLoading = true
        do {
            groups = try await api.fetchGroups()
            profileCache.loadFromGroups(groups)
            // Load household members to separate them from wider family
            if let hhGroup = groups.first(where: { $0.group_type == "household" }) {
                let members = (try? await api.fetchGroupMembers(groupId: hhGroup.id)) ?? []
                householdMemberNames = Set(members.map { $0.displayName.lowercased() })
            }
        } catch {
            guard !error.isCancellation else { return }
        }
        isLoading = false
    }

    // MARK: - Header

    private var headerSection: some View {
        FLScreenHeader(eyebrow: "Your people", title: "Family")
    }

    // MARK: - Household

    @ViewBuilder
    private var householdSection: some View {
        let households = groups.filter { $0.group_type == "household" }
        ForEach(households) { hh in
            Button { selectedGroup = hh } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        GroupAvatar(groupId: hh.id, name: hh.name, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hh.name)
                                .font(.flHeadline)
                                .foregroundStyle(WarmPalette.ink1)
                            Text("\(hh.member_count ?? 1) members")
                                .font(.flFootnote)
                                .foregroundStyle(WarmPalette.ink3)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(WarmPalette.ink4)
                    }
                }
                .padding(16)
                .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            .padding(.bottom, 8)
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

    /// Contacts from wider groups only (household members show in Household settings)
    private var widerFamilyContacts: [APIService.ContactResponse] {
        guard let user = auth.currentUser else { return household.members }
        return household.members.filter { contact in
            // Exclude self
            guard contact.name.localizedCaseInsensitiveCompare(user.name) != .orderedSame
                && contact.name.localizedCaseInsensitiveCompare(user.username) != .orderedSame else { return false }
            // Exclude household members (they show in Household settings)
            let firstName = contact.name.lowercased().split(separator: " ").first.map(String.init) ?? contact.name.lowercased()
            return !householdMemberNames.contains(contact.name.lowercased())
                && !householdMemberNames.contains(firstName)
        }
    }

    private var contactsSection: some View {
        VStack(spacing: 0) {
            if !widerFamilyContacts.isEmpty {
                WarmSectionHeader(title: "Family Members", trailing: "\(widerFamilyContacts.count)")
                    .padding(.bottom, 8)
                    .padding(.top, 4)

                ForEach(widerFamilyContacts) { contact in
                    ContactRow(contact: contact, groups: groups)
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
                                .font(.flSubheadline.weight(.medium))
                        }
                        .foregroundStyle(AccentTheme.sage.color)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
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
            GroupAvatar(groupId: group.id, name: group.name, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.flSubheadline.weight(.semibold))
                    .foregroundStyle(WarmPalette.ink1)
                HStack(spacing: 6) {
                    Text(group.group_type.capitalized)
                    Text("\(group.member_count ?? 0) members")
                }
                .font(.flFootnote)
                .foregroundStyle(WarmPalette.ink3)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WarmPalette.ink4)
        }
        .padding(14)
        .flCard()
    }
}

// MARK: - Contact Row

struct ContactRow: View {
    let contact: APIService.ContactResponse
    var groups: [APIService.GroupResponse] = []
    @Environment(HouseholdService.self) private var household

    var body: some View {
        HStack(spacing: 12) {
            UserAvatar(name: contact.name, userId: household.userId(for: contact.name), size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name)
                    .font(.flSubheadline.weight(.semibold))
                    .foregroundStyle(WarmPalette.ink1)
                if let relationship = contact.relationship, !relationship.isEmpty {
                    Text(relationship.capitalized)
                        .font(.flFootnote)
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
        .flCard()
    }
}

// MARK: - Group Detail

struct GroupDetailView: View {
    let group: APIService.GroupResponse
    var onLeft: (() async -> Void)?
    @Environment(APIService.self) private var api
    @Environment(AuthService.self) private var auth
    @Environment(HouseholdService.self) private var household
    @Environment(ProfileImageCache.self) private var profileCache
    @Environment(\.dismiss) private var dismiss
    @State private var members: [APIService.GroupMemberResponse] = []
    @State private var feed: [APIService.FeedPostResponse] = []
    @State private var isLoadingMoreFeed = false
    @State private var feedReachedEnd = false
    private let feedPageSize = 50
    @State private var showingNewPost = false
    @State private var showingAddMember = false
    @State private var showingLeaveConfirm = false
    @State private var selectedTab = 0
    @State private var copiedCode = false
    @State private var groupImage: UIImage?
    @State private var showingPhotoPicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var errorMessage: String?

    private var isCreator: Bool {
        group.created_by == auth.currentUser?.id
    }

    private var isHousehold: Bool {
        group.group_type == "household"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 10) {
                    Button { showingPhotoPicker = true } label: { groupAvatarView }
                        .buttonStyle(.plain)
                    VStack(spacing: 4) {
                        Text(group.name)
                            .font(.flTitle)
                            .foregroundStyle(WarmPalette.ink1)
                        Text("\(group.group_type.capitalized) \u{00B7} \(members.count) members")
                            .font(.flFootnote)
                            .foregroundStyle(WarmPalette.ink3)
                    }
                }
                .padding(.top, 14)
                .padding(.bottom, 12)

                // Invite code section
                if let code = group.invite_code {
                    VStack(spacing: 10) {
                        Button {
                            UIPasteboard.general.string = code
                            copiedCode = true
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                copiedCode = false
                            }
                        } label: {
                            HStack {
                                Text(code)
                                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                                    .foregroundStyle(WarmPalette.ink1)
                                    .tracking(2)
                                Spacer()
                                Image(systemName: copiedCode ? "checkmark.circle.fill" : "doc.on.doc")
                                    .font(.system(size: 16))
                                    .foregroundStyle(copiedCode ? WarmPalette.good : WarmPalette.ink3)
                            }
                        }
                        .buttonStyle(.plain)

                        ShareLink(
                            item: "Join my \(group.name) circle on Kinrows! Use invite code: \(code)",
                            subject: Text("Join \(group.name)"),
                            message: Text("Join our family circle on Kinrows. Use this code: \(code)")
                        ) {
                            HStack(spacing: 6) {
                                Image(systemName: "message.fill")
                                    .font(.system(size: 14))
                                Text("Send invite")
                            }
                        }
                        .buttonStyle(.flCTA(fill: TabAccent.home.color))
                    }
                    .padding(14)
                    .flCard()
                    .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                    .padding(.bottom, 14)
                }

                if isHousehold {
                    // Households: just show members, no feed tab
                    membersSection
                } else {
                    // Non-household groups: show Feed/Members tabs
                    HStack(spacing: 0) {
                        ForEach(["Feed", "Members"], id: \.self) { tab in
                            let index = tab == "Feed" ? 0 : 1
                            Text(tab)
                                .font(.flFootnote.weight(.semibold))
                                .foregroundStyle(selectedTab == index ? WarmPalette.cream1 : WarmPalette.ink2)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(selectedTab == index ? WarmPalette.ink1 : .clear)
                                .clipShape(Capsule())
                                .onTapGesture { withAnimation { selectedTab = index } }
                        }
                    }
                    .padding(4)
                    .background(WarmPalette.cardSurface, in: Capsule())
                    .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                    .padding(.bottom, 14)

                    if selectedTab == 0 {
                        feedSection
                    } else {
                        membersSection
                    }
                }
            }
            .padding(.bottom, DesignTokens.Spacing.bottomBuffer)
        }
        .background { AmbientBackground(style: .decisions) }
        .inlineError(errorMessage) { errorMessage = nil }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
                    .foregroundStyle(WarmPalette.ink2)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if !isHousehold {
                        Button { showingNewPost = true } label: {
                            Label("New Post", systemImage: "text.bubble")
                        }
                    }
                    Button { showingAddMember = true } label: {
                        Label("Add Member", systemImage: "person.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(WarmPalette.ink2)
                }
            }
        }
        .sheet(isPresented: $showingNewPost) {
            NewFeedPostSheet(groupId: group.id) { await loadFeed() }
        }
        .sheet(isPresented: $showingAddMember) {
            AddGroupMemberSheet(groupId: group.id) { await loadMembers() }
        }
        .confirmationDialog(
            isCreator ? "Delete \(group.name)?" : "Leave \(group.name)?",
            isPresented: $showingLeaveConfirm,
            titleVisibility: .visible
        ) {
            Button(isCreator ? "Delete" : "Leave", role: .destructive) {
                Task {
                    do {
                        if isCreator {
                            try await api.deleteGroup(id: group.id)
                        } else {
                            try await api.leaveGroup(id: group.id)
                        }
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        await onLeft?()
                        dismiss()
                    } catch {
                        guard !error.isCancellation else { return }
                        errorMessage = "\(isCreator ? "Delete" : "Leave") failed — \(error.localizedDescription)"
                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                    }
                }
            }
        } message: {
            Text(isCreator
                 ? "This will permanently remove the group and all its posts."
                 : "You'll no longer see this group's feed or members.")
        }
        .task {
            seedGroupImage()
            async let m: () = loadMembers()
            async let f: () = loadFeed()
            _ = await (m, f)
        }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedPhoto, matching: .images)
        .onChange(of: selectedPhoto) {
            Task { await handlePickedPhoto() }
        }
    }

    // MARK: - Group avatar

    private var groupAvatarView: some View {
        ZStack {
            if let img = currentGroupImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 1))
            } else {
                FamilyAvatar(initial: String(group.name.prefix(1)).uppercased(), size: 72, name: group.name)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "camera.fill")
                .font(.system(size: 11))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(WarmPalette.ink1)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white, lineWidth: 1.5))
        }
    }

    private var currentGroupImage: UIImage? {
        groupImage ?? profileCache.groupImage(for: group.id)
    }

    private func seedGroupImage() {
        guard groupImage == nil else { return }
        if let cached = profileCache.groupImage(for: group.id) {
            groupImage = cached
        } else if let base64 = group.profile_image,
                  let data = Data(base64Encoded: base64),
                  let img = UIImage(data: data) {
            groupImage = img
            profileCache.setGroupImage(img, for: group.id)
        } else {
            profileCache.fetchGroupIfNeeded(groupId: group.id, api: api)
        }
    }

    private func handlePickedPhoto() async {
        guard let data = try? await selectedPhoto?.loadTransferable(type: Data.self) else { return }
        let compressed = UIImage(data: data)?.jpegData(compressionQuality: 0.6) ?? data
        guard let img = UIImage(data: compressed) else { return }
        groupImage = img
        profileCache.setGroupImage(img, for: group.id)
        try? await api.uploadGroupImage(groupId: group.id, compressed.base64EncodedString())
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
                        .onAppear {
                            if post.id == feed.last?.id {
                                Task { await loadMoreFeed() }
                            }
                        }
                }
                if isLoadingMoreFeed {
                    ProgressView()
                        .padding(.vertical, 8)
                }
            }
        }
    }

    // MARK: - Members

    private var membersSection: some View {
        VStack(spacing: 8) {
            ForEach(members) { member in
                HStack(spacing: 12) {
                    FamilyAvatar(initial: member.initial, size: 36, name: member.displayName)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.displayName)
                            .font(.flSubheadline.weight(.semibold))
                            .foregroundStyle(WarmPalette.ink1)
                        HStack(spacing: 6) {
                            if let rel = member.relationship {
                                Text(rel.capitalized)
                            }
                            Text(member.role)
                        }
                        .font(.flFootnote)
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
                .flCard()
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            }

            // Add member button inline
            Button { showingAddMember = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 14))
                    Text("Add a family member")
                        .font(.flSubheadline.weight(.medium))
                }
                .foregroundStyle(TabAccent.home.color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .flCard()
            }
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)

            // Leave / Delete
            Button(role: .destructive) { showingLeaveConfirm = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: isCreator ? "trash" : "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 14))
                    Text(isCreator ? "Delete this group" : "Leave this group")
                        .font(.flSubheadline.weight(.medium))
                }
                .foregroundStyle(WarmPalette.bad)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(WarmPalette.bad.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            .padding(.top, 16)
        }
    }

    private func loadMembers() async {
        do { members = try await api.fetchGroupMembers(groupId: group.id) } catch {}
    }

    private func loadFeed() async {
        do {
            let page = try await api.fetchFeed(groupId: group.id, limit: feedPageSize)
            feed = page
            feedReachedEnd = page.count < feedPageSize
        } catch {}
    }

    // Cursor pagination: load older posts using the oldest loaded post's id as
    // the before_id cursor (feed is ordered id DESC). Triggered when the last
    // row appears.
    private func loadMoreFeed() async {
        guard !isLoadingMoreFeed, !feedReachedEnd, let beforeId = feed.last?.id else { return }
        isLoadingMoreFeed = true
        defer { isLoadingMoreFeed = false }
        do {
            let page = try await api.fetchFeed(groupId: group.id, limit: feedPageSize, beforeId: beforeId)
            let existing = Set(feed.map { $0.id })
            feed.append(contentsOf: page.filter { !existing.contains($0.id) })
            if page.count < feedPageSize { feedReachedEnd = true }
        } catch {}
    }
}

// MARK: - Add Member to Group Sheet

struct AddGroupMemberSheet: View {
    let groupId: Int
    let onComplete: () async -> Void

    @Environment(APIService.self) private var api
    @Environment(HouseholdService.self) private var household
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var relationship = "sister"
    @State private var phone = ""
    @State private var isSaving = false

    private let relationships = [
        "mom", "dad", "sister", "brother",
        "mother-in-law", "father-in-law",
        "sister-in-law", "brother-in-law",
        "grandparent", "aunt", "uncle", "cousin",
        "wife", "husband", "partner",
        "son", "daughter", "child",
        "friend", "other"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    Picker("Relationship", selection: $relationship) {
                        ForEach(relationships, id: \.self) { rel in
                            Text(rel.capitalized).tag(rel)
                        }
                    }
                    TextField("Phone (optional)", text: $phone)
                        .keyboardType(.phonePad)
                } footer: {
                    Text("Add someone who doesn't have the app yet. If they join later with the invite code, they'll appear as a connected user.")
                }

                if !household.members.isEmpty {
                    Section("Or add from your contacts") {
                        ForEach(household.members) { contact in
                            Button {
                                Task {
                                    _ = try? await api.addGroupMember(groupId: groupId, data: [
                                        "contact_id": contact.id,
                                        "role": "member"
                                    ])
                                    await onComplete()
                                    dismiss()
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    FamilyAvatar(
                                        initial: contact.avatar_initial ?? String(contact.name.prefix(1)).uppercased(),
                                        size: 28,
                                        name: contact.name
                                    )
                                    Text(contact.name)
                                        .font(.flSubheadline)
                                        .foregroundStyle(.primary)
                                    if let rel = contact.relationship {
                                        Text(rel.capitalized)
                                            .font(.flCaption)
                                            .foregroundStyle(WarmPalette.ink3)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground(style: .home) }
            .navigationTitle("Add Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(WarmPalette.ink2)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task { await addNewContact() }
                    }
                    .disabled(name.isEmpty || isSaving)
                }
            }
        }
    }

    private func addNewContact() async {
        isSaving = true
        do {
            var contactData: [String: Any] = ["name": name, "relationship": relationship]
            if !phone.isEmpty { contactData["phone"] = phone }
            let result: APIService.IDResponse = try await api.addContact(contactData)
            _ = try? await api.addGroupMember(groupId: groupId, data: [
                "contact_id": result.id,
                "role": "member"
            ])
            await onComplete()
            dismiss()
        } catch {
            isSaving = false
        }
    }
}

// MARK: - Feed Post Card

struct FeedPostCard: View {
    let post: APIService.FeedPostResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Author + time
            HStack(spacing: 10) {
                UserAvatar(name: post.author_name ?? "?", userId: post.author_id, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(post.author_name ?? "Unknown")
                        .font(.flSubheadline.weight(.semibold))
                        .foregroundStyle(WarmPalette.ink1)
                    if let date = post.created_at {
                        Text(String(date.prefix(10)))
                            .font(.flCaption)
                            .foregroundStyle(WarmPalette.ink3)
                    }
                }
                Spacer()
                postTypeBadge
            }

            // Content
            if let title = post.title, !title.isEmpty {
                Text(title)
                    .font(.flHeadline)
                    .foregroundStyle(WarmPalette.ink1)
            }
            if let body = post.body, !body.isEmpty {
                Text(body)
                    .font(.flSubheadline)
                    .foregroundStyle(WarmPalette.ink2)
            }
            if let url = post.link_url, !url.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: 12))
                    Text(url)
                        .font(.flFootnote)
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
                        .font(.flFootnote)
                }
                HStack(spacing: 4) {
                    Image(systemName: "bubble.right")
                        .font(.system(size: 13))
                    Text("\(post.comment_count)")
                        .font(.flFootnote)
                }
                Spacer()
            }
            .foregroundStyle(WarmPalette.ink3)
        }
        .padding(16)
        .flCard()
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
                .font(.flOverline)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(WarmPalette.cardSurface, in: Capsule())
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
    @State private var description = ""

    private let types: [(String, String, String, String)] = [
        ("family", "Family Circle", "person.3.fill", "Your side of the family — parents, siblings, and their households"),
        ("tribe", "Tribe", "globe", "A wider circle — friends, neighbours, anyone you want to stay connected with"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. The Sharratts, Mom's Side", text: $name)
                } header: {
                    Text("Name")
                } footer: {
                    Text("Pick a name everyone in the circle will recognize.")
                }

                Section("Type") {
                    ForEach(types, id: \.0) { type in
                        Button {
                            groupType = type.0
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: type.2)
                                    .font(.system(size: 16))
                                    .foregroundStyle(groupType == type.0 ? TabAccent.home.color : WarmPalette.ink3)
                                    .frame(width: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(type.1)
                                        .font(.flSubheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text(type.3)
                                        .font(.flCaption)
                                        .foregroundStyle(WarmPalette.ink3)
                                }
                                Spacer()
                                if groupType == type.0 {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(TabAccent.home.color)
                                }
                            }
                        }
                    }
                }

                Section {
                    TextField("Optional description", text: $description, axis: .vertical)
                        .lineLimit(2)
                } header: {
                    Text("Description")
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground(style: .home) }
            .navigationTitle("New Circle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(WarmPalette.ink2)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            var data: [String: Any] = ["name": name, "group_type": groupType]
                            if !description.isEmpty { data["description"] = description }
                            let _ = try? await api.createGroup(data)
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
    .environment(HouseholdService())
}
