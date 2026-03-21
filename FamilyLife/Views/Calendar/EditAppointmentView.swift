import SwiftUI

struct EditAppointmentView: View {
    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss

    let appointment: AppointmentResponse
    let onSaved: () -> Void

    @State private var title: String
    @State private var date: Date
    @State private var time: Date
    @State private var includeTime: Bool
    @State private var location: String
    @State private var category: String
    @State private var notes: String
    @State private var isSaving = false

    private let categories = ["personal", "medical", "school", "daycare"]

    init(appointment: AppointmentResponse, onSaved: @escaping () -> Void) {
        self.appointment = appointment
        self.onSaved = onSaved

        _title = State(initialValue: appointment.title)
        _date = State(initialValue: DateFormatter.isoDate.date(from: appointment.appointment_date) ?? Date())
        _time = State(initialValue: DateFormatter.hourMinute.date(from: appointment.appointment_time ?? "") ?? Date())
        _includeTime = State(initialValue: appointment.appointment_time != nil)
        _location = State(initialValue: appointment.location ?? "")
        _category = State(initialValue: appointment.category ?? "personal")
        _notes = State(initialValue: appointment.description ?? "")
    }

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
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground(style: .calendar) }
            .navigationTitle("Edit Appointment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(title.isEmpty || isSaving)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        var data: [String: Any] = [
            "title": title,
            "appointment_date": DateFormatter.isoDate.string(from: date),
            "category": category
        ]
        if includeTime {
            data["appointment_time"] = DateFormatter.hourMinute.string(from: time)
        }
        if !location.isEmpty { data["location"] = location }
        if !notes.isEmpty { data["description"] = notes }

        Task {
            do {
                try await api.updateAppointment(id: appointment.id, data: data)
                onSaved()
                dismiss()
            } catch {
                isSaving = false
            }
        }
    }
}

#Preview {
    EditAppointmentView(
        appointment: AppointmentResponse(
            id: 1, title: "Doctor", description: nil,
            appointment_date: "2026-03-25", appointment_time: "10:00",
            location: "Halifax", with_person: nil, category: "medical",
            person_tags: nil, reminder_sent: nil, created_at: nil
        ),
        onSaved: {}
    )
    .environment(APIService())
}
