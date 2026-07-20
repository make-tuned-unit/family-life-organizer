import SwiftUI
import MapKit

struct EditAppointmentView: View {
    @Environment(APIService.self) private var api
    @Environment(HouseholdService.self) private var household
    @Environment(AuthService.self) private var auth
    @Environment(CalendarService.self) private var calendarService
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppleCalendarSyncMode.storageKey) private var calendarSyncMode: AppleCalendarSyncMode = .off
    @State private var addToAppleCalendar = false

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
    @State private var recurrence: RecurrenceRule
    @State private var recurrenceEnd: Date?
    @State private var showRecurrenceEnd: Bool
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

        let rule = RecurrenceRule(rawValue: appointment.recurrence_rule ?? "") ?? .none
        _recurrence = State(initialValue: rule)
        let endDate = appointment.recurrence_end.flatMap { DateFormatter.isoDate.date(from: $0) }
        _recurrenceEnd = State(initialValue: endDate)
        _showRecurrenceEnd = State(initialValue: endDate != nil)
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
                                        .font(.flSubheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                    if !result.subtitle.isEmpty {
                                        Text(result.subtitle)
                                            .font(.flCaption)
                                            .foregroundStyle(WarmPalette.ink3)
                                    }
                                }
                            }
                        }
                    }
                }

                Section("Repeat") {
                    Picker(selection: $recurrence) {
                        ForEach(RecurrenceRule.allCases) { rule in
                            Label(rule.displayName, systemImage: rule.icon).tag(rule)
                        }
                    } label: {
                        Label("Repeats", systemImage: "repeat")
                    }

                    if recurrence != .none {
                        Toggle("End date", isOn: $showRecurrenceEnd)
                        if showRecurrenceEnd {
                            DatePicker("Ends on", selection: Binding(
                                get: { recurrenceEnd ?? Calendar.current.date(byAdding: .month, value: 3, to: date)! },
                                set: { recurrenceEnd = $0 }
                            ), in: date..., displayedComponents: .date)
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
                                FamilyAvatar(initial: contact.avatar_initial ?? String(contact.name.prefix(1)).uppercased(), size: 24, name: contact.name)
                                Text(contact.name)
                                    .foregroundStyle(.primary)
                                if let rel = contact.relationship {
                                    Text(rel.capitalized)
                                        .font(.flCaption)
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

                if calendarSyncMode == .ask {
                    Section {
                        Toggle("Add to Apple Calendar", isOn: $addToAppleCalendar)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground(style: .calendar) }
            .onAppear {
                if calendarSyncMode == .ask {
                    addToAppleCalendar = calendarService.isSynced(appointmentId: appointment.id)
                }
            }
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
        if !personTags.isEmpty { data["person_tags"] = personTags.sorted().joined(separator: ",") }
        if recurrence != .none {
            data["recurrence_rule"] = recurrence.rawValue
            if showRecurrenceEnd, let end = recurrenceEnd {
                data["recurrence_end"] = DateFormatter.isoDate.string(from: end)
            }
        } else {
            data["recurrence_rule"] = NSNull()
            data["recurrence_end"] = NSNull()
        }

        Task {
            do {
                try await api.updateAppointment(id: appointment.id, data: data)
                switch calendarSyncMode {
                case .always:
                    await calendarService.syncUpdate(appointmentId: appointment.id, fields: data, shouldSync: true)
                case .ask:
                    await calendarService.syncUpdate(appointmentId: appointment.id, fields: data, shouldSync: addToAppleCalendar)
                case .off:
                    break
                }
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
            person_tags: nil, recurrence_rule: nil, recurrence_end: nil,
            reminder_sent: nil, created_at: nil
        ),
        onSaved: {}
    )
    .environment(APIService())
    .environment(AuthService())
    .environment(HouseholdService())
    .environment(CalendarService())
}
