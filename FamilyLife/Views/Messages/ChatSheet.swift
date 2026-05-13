import SwiftUI

struct ChatSheet: View {
    @Environment(APIService.self) private var api
    @Environment(AuthService.self) private var auth
    @Environment(HouseholdService.self) private var household
    @Environment(ProfileImageCache.self) private var profileCache
    @Environment(\.dismiss) private var dismiss

    @State private var conversations: [APIService.ConversationResponse] = []
    @State private var selectedPartnerId: Int?
    @State private var selectedPartnerName: String?

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
                // Person picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(otherMembers) { member in
                            let partnerId = abs(member.id)
                            let isSelected = selectedPartnerId == partnerId
                            let unread = conversations.first { $0.partner_id == partnerId }?.unread_count ?? 0
                            Button {
                                selectedPartnerId = partnerId
                                selectedPartnerName = member.name
                            } label: {
                                VStack(spacing: 4) {
                                    ZStack(alignment: .topTrailing) {
                                        if let img = profileCache.image(for: partnerId) {
                                            Image(uiImage: img)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 44, height: 44)
                                                .clipShape(Circle())
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
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 4)
                                .background(
                                    isSelected ? TabAccent.home.color.opacity(0.1) : .clear,
                                    in: RoundedRectangle(cornerRadius: 12)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 8)
                .background(WarmPalette.cardSurface)

                Divider()

                // Conversation area
                if let partnerId = selectedPartnerId, let partnerName = selectedPartnerName {
                    ConversationView(partnerId: partnerId, partnerName: partnerName)
                } else {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                            .font(.system(size: 32))
                            .foregroundStyle(WarmPalette.ink4)
                        Text("Select someone to chat with")
                            .font(.system(size: 14))
                            .foregroundStyle(WarmPalette.ink3)
                    }
                    Spacer()
                }
            }
            .background { AmbientBackground(style: .home) }
            .navigationTitle("Messages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(WarmPalette.ink2)
                }
            }
            .task {
                conversations = (try? await api.fetchConversations()) ?? []
                // Auto-select first person with unread, or first member
                if selectedPartnerId == nil {
                    if let unread = conversations.first(where: { $0.unread_count > 0 }) {
                        selectedPartnerId = unread.partner_id
                        selectedPartnerName = unread.partner_name
                    } else if let first = otherMembers.first {
                        selectedPartnerId = abs(first.id)
                        selectedPartnerName = first.name
                    }
                }
            }
        }
    }
}
