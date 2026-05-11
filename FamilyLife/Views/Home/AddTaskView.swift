import SwiftUI

struct AddTaskView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth
    @Environment(HouseholdService.self) private var household

    @State private var title = ""
    @State private var category = "household"
    @State private var priority = "medium"
    @State private var assignedTo = "Me"
    @State private var hasDueDate = false
    @State private var dueDate = Date()

    let onSave: ([String: Any]) -> Void

    private let categories = ["household", "errands", "kids", "health", "finance", "work"]
    private let priorities = ["low", "medium", "high"]

    private var familyMembers: [String] {
        var names = [auth.currentUser?.name ?? "Me"]
        names += household.members.map(\.name)
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
    }
}

#Preview {
    AddTaskView { _ in }
        .environment(AuthService())
        .environment(HouseholdService())
}
