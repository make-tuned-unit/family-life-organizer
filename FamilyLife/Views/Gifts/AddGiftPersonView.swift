import SwiftUI
import SwiftData

struct AddGiftPersonView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var relationship = "other"
    @State private var hasBirthday = false
    @State private var birthdayDate = Date()
    @State private var hasAnniversary = false
    @State private var anniversaryDate = Date()
    @State private var notes = ""

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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }

    private func save() {
        let person = GiftPerson(
            name: name,
            relationship: relationship,
            birthday: hasBirthday ? DateFormatter.monthDay.string(from: birthdayDate) : nil,
            anniversary: hasAnniversary ? DateFormatter.monthDay.string(from: anniversaryDate) : nil,
            notes: notes.isEmpty ? nil : notes
        )
        modelContext.insert(person)

        // Auto-create special events
        if hasBirthday {
            let event = SpecialEvent(
                personID: person.id,
                title: "\(name)'s Birthday",
                date: DateFormatter.monthDay.string(from: birthdayDate),
                eventType: "birthday"
            )
            modelContext.insert(event)
        }
        if hasAnniversary {
            let event = SpecialEvent(
                personID: person.id,
                title: "Anniversary with \(name)",
                date: DateFormatter.monthDay.string(from: anniversaryDate),
                eventType: "anniversary"
            )
            modelContext.insert(event)
        }
    }
}

#Preview {
    AddGiftPersonView()
        .modelContainer(for: [GiftPerson.self, SpecialEvent.self])
}
