import SwiftUI
import SwiftData

struct StartRivalryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var challengeType: ChallengeType = .steps
    @State private var opponentName = "Sophie"
    @State private var endDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date().addingTimeInterval(7 * 86400)
    @State private var pointValue = 100
    @State private var startError: String?

    private let familyMembers = ["Jesse", "Sophie", "Rowan", "Jude"]
    private let currentUser = "Jesse" // From AuthService in real usage

    // Stable UUIDs per family member (deterministic for local-only SwiftData)
    private let memberIDs: [String: UUID] = [
        "Jesse": UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID(),
        "Sophie": UUID(uuidString: "00000000-0000-0000-0000-000000000002") ?? UUID(),
        "Rowan": UUID(uuidString: "00000000-0000-0000-0000-000000000003") ?? UUID(),
        "Jude": UUID(uuidString: "00000000-0000-0000-0000-000000000004") ?? UUID()
    ]

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
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if challengeType == type {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.teal)
                                }
                            }
                        }
                    }
                }

                Section("Opponent") {
                    Picker("Challenge", selection: $opponentName) {
                        ForEach(familyMembers.filter { $0 != currentUser }, id: \.self) {
                            Text($0)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Duration & Points") {
                    DatePicker("End Date", selection: $endDate, in: Date()..., displayedComponents: .date)
                    Stepper("Points: \(pointValue)", value: $pointValue, in: 10...1000, step: 10)
                }

                if let error = startError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground(style: .rivalries) }
            .navigationTitle("Start a Rivalry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Challenge!") {
                        createRivalry()
                        if startError == nil { dismiss() }
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }

    private func typeColor(_ type: ChallengeType) -> Color {
        switch type {
        case .steps: .blue
        case .workout: .orange
        case .habit: .green
        case .custom: .purple
        }
    }

    private func updateDefaultTitle() {
        if title.isEmpty || ChallengeType.allCases.map({ "\(currentUser) vs \(opponentName): \($0.displayName)" }).contains(title) {
            title = "\(currentUser) vs \(opponentName): \(challengeType.displayName)"
        }
    }

    private func createRivalry() {
        guard let initiatorID = memberIDs[currentUser],
              let opponentID = memberIDs[opponentName] else {
            startError = "Could not find member IDs. Please try again."
            return
        }
        let rivalry = Rivalry(
            title: title,
            challengeType: challengeType,
            initiatorID: initiatorID,
            initiatorName: currentUser,
            opponentID: opponentID,
            opponentName: opponentName,
            endDate: endDate,
            pointValue: pointValue
        )
        modelContext.insert(rivalry)
    }
}

#Preview {
    StartRivalryView()
        .modelContainer(for: [Rivalry.self])
}
