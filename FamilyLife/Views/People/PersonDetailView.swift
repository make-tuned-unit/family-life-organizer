import SwiftUI

/// One family member's card: their milestones timeline, gift ideas, key
/// dates, and the decisions the household has tagged to them.
struct PersonDetailView: View {
    @Environment(APIService.self) private var api
    let person: PersonResponse
    var onChanged: (() async -> Void)?

    private enum Tab: String, CaseIterable, Identifiable {
        case milestones = "Milestones"
        case gifts = "Gifts"
        case dates = "Key dates"
        case decisions = "Decisions"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .milestones
    @State private var milestones: [MilestoneResponse] = []
    @State private var decisions: [DecisionResponse] = []
    @State private var keyDates: [SpecialEventResponse] = []
    @State private var showingAddMilestone = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                header

                Picker("Section", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                switch tab {
                case .milestones: milestonesSection
                case .gifts: giftsSection
                case .dates: datesSection
                case .decisions: decisionsSection
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        .background { AmbientBackground(style: .gifts) }
        .navigationTitle(person.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddMilestone) {
            AddMilestoneSheet(person: person) {
                await load()
                await onChanged?()
            }
        }
        .task { await load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(person.accentColor.opacity(0.18))
                    .frame(width: 76, height: 76)
                Text(String(person.name.prefix(1)).uppercased())
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(person.accentColor)
            }
            HStack(spacing: 8) {
                if let rel = person.relationship, rel != "other", rel != "household" {
                    Text(rel.capitalized)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(person.accentColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(person.accentColor.opacity(0.12), in: Capsule())
                }
                if let bday = person.birthday, let date = DateFormatter.isoDate.date(from: bday) {
                    HStack(spacing: 4) {
                        Image(systemName: "birthday.cake.fill").font(.system(size: 10))
                        Text(DateFormatter.longMonthDay.string(from: date))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WarmPalette.ink3)
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Milestones

    private var milestonesSection: some View {
        VStack(spacing: 10) {
            Button { showingAddMilestone = true } label: {
                Label("Add a milestone", systemImage: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(person.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(person.accentColor)
            }
            .buttonStyle(.plain)

            if milestones.isEmpty {
                sectionEmpty("flag.fill", "No milestones yet",
                             "First steps, first goal, lost tooth — log the moments worth remembering.")
            } else {
                ForEach(milestones) { m in
                    milestoneRow(m)
                }
            }
        }
    }

    private func milestoneRow(_ m: MilestoneResponse) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11)
                    .fill(m.categoryEnum.color.opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: m.categoryEnum.icon)
                    .font(.system(size: 15))
                    .foregroundStyle(m.categoryEnum.color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(m.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WarmPalette.ink1)
                if let desc = m.description, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 13))
                        .foregroundStyle(WarmPalette.ink2)
                }
                HStack(spacing: 6) {
                    if let date = DateFormatter.isoDate.date(from: String(m.milestone_date.prefix(10))) {
                        Text(DateFormatter.mediumDisplay.string(from: date))
                    }
                    if let by = m.creator_name {
                        Text("· added by \(by)")
                    }
                }
                .font(.system(size: 11.5))
                .foregroundStyle(WarmPalette.ink3)
            }
            Spacer()
        }
        .padding(13)
        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: 16))
        .contextMenu {
            Button(role: .destructive) {
                Task {
                    try? await api.deleteMilestone(id: m.id)
                    await load()
                    await onChanged?()
                }
            } label: {
                Label("Delete milestone", systemImage: "trash")
            }
        }
    }

    // MARK: - Gifts

    private var giftsSection: some View {
        VStack(spacing: 10) {
            NavigationLink {
                PersonGiftListView(person: person.asGiftPerson)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "gift.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(AccentTheme.rose.color)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Gift ideas for \(person.name)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(WarmPalette.ink1)
                        Text("\(person.gift_idea_count ?? 0) idea\((person.gift_idea_count ?? 0) == 1 ? "" : "s") saved")
                            .font(.system(size: 12))
                            .foregroundStyle(WarmPalette.ink3)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WarmPalette.ink3)
                }
                .padding(14)
                .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Key dates

    private var datesSection: some View {
        VStack(spacing: 10) {
            if let bday = person.birthday, let date = DateFormatter.isoDate.date(from: bday) {
                dateRow("birthday.cake.fill", "Birthday", DateFormatter.longMonthDay.string(from: date), AccentTheme.saffron.color)
            }
            if let ann = person.anniversary, let date = DateFormatter.isoDate.date(from: ann) {
                dateRow("heart.fill", "Anniversary", DateFormatter.longMonthDay.string(from: date), AccentTheme.rose.color)
            }
            ForEach(keyDates) { ev in
                dateRow("calendar", ev.title, ev.date, AccentTheme.ocean.color)
            }
            if person.birthday == nil && person.anniversary == nil && keyDates.isEmpty {
                sectionEmpty("calendar", "No key dates",
                             "Add a birthday when editing this person, or occasions from the Gifts overview.")
            }
        }
    }

    private func dateRow(_ icon: String, _ title: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .frame(width: 30)
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(WarmPalette.ink1)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(WarmPalette.ink3)
        }
        .padding(13)
        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Decisions

    private var decisionsSection: some View {
        VStack(spacing: 10) {
            if decisions.isEmpty {
                sectionEmpty("chart.bar.fill", "Nothing tagged yet",
                             "When you create a decision, tag \(person.name) and it will appear here — the story of what you've talked about for them.")
            } else {
                ForEach(decisions) { d in
                    NavigationLink {
                        DecisionDetailView(decision: d) { await load() }
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(d.title)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(WarmPalette.ink1)
                                    .multilineTextAlignment(.leading)
                                HStack(spacing: 6) {
                                    Text(d.status == "active" ? "Open" : d.status.capitalized)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(d.status == "active" ? AccentTheme.sage.color : WarmPalette.ink3)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2)
                                        .background((d.status == "active" ? AccentTheme.sage.color : WarmPalette.ink4).opacity(0.14), in: Capsule())
                                    Text("by \(d.creator_name)")
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(WarmPalette.ink3)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(WarmPalette.ink3)
                        }
                        .padding(13)
                        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Shared bits

    private func sectionEmpty(_ icon: String, _ title: String, _ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(WarmPalette.ink4)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WarmPalette.ink1)
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(WarmPalette.ink3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 18)
        .background(WarmPalette.cardSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
    }

    private func load() async {
        async let ms = api.fetchMilestones(personId: person.id)
        async let decs = api.fetchPersonDecisions(personId: person.id)
        async let events = api.fetchSpecialEvents()
        milestones = (try? await ms) ?? []
        decisions = (try? await decs) ?? []
        keyDates = ((try? await events) ?? []).filter { $0.person_id == person.id }
    }
}

// MARK: - Add milestone

struct AddMilestoneSheet: View {
    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss
    let person: PersonResponse
    var onSaved: () async -> Void

    @State private var title = ""
    @State private var note = ""
    @State private var date = Date()
    @State private var category: MilestoneCategory = .moment
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("The moment") {
                    TextField("What happened? (e.g. First steps)", text: $title)
                    TextField("A little detail (optional)", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                    DatePicker("When", selection: $date, displayedComponents: .date)
                }
                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(MilestoneCategory.allCases) { c in
                            Label(c.displayName, systemImage: c.icon).tag(c)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section {
                    Text("The household gets a feed post and a nudge to cheer \(person.name) on.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(WarmPalette.ink3)
                }
                if let error {
                    Text(error).foregroundStyle(.red).font(.system(size: 13))
                }
            }
            .navigationTitle("New milestone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        var data: [String: Any] = [
            "person_id": person.id,
            "title": title.trimmingCharacters(in: .whitespaces),
            "milestone_date": DateFormatter.isoDate.string(from: date),
            "category": category.rawValue,
        ]
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNote.isEmpty { data["description"] = trimmedNote }
        Task {
            do {
                try await api.addMilestone(data)
                await onSaved()
                dismiss()
            } catch {
                self.error = "Couldn't save. Try again."
                isSaving = false
            }
        }
    }
}

#Preview {
    NavigationStack {
        PersonDetailView(person: PersonResponse(
            id: 1, name: "Rowan", relationship: "son", birthday: "2019-04-12",
            anniversary: nil, notes: nil, user_id: nil, is_dependent: 1,
            avatar_color: "ocean", created_at: nil, gift_idea_count: 2,
            milestone_count: 3, decision_count: 1, key_date_count: 1))
    }
    .environment(APIService())
}
