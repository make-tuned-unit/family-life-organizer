import SwiftUI

struct StartRivalryView: View {
    @Environment(APIService.self) private var api
    @Environment(HouseholdService.self) private var household
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    let onSaved: () async -> Void

    @State private var title = ""
    @State private var challengeType: ChallengeType = .steps
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
                                FamilyAvatar(initial: member.avatar_initial ?? String(member.name.prefix(1)).uppercased(), size: 28)
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

                Section("Duration & Points") {
                    DatePicker("End Date", selection: $endDate, in: Date()..., displayedComponents: .date)
                    Stepper("Points: \(pointValue)", value: $pointValue, in: 10...1000, step: 10)
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground(style: .rivalries) }
            .navigationTitle("Start a Rivalry")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Couldn’t start rivalry", isPresented: errorAlertIsPresented) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "An unexpected error occurred.")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Challenge!") {
                        Task { await createRivalry() }
                    }
                    .disabled(title.isEmpty || selectedOpponents.isEmpty || isSaving)
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

    private func updateDefaultTitle() {
        let opponents = selectedOpponents.sorted()
        let isAutoTitle = title.isEmpty
            || title.contains(" vs ")
            || title.hasSuffix("Challenge")
        guard isAutoTitle else { return }
        if opponents.count == 1 {
            title = "\(currentUser) vs \(opponents[0]): \(challengeType.displayName)"
        } else if opponents.count > 1 {
            title = "\(challengeType.displayName) Challenge"
        }
    }

    private func createRivalry() async {
        isSaving = true
        let opponents = selectedOpponents.sorted()
        let allParticipants = [currentUser] + opponents
        do {
            var body: [String: Any] = [
                "title": title,
                "challenge_type": challengeType.rawValue,
                "initiator_name": currentUser,
                "opponent_name": opponents.first ?? "",
                "start_date": ISO8601DateFormatter().string(from: Date()),
                "end_date": ISO8601DateFormatter().string(from: endDate),
                "status": RivalryStatus.active.rawValue,
                "point_value": pointValue
            ]
            if allParticipants.count > 2 {
                // JSON-encode participant list
                if let jsonData = try? JSONEncoder().encode(allParticipants) {
                    body["participants"] = String(data: jsonData, encoding: .utf8) ?? "[]"
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

    private var errorAlertIsPresented: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    }
}

#Preview {
    StartRivalryView(onSaved: {})
        .environment(APIService())
        .environment(AuthService())
        .environment(HouseholdService())
}
