import SwiftUI

struct AddTaskView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(APIService.self) private var api
    @Environment(AuthService.self) private var auth
    @Environment(HouseholdService.self) private var household

    @State private var title = ""
    @State private var category = "household"
    @State private var priority = "medium"
    @State private var assignedTo = "Me"
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var shareGroupId: Int?

    let onSave: ([String: Any]) -> Void

    private let categories = ["household", "errands", "kids", "health", "finance", "work"]
    private let priorities = ["low", "medium", "high"]

    // Tasks are household-first: only people in your own household can be assigned.
    // To involve someone in a clan (e.g. Ariel in the Sharratt Clan), use "Share with" below.
    private var familyMembers: [String] {
        let me = auth.currentUser?.name ?? "Me"
        var seen = Set([me.lowercased()])
        var names = [me]
        for member in household.householdMembers where !seen.contains(member.name.lowercased()) {
            seen.insert(member.name.lowercased())
            names.append(member.name)
        }
        return names
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What needs to be done?", text: $title)

                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { cat in
                            Text(cat.capitalized).tag(cat)
                        }
                    }
                }

                Section("Priority") {
                    Picker("Priority", selection: $priority) {
                        ForEach(priorities, id: \.self) { p in
                            HStack {
                                Circle()
                                    .fill(priorityColor(p))
                                    .frame(width: 8, height: 8)
                                Text(p.capitalized)
                            }
                            .tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Assign") {
                    Picker("Assigned to", selection: $assignedTo) {
                        ForEach(familyMembers, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Due Date") {
                    Toggle("Set due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                    }
                }

                ShareWithSection(selectedGroupId: $shareGroupId)
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground(style: .home) }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        save()
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }

    private func priorityColor(_ p: String) -> Color {
        switch p {
        case "high": WarmPalette.bad
        case "medium": AccentTheme.saffron.color
        default: WarmPalette.good
        }
    }

    private func save() {
        var data: [String: Any] = [
            "title": title,
            "category": category,
            "priority": priority,
            "assigned_to": assignedTo.lowercased()
        ]
        if hasDueDate {
            data["due_date"] = DateFormatter.isoDate.string(from: dueDate)
        }
        onSave(data)
        if let groupId = shareGroupId {
            Task {
                _ = try? await api.addFeedPost(groupId: groupId, data: [
                    "post_type": "text",
                    "title": "New task: \(title)",
                    "body": "\(auth.currentUser?.name ?? "Someone") added a task: \(title)"
                ])
            }
        }
    }
}

#Preview {
    AddTaskView { _ in }
        .environment(AuthService())
        .environment(HouseholdService())
}
