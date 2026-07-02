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
                    ProgressView()
                        .padding(.top, 60)
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

                NavigationLink { GiftsView() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "gift.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(AccentTheme.rose.color)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Occasions & gifts overview")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(WarmPalette.ink1)
                            Text("Every upcoming date and idea, across everyone")
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
        VStack(spacing: 10) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 34))
                .foregroundStyle(WarmPalette.ink4)
            Text("Your family's people")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(WarmPalette.ink1)
            Text("Household members appear automatically. Add the kids as dependents to track their milestones, dates, and ideas.")
                .font(.system(size: 13))
                .foregroundStyle(WarmPalette.ink3)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
        .padding(.horizontal, 30)
    }

    private func personCard(_ person: PersonResponse) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(person.accentColor.opacity(0.18))
                    .frame(width: 52, height: 52)
                Text(String(person.name.prefix(1)).uppercased())
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(person.accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(person.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(WarmPalette.ink1)
                    if person.isDependent {
                        Text("Kid")
                            .font(.system(size: 10, weight: .bold))
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
        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private func countBadge(_ icon: String, _ count: Int?) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text("\(count ?? 0)")
                .font(.system(size: 11, weight: .medium))
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
                    Text(error).foregroundStyle(.red).font(.system(size: 13))
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

#Preview {
    NavigationStack { PeopleView() }
        .environment(APIService())
}
