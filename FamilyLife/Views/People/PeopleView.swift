import SwiftUI

/// The household's People hub — one card per family member, including
/// dependents (kids without devices). Each card opens the person's detail:
/// milestones, gift ideas, key dates, and decisions tagged to them.
struct PeopleView: View {
    @Environment(APIService.self) private var api

    @State private var people: [PersonResponse] = []
    @State private var householdDates: [SpecialEventResponse] = []
    @State private var isLoading = true
    @State private var showingAddPerson = false
    @State private var assigningDate: SpecialEventResponse?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                if isLoading && people.isEmpty {
                    FLLoadingState(message: "Loading your people…")
                        .padding(.top, 20)
                } else if people.isEmpty {
                    emptyState
                } else {
                    ForEach(people) { person in
                        NavigationLink {
                            PersonDetailView(person: person) { await load() }
                        } label: {
                            personCard(person)
                        }
                        .buttonStyle(.flCardPress)
                    }
                }

                if !householdDates.isEmpty {
                    householdDatesCard
                }

                NavigationLink { YearRecapView() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 15))
                            .foregroundStyle(AccentTheme.saffron.color)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Year in milestones")
                                .font(.flSubheadline.weight(.semibold))
                                .foregroundStyle(WarmPalette.ink1)
                            Text("Everything the family celebrated, year by year")
                                .font(.flCaption)
                                .foregroundStyle(WarmPalette.ink3)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(WarmPalette.ink3)
                    }
                    .padding(14)
                    .flCard()
                }
                .buttonStyle(.flCardPress)
                .padding(.top, 6)
            }
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            .padding(.top, 10)
            .padding(.bottom, 110)
        }
        .background { AmbientBackground(style: .gifts) }
        .navigationTitle("People")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAddPerson = true } label: {
                    Image(systemName: "person.badge.plus")
                }
                .accessibilityLabel("Add person")
                .help("Add person")
            }
        }
        .sheet(isPresented: $showingAddPerson) {
            AddPersonSheet { await load() }
        }
        .sheet(item: $assigningDate) { ev in
            AssignKeyDateSheet(event: ev, people: people) { await load() }
        }
        .task { await load() }
        .onConciergeDataChange { await load() }
    }

    /// Key dates with no person attached (e.g. "Dating anniversary", or one the
    /// Concierge added without linking anyone). Without this section they only
    /// ever appear in the feed and look lost. Tap one to hang it on a person.
    private var householdDatesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 14))
                    .foregroundStyle(AccentTheme.saffron.color)
                Text("Household dates")
                    .font(.flSubheadline.weight(.semibold))
                    .foregroundStyle(WarmPalette.ink1)
                Spacer()
                Text("\(householdDates.count)")
                    .font(.flOverline)
                    .foregroundStyle(WarmPalette.ink3)
            }
            Text("Shared dates not tied to anyone. Tap to attach one to a person.")
                .font(.flCaption)
                .foregroundStyle(WarmPalette.ink3)
            ForEach(householdDates) { ev in
                Button { assigningDate = ev } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ev.title)
                                .font(.flBody)
                                .foregroundStyle(WarmPalette.ink1)
                            Text(keyDateLabel(ev))
                                .font(.flCaption)
                                .foregroundStyle(WarmPalette.ink3)
                        }
                        Spacer()
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 15))
                            .foregroundStyle(WarmPalette.ink3)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .flCard()
    }

    private func keyDateLabel(_ ev: SpecialEventResponse) -> String {
        let recurring = (ev.is_recurring ?? 1) == 1
        guard let date = ISO8601DateFormatter.flexible.date(from: ev.date) else { return ev.date }
        let fmt: Date.FormatStyle = recurring ? .dateTime.month(.abbreviated).day() : .dateTime.month(.abbreviated).day().year()
        return (recurring ? "Every " : "") + date.formatted(fmt)
    }

    private var emptyState: some View {
        WarmEmptyState(
            title: "Your family's people",
            systemImage: "person.2",
            description: "Household members appear automatically. Add the kids as dependents to track their milestones, dates, and ideas.",
            actionLabel: "Add a person",
            action: { showingAddPerson = true }
        )
    }

    private func personCard(_ person: PersonResponse) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(person.accentColor.opacity(0.18))
                    .frame(width: 52, height: 52)
                Text(String(person.name.prefix(1)).uppercased())
                    .font(.flTitle)
                    .foregroundStyle(person.accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(person.name)
                        .font(.flHeadline)
                        .foregroundStyle(WarmPalette.ink1)
                    if person.isDependent {
                        Text("Kid")
                            .font(.flOverline.weight(.bold))
                            .foregroundStyle(person.accentColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(person.accentColor.opacity(0.14), in: Capsule())
                    }
                }
                HStack(spacing: 10) {
                    countBadge("flag.fill", person.milestone_count)
                    countBadge("gift.fill", person.gift_idea_count)
                    countBadge("calendar", person.key_date_count)
                    countBadge("chart.bar.fill", person.decision_count)
                }
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WarmPalette.ink3)
        }
        .padding(14)
        .flCard()
    }

    @ViewBuilder
    private func countBadge(_ icon: String, _ count: Int?) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text("\(count ?? 0)")
                .font(.flOverline)
        }
        .foregroundStyle(WarmPalette.ink3)
    }

    private func load() async {
        async let dates = api.fetchSpecialEvents()
        do {
            people = try await api.fetchPeople()
        } catch {
            // Non-fatal: keep whatever we had; the empty state covers first load.
        }
        householdDates = ((try? await dates) ?? [])
            .filter { $0.person_id == nil }
            .sorted { $0.date < $1.date }
        isLoading = false
    }
}

// MARK: - Add dependent / person

struct AddPersonSheet: View {
    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss
    var onSaved: () async -> Void

    @State private var name = ""
    @State private var relationship = "son"
    @State private var hasBirthday = false
    @State private var birthday = Date()
    @State private var avatarColor = "sage"
    @State private var isSaving = false
    @State private var error: String?

    private let relationships = ["son", "daughter", "partner", "parent", "grandparent", "other"]
    private let colors = ["sage", "rose", "ocean", "saffron", "mauve", "terracotta"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Who are they?") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    Picker("Relationship", selection: $relationship) {
                        ForEach(relationships, id: \.self) { Text($0.capitalized) }
                    }
                }
                Section("Birthday") {
                    Toggle("Add a birthday", isOn: $hasBirthday)
                    if hasBirthday {
                        DatePicker("Birthday", selection: $birthday, displayedComponents: .date)
                    }
                }
                Section("Color") {
                    HStack(spacing: 12) {
                        ForEach(colors, id: \.self) { c in
                            Circle()
                                .fill((AccentTheme(rawValue: c) ?? .sage).color)
                                .frame(width: 30, height: 30)
                                .overlay {
                                    if avatarColor == c {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .onTapGesture { avatarColor = c }
                        }
                    }
                }
            }
            .navigationTitle("Add a person")
            .navigationBarTitleDisplayMode(.inline)
            .inlineError(error) { error = nil }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Add") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        var data: [String: Any] = [
            "name": name.trimmingCharacters(in: .whitespaces),
            "relationship": relationship,
            "is_dependent": true,
            "avatar_color": avatarColor,
        ]
        if hasBirthday { data["birthday"] = DateFormatter.isoDate.string(from: birthday) }
        Task {
            do {
                try await api.addPerson(data)
                await onSaved()
                dismiss()
            } catch {
                self.error = "Couldn't save. Try again."
                isSaving = false
            }
        }
    }
}

// MARK: - Year in milestones

/// The family's year, told through its milestones — grouped by person,
/// switchable by year. The seed of the year-end recap.
struct YearRecapView: View {
    @Environment(APIService.self) private var api

    @State private var milestones: [MilestoneResponse] = []
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var isLoading = true

    private var years: [Int] {
        let ys = Set(milestones.compactMap { Int($0.milestone_date.prefix(4)) })
        return ys.sorted(by: >)
    }

    private var yearMilestones: [MilestoneResponse] {
        milestones
            .filter { Int($0.milestone_date.prefix(4)) == selectedYear }
            .sorted { $0.milestone_date < $1.milestone_date }
    }

    private var byPerson: [(name: String, items: [MilestoneResponse])] {
        let groups = Dictionary(grouping: yearMilestones) { $0.person_name ?? "Someone" }
        return groups.map { (name: $0.key, items: $0.value) }
            .sorted { $0.items.count == $1.items.count ? $0.name < $1.name : $0.items.count > $1.items.count }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                if !years.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(years, id: \.self) { y in
                                WarmChip(label: String(y), isActive: selectedYear == y) {
                                    selectedYear = y
                                }
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }

                if isLoading && milestones.isEmpty {
                    FLLoadingState(message: "Loading milestones…")
                        .padding(.top, 20)
                } else if yearMilestones.isEmpty {
                    WarmEmptyState(
                        title: "Make \(String(selectedYear)) a year to remember",
                        systemImage: "sparkles",
                        description: "Log the family's moments from each person's card, and this page becomes the story of your year."
                    )
                } else {
                    HStack {
                        Text("\(yearMilestones.count) moment\(yearMilestones.count == 1 ? "" : "s") in \(String(selectedYear))")
                            .font(.flFootnote.weight(.semibold))
                            .foregroundStyle(WarmPalette.ink3)
                        Spacer()
                    }

                    ForEach(byPerson, id: \.name) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Text(group.name)
                                    .font(.flHeadline)
                                    .foregroundStyle(WarmPalette.ink1)
                                Text("\(group.items.count)")
                                    .font(.flOverline.weight(.bold))
                                    .foregroundStyle(AccentTheme.saffron.color)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(AccentTheme.saffron.color.opacity(0.14), in: Capsule())
                                Spacer()
                            }
                            ForEach(group.items) { m in
                                HStack(spacing: 11) {
                                    Image(systemName: m.categoryEnum.icon)
                                        .font(.system(size: 13))
                                        .foregroundStyle(m.categoryEnum.color)
                                        .frame(width: 26)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(m.title)
                                            .font(.flSubheadline.weight(.semibold))
                                            .foregroundStyle(WarmPalette.ink1)
                                        if let date = DateFormatter.isoDate.date(from: String(m.milestone_date.prefix(10))) {
                                            Text(DateFormatter.longMonthDay.string(from: date))
                                                .font(.flCaption)
                                                .foregroundStyle(WarmPalette.ink3)
                                        }
                                    }
                                    Spacer()
                                    if let b64 = m.photo_data, let data = Data(base64Encoded: b64), let img = UIImage(data: data) {
                                        Image(uiImage: img)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 40, height: 40)
                                            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small))
                                    }
                                }
                                .padding(11)
                                .flCard()
                            }
                        }
                        .padding(.top, 6)
                    }
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            .padding(.top, 10)
            .padding(.bottom, 110)
        }
        .background { AmbientBackground(style: .gifts) }
        .navigationTitle("Year in milestones")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            milestones = (try? await api.fetchMilestones()) ?? []
            if let latest = years.first, yearMilestones.isEmpty { selectedYear = latest }
            isLoading = false
        }
    }
}

#Preview {
    NavigationStack { PeopleView() }
        .environment(APIService())
}


/// Attach a household-wide key date to a person so it shows on their card.
struct AssignKeyDateSheet: View {
    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss

    let event: SpecialEventResponse
    let people: [PersonResponse]
    let onSaved: () async -> Void

    @State private var selected: Int?
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(event.title).font(.flHeadline)
                } header: {
                    Text("Key date")
                } footer: {
                    Text("Pick whose date this is. It will move from Household dates onto their People card and reminders will mention them.")
                }
                Section("Who is it for?") {
                    ForEach(people) { person in
                        Button {
                            selected = person.id
                        } label: {
                            HStack {
                                FamilyAvatar(initial: String(person.name.prefix(1)), size: 28, name: person.name)
                                Text(person.name).foregroundStyle(WarmPalette.ink1)
                                Spacer()
                                if selected == person.id {
                                    Image(systemName: "checkmark").foregroundStyle(AccentTheme.sage.color)
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground(style: .gifts) }
            .navigationTitle("Attach to person")
            .navigationBarTitleDisplayMode(.inline)
            .inlineError(error) { error = nil }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Attach") { save() }.disabled(selected == nil || isSaving)
                }
            }
        }
    }

    private func save() {
        guard let selected else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await api.updateSpecialEvent(id: event.id, data: ["person_id": selected])
                await onSaved()
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

#Preview("Assign key date") {
    AssignKeyDateSheet(
        event: SpecialEventResponse(id: 1, person_id: nil, title: "Rowan violin anniversary", date: "2026-09-01",
                                    is_recurring: 1, event_type: "custom", notes: nil, shared_scope: nil, created_by: nil, created_at: nil),
        people: [PersonResponse(id: 1, name: "Rowan", relationship: "son", birthday: nil, anniversary: nil, notes: nil,
                                user_id: nil, is_dependent: 1, avatar_color: nil, created_at: nil,
                                gift_idea_count: 0, milestone_count: 0, decision_count: 0, key_date_count: 0)]
    ) {}
    .environment(APIService())
}
