import SwiftUI

struct StartRivalryView: View {
    @Environment(APIService.self) private var api
    @Environment(HouseholdService.self) private var household
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    let onSaved: () async -> Void

    @State private var title = ""
    @State private var challengeType: ChallengeType = .steps
    @State private var isTeamMode = false
    @State private var teamA: Set<String> = []   // your team (includes you)
    @State private var teamB: Set<String> = []   // their team
    @State private var selectedOpponents: Set<String> = []
    @State private var endDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date().addingTimeInterval(7 * 86400)
    @State private var pointValue = 100
    @State private var error: String?
    @State private var isSaving = false

    private var currentUser: String { auth.currentUser?.name ?? "Me" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Rivalry title", text: $title)
                        .onAppear { updateDefaultTitle() }
                }

                Section("Challenge Type") {
                    ForEach(ChallengeType.allCases) { type in
                        Button {
                            challengeType = type
                            updateDefaultTitle()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: type.icon)
                                    .frame(width: 28)
                                    .foregroundStyle(typeColor(type))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(type.displayName)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                    if type != .custom {
                                        Text(type.hint)
                                            .font(.caption)
                                            .foregroundStyle(WarmPalette.ink3)
                                    }
                                }
                                Spacer()
                                if challengeType == type {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(TabAccent.home.color)
                                }
                            }
                        }
                    }
                }

                Section("Format") {
                    Picker("Type", selection: $isTeamMode) {
                        Text("1-on-1 / Free-for-all").tag(false)
                        Text("Teams").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: isTeamMode) { _, team in
                        if team { teamA.insert(currentUser) }
                        updateDefaultTitle()
                    }
                }

                if !isTeamMode {
                    Section(selectedOpponents.count <= 1 ? "Opponent" : "Opponents (\(selectedOpponents.count))") {
                        ForEach(household.members) { member in
                            Button {
                                if selectedOpponents.contains(member.name) {
                                    selectedOpponents.remove(member.name)
                                } else {
                                    selectedOpponents.insert(member.name)
                                }
                                updateDefaultTitle()
                            } label: {
                                HStack {
                                    FamilyAvatar(initial: member.avatar_initial ?? String(member.name.prefix(1)).uppercased(), size: 28, name: member.name)
                                    Text(member.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if selectedOpponents.contains(member.name) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(TabAccent.home.color)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundStyle(WarmPalette.ink4)
                                    }
                                }
                            }
                        }
                        if household.members.isEmpty {
                            Text("Add family members in Settings to challenge them")
                                .font(.caption)
                                .foregroundStyle(WarmPalette.ink3)
                        }
                    }
                } else {
                    Section {
                        Button("Add my whole household to my team") {
                            teamA.insert(currentUser)
                            for name in allPeople where household.householdMemberNames.contains(name.lowercased()) {
                                teamA.insert(name); teamB.remove(name)
                            }
                            updateDefaultTitle()
                        }
                        .font(.subheadline)
                        ForEach(allPeople, id: \.self) { name in
                            teamPickRow(name)
                        }
                    } header: {
                        Text("Your team (\(teamA.count)) vs Their team (\(teamB.count))")
                    } footer: {
                        Text("Tap a name to put them on your team, tap again for their team, again to clear.")
                    }
                }

                Section("Duration & Points") {
                    DatePicker("End Date", selection: $endDate, in: Date()..., displayedComponents: .date)
                    Stepper("Points: \(pointValue)", value: $pointValue, in: 10...1000, step: 10)
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground(style: .rivalries) }
            .navigationTitle("Start a Rivalry")
            .navigationBarTitleDisplayMode(.inline)
            .inlineError(error) { error = nil }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Challenge!") {
                        Task { await createRivalry() }
                    }
                    .disabled(title.isEmpty || isSaving || (isTeamMode ? (teamA.isEmpty || teamB.isEmpty) : selectedOpponents.isEmpty))
                }
            }
        }
    }

    private func typeColor(_ type: ChallengeType) -> Color {
        switch type {
        case .steps, .stairs: AccentTheme.ocean.color
        case .workout, .pushups, .squats, .situps, .plank: AccentTheme.saffron.color
        case .running: AccentTheme.ocean.color
        case .habit: WarmPalette.good
        case .custom: AccentTheme.mauve.color
        }
    }

    /// People available to place on teams — the current user plus household/clan members.
    private var allPeople: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for name in [currentUser] + household.members.map(\.name) {
            let key = name.lowercased()
            if !seen.contains(key) { seen.insert(key); out.append(name) }
        }
        return out
    }

    @ViewBuilder
    private func teamPickRow(_ name: String) -> some View {
        let inA = teamA.contains(name)
        let inB = teamB.contains(name)
        Button {
            if inA { teamA.remove(name); teamB.insert(name) }
            else if inB { teamB.remove(name) }
            else { teamA.insert(name); teamB.remove(name) }
            updateDefaultTitle()
        } label: {
            HStack {
                FamilyAvatar(initial: String(name.prefix(1)).uppercased(), size: 28, name: name)
                Text(name).foregroundStyle(.primary)
                Spacer()
                if inA {
                    Text("Your team").font(.caption.weight(.semibold)).foregroundStyle(AccentTheme.ocean.color)
                } else if inB {
                    Text("Their team").font(.caption.weight(.semibold)).foregroundStyle(AccentTheme.terracotta.color)
                } else {
                    Image(systemName: "circle").foregroundStyle(WarmPalette.ink4)
                }
            }
        }
    }

    private func updateDefaultTitle() {
        let isAutoTitle = title.isEmpty
            || title.contains(" vs ")
            || title.hasSuffix("Challenge")
        guard isAutoTitle else { return }
        if isTeamMode {
            title = "Team \(challengeType.displayName) Challenge"
            return
        }
        let opponents = selectedOpponents.sorted()
        if opponents.count == 1 {
            title = "\(currentUser) vs \(opponents[0]): \(challengeType.displayName)"
        } else if opponents.count > 1 {
            title = "\(challengeType.displayName) Challenge"
        }
    }

    private func jsonString(_ names: [String]) -> String {
        guard let data = try? JSONEncoder().encode(names) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private func createRivalry() async {
        isSaving = true
        do {
            var body: [String: Any] = [
                "title": title,
                "challenge_type": challengeType.rawValue,
                "initiator_name": currentUser,
                "start_date": ISO8601DateFormatter().string(from: Date()),
                "end_date": ISO8601DateFormatter().string(from: endDate),
                "status": RivalryStatus.active.rawValue,
                "point_value": pointValue
            ]

            if isTeamMode {
                let teamANames = teamA.sorted()
                let teamBNames = teamB.sorted()
                body["rivalry_type"] = "team"
                body["team_a"] = jsonString(teamANames)
                body["team_b"] = jsonString(teamBNames)
                body["opponent_name"] = teamBNames.first ?? ""
                body["participants"] = jsonString(teamANames + teamBNames)
            } else {
                let opponents = selectedOpponents.sorted()
                let allParticipants = [currentUser] + opponents
                body["opponent_name"] = opponents.first ?? ""
                if allParticipants.count > 2 {
                    body["participants"] = jsonString(allParticipants)
                }
            }

            try await api.addRivalry(body)
            await onSaved()
            dismiss()
        } catch let err {
            guard !err.isCancellation else { return }
            self.error = err.localizedDescription
            isSaving = false
        }
    }

}

#Preview {
    StartRivalryView(onSaved: {})
        .environment(APIService())
        .environment(AuthService())
        .environment(HouseholdService())
}
