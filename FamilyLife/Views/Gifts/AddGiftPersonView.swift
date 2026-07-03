import SwiftUI

struct AddGiftPersonView: View {
    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss

    let onSaved: () async -> Void

    @State private var name = ""
    @State private var relationship = "other"
    @State private var hasBirthday = false
    @State private var birthdayDate = Date()
    @State private var hasAnniversary = false
    @State private var anniversaryDate = Date()
    @State private var notes = ""
    @State private var error: String?

    private let relationships = ["spouse", "child", "parent", "sibling", "friend", "other"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    Picker("Relationship", selection: $relationship) {
                        ForEach(relationships, id: \.self) {
                            Text($0.capitalized)
                        }
                    }
                }

                Section("Birthday") {
                    Toggle("Has birthday", isOn: $hasBirthday)
                    if hasBirthday {
                        DatePicker("Date", selection: $birthdayDate, displayedComponents: .date)
                    }
                }

                Section("Anniversary") {
                    Toggle("Has anniversary", isOn: $hasAnniversary)
                    if hasAnniversary {
                        DatePicker("Date", selection: $anniversaryDate, displayedComponents: .date)
                    }
                }

                Section("Notes") {
                    TextField("Sizes, preferences, dislikes...", text: $notes, axis: .vertical)
                        .lineLimit(3)
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground(style: .gifts) }
            .navigationTitle("Add Person")
            .navigationBarTitleDisplayMode(.inline)
            .inlineError(error) { error = nil }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }

    private func save() async {
        do {
            try await api.addGiftPerson([
                "name": name,
                "relationship": relationship,
                "birthday": hasBirthday ? DateFormatter.monthDay.string(from: birthdayDate) : NSNull(),
                "anniversary": hasAnniversary ? DateFormatter.monthDay.string(from: anniversaryDate) : NSNull(),
                "notes": notes.isEmpty ? NSNull() : notes
            ])
            await onSaved()
            dismiss()
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }
}

#Preview {
    AddGiftPersonView(onSaved: {})
        .environment(APIService())
}
