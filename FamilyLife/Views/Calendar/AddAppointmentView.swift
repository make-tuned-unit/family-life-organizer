import SwiftUI
import MapKit

struct AddAppointmentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(APIService.self) private var api
    @Environment(HouseholdService.self) private var household

    var initialDate: Date?

    @State private var title = ""
    @State private var date = Date()
    @State private var time = Date()
    @State private var includeTime = true
    @State private var location = ""
    @State private var category = "personal"
    @State private var notes = ""
    @State private var personTags: Set<String> = []
    @State private var recurrence: RecurrenceRule = .none
    @State private var recurrenceEnd: Date? = nil
    @State private var showRecurrenceEnd = false
    @State private var addReminder = true
    @AppStorage(AppleCalendarSyncMode.storageKey) private var calendarSyncMode: AppleCalendarSyncMode = .off
    @State private var addToAppleCalendar = true
    @State private var shareGroupId: Int?
    @State private var isSaving = false
    @State private var error: String?

    // Location autocomplete
    @State private var locationCompleter = LocationCompleter()
    @State private var showingLocationSuggestions = false

    // Family contacts from shared household

    let onSave: ([String: Any], Bool) -> Void

    private let categories = ["personal", "medical", "school", "daycare", "work", "social"]

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

                Section("Details") {
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3)
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { cat in
                            Text(cat.capitalized).tag(cat)
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
                    // Current user
                    Button {
                        toggleTag("Me")
                    } label: {
                        HStack {
                            Text("Me")
                                .foregroundStyle(.primary)
                            Spacer()
                            if personTags.contains("Me") {
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

                ShareWithSection(selectedGroupId: $shareGroupId)

                Section("Reminder") {
                    Toggle("Notify me before this event", isOn: $addReminder)
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
                if let d = initialDate { date = d }
            }
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .inlineError(error) { error = nil }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(WarmPalette.ink2)
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

    private func toggleTag(_ name: String) {
        if personTags.contains(name) { personTags.remove(name) }
        else { personTags.insert(name) }
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
        if !location.isEmpty { data["location"] = location }
        if !notes.isEmpty { data["description"] = notes }
        if !personTags.isEmpty { data["person_tags"] = personTags.sorted().joined(separator: ",") }
        if recurrence != .none {
            data["recurrence_rule"] = recurrence.rawValue
            if showRecurrenceEnd, let end = recurrenceEnd {
                data["recurrence_end"] = DateFormatter.isoDate.string(from: end)
            }
        }

        let syncToApple = calendarSyncMode == .always || (calendarSyncMode == .ask && addToAppleCalendar)
        onSave(data, syncToApple)
        if let groupId = shareGroupId {
            let dateStr = date.formatted(date: .abbreviated, time: .omitted)
            let timeStr = includeTime ? " at \(DateFormatter.hourMinute.string(from: time))" : ""
            var eventBody = "\(dateStr)\(timeStr)"
            if !location.isEmpty { eventBody += "\n\(location)" }
            if !personTags.isEmpty { eventBody += "\nWith \(personTags.sorted().joined(separator: ", "))" }
            if recurrence != .none { eventBody += "\nRepeats \(recurrence.rawValue)" }
            _ = try? await api.addFeedPost(groupId: groupId, data: [
                "post_type": "event",
                "title": "New event: \(title)",
                "body": eventBody
            ])
        }
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
}

// MARK: - Location Autocomplete using MapKit

@MainActor
@Observable
final class LocationCompleter: NSObject, MKLocalSearchCompleterDelegate {
    var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func search(query: String) {
        completer.queryFragment = query
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let r = Array(completer.results.prefix(5))
        Task { @MainActor in results = r }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in results = [] }
    }
}

#Preview {
    AddAppointmentView { _, _ in }
        .environment(APIService())
        .environment(HouseholdService())
}
