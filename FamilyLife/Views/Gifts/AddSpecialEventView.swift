import SwiftUI

struct AddSpecialEventView: View {
    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss

    let onSaved: () async -> Void

    @State private var title = ""
    @State private var eventType = "custom"
    @State private var date = Date()
    @State private var isRecurring = true
    @State private var notes = ""
    @State private var error: String?

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
            .alert("Couldn’t save event", isPresented: errorAlertIsPresented) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "An unexpected error occurred.")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }

    private func save() async {
        do {
            try await api.addSpecialEvent([
                "title": title,
                "date": DateFormatter.monthDay.string(from: date),
                "is_recurring": isRecurring,
                "event_type": eventType,
                "notes": notes.isEmpty ? NSNull() : notes
            ])
            await onSaved()
            dismiss()
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }

    private var errorAlertIsPresented: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    }
}

#Preview {
    AddSpecialEventView(onSaved: {})
        .environment(APIService())
}
