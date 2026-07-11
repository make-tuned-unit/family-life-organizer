import SwiftUI

/// The household's People hub — one card per family member, including
/// dependents (kids without devices). Each card opens the person's detail:
/// milestones, gift ideas, key dates, and decisions tagged to them.
struct PeopleView: View {
    @Environment(APIService.self) private var api

    @State private var people: [PersonResponse] = []
    @State private var isLoading = true
    @State private var showingAddPerson = false

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
                        .buttonStyle(.plain)
                    }
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
                .buttonStyle(.plain)
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
            }
        }
        .sheet(isPresented: $showingAddPerson) {
            AddPersonSheet { await load() }
        }
        .task { await load() }
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
        do {
            people = try await api.fetchPeople()
        } catch {
            // Non-fatal: keep whatever we had; the empty state covers first load.
        }
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
                if let error {
                    Text(error).foregroundStyle(.red).font(.flFootnote)
                }
            }
            .navigationTitle("Add a person")
            .navigationBarTitleDisplayMode(.inline)
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
                                            .clipShape(RoundedRectangle(cornerRadius: 9))
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
