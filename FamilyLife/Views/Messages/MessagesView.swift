import SwiftUI

struct MessagesView: View {
    @Environment(APIService.self) private var api
    @Environment(AuthService.self) private var auth
    @Environment(HouseholdService.self) private var household
    @Environment(ProfileImageCache.self) private var profileCache

    @State private var conversations: [APIService.ConversationResponse] = []
    @State private var isLoading = false
    @State private var showingNewMessage = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack {
                    Text("Messages")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(WarmPalette.ink1)
                    Spacer()
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .padding(.bottom, 16)

                if conversations.isEmpty && !isLoading {
                    VStack(spacing: 12) {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                            .font(.system(size: 36))
                            .foregroundStyle(WarmPalette.ink4)
                        Text("No messages yet")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(WarmPalette.ink3)
                        Text("Send a private message to a family member")
                            .font(.system(size: 13))
                            .foregroundStyle(WarmPalette.ink4)
                            .multilineTextAlignment(.center)

                        Button { showingNewMessage = true } label: {
                            Label("Start a conversation", systemImage: "plus.message.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(WarmPalette.cream1)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(TabAccent.home.color)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.top, 40)
                } else {
                    ForEach(conversations) { convo in
                        NavigationLink {
                            ConversationView(partnerId: convo.partner_id, partnerName: convo.partner_name)
                        } label: {
                            ConversationRow(conversation: convo)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                        .padding(.bottom, 8)
                    }
                }
            }
            .padding(.bottom, DesignTokens.Spacing.bottomBuffer)
        }
        .background { AmbientBackground(style: .home) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingNewMessage = true } label: {
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(TabAccent.home.color)
                }
            }
        }
        .sheet(isPresented: $showingNewMessage) {
            NewConversationPicker { partnerId, name in
                showingNewMessage = false
            }
        }
        .refreshable { await loadConversations() }
        .overlay {
            if isLoading && conversations.isEmpty { ProgressView() }
        }
        .task { await loadConversations() }
    }

    private func loadConversations() async {
        isLoading = true
        do { conversations = try await api.fetchConversations() } catch {}
        isLoading = false
    }
}

// MARK: - Conversation Row

struct ConversationRow: View {
    let conversation: APIService.ConversationResponse
    @Environment(ProfileImageCache.self) private var profileCache
    @Environment(APIService.self) private var api

    var body: some View {
        HStack(spacing: 12) {
            if let img = profileCache.image(for: conversation.partner_id) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
            } else {
                FamilyAvatar(
                    initial: String(conversation.partner_name.prefix(1)).uppercased(),
                    size: 44
                )
                .onAppear { profileCache.fetchIfNeeded(userId: conversation.partner_id, api: api) }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(conversation.partner_name)
                        .font(.system(size: 15, weight: conversation.unread_count > 0 ? .bold : .semibold))
                        .foregroundStyle(WarmPalette.ink1)
                    Spacer()
                    if let date = conversation.created_at {
                        Text(relativeTime(date))
                            .font(.system(size: 11))
                            .foregroundStyle(WarmPalette.ink4)
                    }
                }

                HStack {
                    Text(conversation.text)
                        .font(.system(size: 13))
                        .foregroundStyle(conversation.unread_count > 0 ? WarmPalette.ink1 : WarmPalette.ink3)
                        .lineLimit(1)
                    Spacer()
                    if conversation.unread_count > 0 {
                        Text("\(conversation.unread_count)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 20, minHeight: 20)
                            .background(TabAccent.home.color, in: Circle())
                    }
                }
            }
        }
        .padding(14)
        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func relativeTime(_ dateStr: String) -> String {
        guard let date = ISO8601DateFormatter.flexible.date(from: dateStr) else { return "" }
        return date.formatted(.relative(presentation: .named))
    }
}

// MARK: - New Conversation Picker

struct NewConversationPicker: View {
    let onSelect: (Int, String) -> Void

    @Environment(HouseholdService.self) private var household
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Send message to") {
                    ForEach(otherMembers) { member in
                        NavigationLink {
                            ConversationView(partnerId: abs(member.id), partnerName: member.name)
                        } label: {
                            HStack(spacing: 12) {
                                FamilyAvatar(
                                    initial: member.avatar_initial ?? String(member.name.prefix(1)).uppercased(),
                                    size: 36
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.name)
                                        .font(.system(size: 15, weight: .medium))
                                    if let rel = member.relationship {
                                        Text(rel.capitalized)
                                            .font(.system(size: 12))
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
            .navigationTitle("New Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(WarmPalette.ink2)
                }
            }
        }
    }

    private var otherMembers: [APIService.ContactResponse] {
        guard let user = auth.currentUser else { return household.members }
        return household.members.filter {
            $0.name.localizedCaseInsensitiveCompare(user.name) != .orderedSame
            && $0.name.localizedCaseInsensitiveCompare(user.username) != .orderedSame
        }
    }
}
