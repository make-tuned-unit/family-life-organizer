import SwiftUI

struct AddAppointmentView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var date = Date()
    @State private var time = Date()
    @State private var includeTime = true
    @State private var location = ""
    @State private var category = "personal"
    @State private var notes = ""
    @State private var personTags: Set<String> = []

    let onSave: ([String: Any]) -> Void

    private let categories = ["personal", "medical", "school", "daycare"]
    private let familyMembers = ["Jesse", "Sophie", "Rowan", "Jude"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Toggle("Include Time", isOn: $includeTime)
                    if includeTime {
                        DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    }
                }

                Section("Details") {
                    TextField("Location", text: $location)
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3)
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { cat in
                            Text(cat.capitalized).tag(cat)
                        }
                    }
                }

                Section("Who") {
                    ForEach(familyMembers, id: \.self) { member in
                        Button {
                            if personTags.contains(member) {
                                personTags.remove(member)
                            } else {
                                personTags.insert(member)
                            }
                        } label: {
                            HStack {
                                Text(member)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if personTags.contains(member) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.teal)
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground(style: .calendar) }
            .navigationTitle("New Appointment")
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
        var data: [String: Any] = [
            "title": title,
            "appointment_date": DateFormatter.isoDate.string(from: date),
            "category": category
        ]
        if includeTime {
            data["appointment_time"] = DateFormatter.hourMinute.string(from: time)
        }
        if !location.isEmpty {
            data["location"] = location
        }
        if !notes.isEmpty {
            data["description"] = notes
        }
        if !personTags.isEmpty {
            data["person_tags"] = Array(personTags)
        }
        onSave(data)
    }
}

#Preview {
    AddAppointmentView { _ in }
}
