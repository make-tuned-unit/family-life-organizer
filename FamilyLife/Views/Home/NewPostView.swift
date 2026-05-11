import SwiftUI

struct NewPostView: View {
    @Environment(APIService.self) private var api
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    let onSaved: () async -> Void

    @State private var bodyText = ""
    @State private var groups: [APIService.GroupResponse] = []
    @State private var selectedGroupId: Int?
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What's on your mind?", text: $bodyText, axis: .vertical)
                        .lineLimit(5...10)
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
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(.primary)
                                        Text(groupLabel(group.group_type))
                                            .font(.system(size: 12))
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
            .alert("Couldn't share post", isPresented: errorBinding) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
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

    private func loadGroups() async {
        do {
            groups = try await api.fetchGroups()
            if selectedGroupId == nil {
                selectedGroupId = groups.first?.id
            }
        } catch {
            guard !error.isCancellation else { return }
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

    private var errorBinding: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    }
}

#Preview {
    NewPostView(onSaved: {})
        .environment(APIService())
        .environment(AuthService())
}
