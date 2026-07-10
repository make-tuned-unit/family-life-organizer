import SwiftUI

struct NewPostView: View {
    @Environment(APIService.self) private var api
    @Environment(AuthService.self) private var auth
    @Environment(HouseholdService.self) private var household
    @Environment(\.dismiss) private var dismiss

    let onSaved: () async -> Void

    @State private var bodyText = ""
    @State private var groups: [APIService.GroupResponse] = []
    @State private var selectedGroupId: Int?
    @State private var isSaving = false
    @State private var error: String?
    @State private var mentionSuggestions: [APIService.ContactResponse] = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 0) {
                        TextField("What's on your mind?", text: $bodyText, axis: .vertical)
                            .lineLimit(5...10)
                            .onChange(of: bodyText) { updateMentionSuggestions() }

                        if !mentionSuggestions.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(mentionSuggestions, id: \.name) { member in
                                    Button { insertMention(member.name) } label: {
                                        HStack(spacing: 8) {
                                            FamilyAvatar(
                                                initial: member.avatar_initial ?? String(member.name.prefix(1)).uppercased(),
                                                size: 24,
                                                name: member.name
                                            )
                                            Text(member.name)
                                                .font(.flSubheadline.weight(.medium))
                                                .foregroundStyle(WarmPalette.ink1)
                                        }
                                        .padding(.vertical, 6)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                }

                Section("Share with") {
                    if groups.isEmpty {
                        Text("No groups yet — create one in Family tab")
                            .font(.caption)
                            .foregroundStyle(WarmPalette.ink3)
                    } else {
                        ForEach(groups) { group in
                            Button {
                                selectedGroupId = group.id
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: groupIcon(group.group_type))
                                        .foregroundStyle(groupColor(group.group_type))
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(group.name)
                                            .font(.flSubheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                        Text(groupLabel(group.group_type))
                                            .font(.flCaption)
                                            .foregroundStyle(WarmPalette.ink3)
                                    }
                                    Spacer()
                                    if selectedGroupId == group.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(TabAccent.home.color)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground(style: .home) }
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
            .inlineError(error) { error = nil }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(WarmPalette.ink2)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") {
                        Task { await save() }
                    }
                    .disabled(bodyText.trimmingCharacters(in: .whitespaces).isEmpty || selectedGroupId == nil || isSaving)
                }
            }
            .task { await loadGroups() }
        }
    }

    // MARK: - @mention autocomplete

    private func updateMentionSuggestions() {
        guard let atRange = bodyText.range(of: "@", options: .backwards) else {
            mentionSuggestions = []
            return
        }
        let afterAt = String(bodyText[atRange.upperBound...])
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
        guard let atRange = bodyText.range(of: "@", options: .backwards) else { return }
        bodyText = String(bodyText[..<atRange.lowerBound]) + "@\(name) "
        mentionSuggestions = []
    }

    // MARK: - Data

    private func loadGroups() async {
        do {
            groups = try await api.fetchGroups()
            if selectedGroupId == nil {
                selectedGroupId = groups.first?.id
            }
        } catch {
            guard !error.isCancellation else { return }
            // Without a group the Post button is a silent no-op — say why.
            self.error = "Couldn't load your groups — \(error.localizedDescription)"
        }
    }

    private func save() async {
        guard let groupId = selectedGroupId else { return }
        isSaving = true
        do {
            let data: [String: Any] = [
                "post_type": "text",
                "title": String(bodyText.prefix(60)),
                "body": bodyText
            ]
            let _ = try await api.addFeedPost(groupId: groupId, data: data)
            await onSaved()
            dismiss()
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
            isSaving = false
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

    private func groupLabel(_ type: String) -> String {
        switch type {
        case "household": "Your household"
        case "family": "Your family circle"
        case "tribe": "Extended network"
        default: "Group"
        }
    }
}

#Preview {
    NewPostView(onSaved: {})
        .environment(APIService())
        .environment(AuthService())
        .environment(HouseholdService())
}
