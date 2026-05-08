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
    @State private var addReminder = true
    @State private var isSaving = false
    @State private var error: String?

    let onSave: ([String: Any]) -> Void

    private let categories = ["personal", "medical", "school", "daycare"]
    private let familyMembers = ["Me", "Partner"] // TODO: load from API

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
                                        .foregroundStyle(TabAccent.home.color)
                                }
                            }
                        }
                    }
                }

                Section("Reminder") {
                    Toggle("Notify me before this appointment", isOn: $addReminder)
                    Text("If notifications are unavailable, the appointment still saves and the reminder is skipped.")
                        .font(.caption)
                        .foregroundStyle(WarmPalette.ink3)
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground(style: .calendar) }
            .navigationTitle("New Event")
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
                    .disabled(title.isEmpty || isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
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
        if addReminder {
            let authorized = await NotificationService.shared.ensurePermissionIfNeeded()
            if authorized {
                NotificationService.shared.scheduleAppointmentReminder(
                    id: Int(Date().timeIntervalSince1970),
                    title: title,
                    date: DateFormatter.isoDate.string(from: date),
                    time: includeTime ? DateFormatter.hourMinute.string(from: time) : nil
                )
            }
        }
        isSaving = false
        dismiss()
    }

    private var errorAlertIsPresented: Binding<Bool> {
        Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )
    }
}

#Preview {
    AddAppointmentView { _ in }
}
