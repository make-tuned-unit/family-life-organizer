import SwiftUI
import SwiftData

struct AddSpecialEventView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var eventType = "custom"
    @State private var date = Date()
    @State private var isRecurring = true
    @State private var notes = ""

    private let eventTypes = ["birthday", "anniversary", "holiday", "custom"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Event name", text: $title)
                    Picker("Type", selection: $eventType) {
                        ForEach(eventTypes, id: \.self) {
                            Text($0.capitalized)
                        }
                    }
                }

                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Toggle("Repeats annually", isOn: $isRecurring)
                }

                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(2)
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground(style: .gifts) }
            .navigationTitle("Add Event")
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
                    .disabled(title.isEmpty)
                }
            }
        }
    }

    private func save() {
        let event = SpecialEvent(
            title: title,
            date: DateFormatter.monthDay.string(from: date),
            isRecurring: isRecurring,
            eventType: eventType,
            notes: notes.isEmpty ? nil : notes
        )
        modelContext.insert(event)
    }
}

#Preview {
    AddSpecialEventView()
        .modelContainer(for: [SpecialEvent.self])
}
