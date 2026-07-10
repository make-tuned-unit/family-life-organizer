import SwiftUI

/// A sheet that lets you pick a household member and opens a conversation with a quoted item.
struct SendToSheet: View {
    let quotedItem: QuotedItem
    @Environment(APIService.self) private var api
    @Environment(AuthService.self) private var auth
    @Environment(HouseholdService.self) private var household
    @Environment(ProfileImageCache.self) private var profileCache
    @Environment(\.dismiss) private var dismiss

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
            List {
                Section {
                    QuotedItemCard(type: quotedItem.type, title: quotedItem.title)
                } header: {
                    Text("Sharing")
                }

                Section {
                    ForEach(otherMembers) { member in
                        NavigationLink {
                            ConversationView(
                                partnerId: household.userId(for: member.name) ?? abs(member.id),
                                partnerName: member.name,
                                quotedItem: quotedItem
                            )
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button("Done") { dismiss() }
                                        .foregroundStyle(WarmPalette.ink2)
                                }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                if let img = profileCache.image(for: household.userId(for: member.name) ?? abs(member.id)) {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 36, height: 36)
                                        .clipShape(Circle())
                                } else {
                                    FamilyAvatar(
                                        initial: member.avatar_initial ?? String(member.name.prefix(1)).uppercased(),
                                        size: 36,
                                        name: member.name
                                    )
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.name)
                                        .font(.flSubheadline.weight(.medium))
                                    if let rel = member.relationship {
                                        Text(rel.capitalized)
                                            .font(.flCaption)
                                            .foregroundStyle(WarmPalette.ink3)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("Send to")
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground(style: .home) }
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(WarmPalette.ink2)
                }
            }
        }
    }
}
