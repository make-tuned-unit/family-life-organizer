import SwiftUI

struct ShareWithSection: View {
    @Binding var selectedGroupId: Int?
    @State private var groups: [APIService.GroupResponse] = []
    @Environment(APIService.self) private var api

    var body: some View {
        Section {
            if groups.isEmpty {
                Text("Loading groups...")
                    .font(.caption)
                    .foregroundStyle(WarmPalette.ink3)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // "None" chip
                        Button {
                            withAnimation(.spring(response: 0.25)) { selectedGroupId = nil }
                        } label: {
                            Text("None")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(selectedGroupId == nil ? WarmPalette.cream1 : WarmPalette.ink2)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    selectedGroupId == nil
                                        ? AnyShapeStyle(WarmPalette.ink2)
                                        : AnyShapeStyle(WarmPalette.ink1.opacity(0.06)),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)

                        ForEach(groups) { group in
                            Button {
                                withAnimation(.spring(response: 0.25)) {
                                    selectedGroupId = group.id
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: groupIcon(group.group_type))
                                        .font(.system(size: 11))
                                    Text(group.name)
                                        .font(.system(size: 13, weight: .medium))
                                }
                                .foregroundStyle(selectedGroupId == group.id ? WarmPalette.cream1 : WarmPalette.ink2)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    selectedGroupId == group.id
                                        ? AnyShapeStyle(groupColor(group.group_type))
                                        : AnyShapeStyle(WarmPalette.ink1.opacity(0.06)),
                                    in: Capsule()
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        } header: {
            Text("Share with")
        } footer: {
            Text(selectedGroupId != nil ? "A post will appear in the group's feed." : "Optional — select a circle to announce this.")
        }
        .task {
            do { groups = try await api.fetchGroups() } catch {}
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
