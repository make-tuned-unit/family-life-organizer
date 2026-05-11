import SwiftUI
import MapKit

struct EditAppointmentView: View {
    @Environment(APIService.self) private var api
    @Environment(HouseholdService.self) private var household
    @Environment(AuthService.self) private var auth
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
    @State private var personTags: Set<String>
    @State private var isSaving = false
    @State private var locationCompleter = LocationCompleter()
    @State private var showingLocationSuggestions = false

    private let categories = ["personal", "medical", "school", "daycare", "work", "social"]

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

        let tags = appointment.person_tags?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? []
        _personTags = State(initialValue: Set(tags))
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

                Section("Location") {
                    TextField("Search for a place...", text: $location)
                        .onChange(of: location) {
                            locationCompleter.search(query: location)
                            showingLocationSuggestions = !location.isEmpty
                        }

                    if showingLocationSuggestions && !locationCompleter.results.isEmpty {
                        ForEach(locationCompleter.results, id: \.self) { result in
                            Button {
                                location = [result.title, result.subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
                                showingLocationSuggestions = false
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.title)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                    if !result.subtitle.isEmpty {
                                        Text(result.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(WarmPalette.ink3)
                                    }
                                }
                            }
                        }
                    }
                }

                Section("Who's involved") {
                    Button {
                        toggleTag(auth.currentUser?.name ?? "Me")
                    } label: {
                        HStack {
                            Text("Me")
                                .foregroundStyle(.primary)
                            Spacer()
                            if personTags.contains(auth.currentUser?.name ?? "Me") {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(TabAccent.home.color)
                            }
                        }
                    }

                    ForEach(household.members) { contact in
                        Button {
                            toggleTag(contact.name)
                        } label: {
                            HStack {
                                FamilyAvatar(initial: contact.avatar_initial ?? String(contact.name.prefix(1)).uppercased(), size: 24)
                                Text(contact.name)
                                    .foregroundStyle(.primary)
                                if let rel = contact.relationship {
                                    Text(rel.capitalized)
                                        .font(.caption)
                                        .foregroundStyle(WarmPalette.ink3)
                                }
                                Spacer()
                                if personTags.contains(contact.name) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(TabAccent.home.color)
                                }
                            }
                        }
                    }
                }

                Section("Details") {
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

    private func toggleTag(_ name: String) {
        if personTags.contains(name) { personTags.remove(name) }
        else { personTags.insert(name) }
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
        if !personTags.isEmpty { data["person_tags"] = Array(personTags) }

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
    .environment(AuthService())
    .environment(HouseholdService())
}
