import SwiftUI

struct LogProgressView: View {
    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss

    let rivalry: RivalryResponse
    let memberName: String
    let onSaved: () async -> Void

    @State private var value = ""
    @State private var note = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: rivalry.challengeType.icon)
                            .foregroundStyle(TabAccent.home.color)
                        Text(rivalry.title)
                            .font(.subheadline)
                    }
                }

                Section("Log Entry") {
                    HStack {
                        TextField(placeholder, text: $value)
                            .keyboardType(.decimalPad)
                        Text(unitLabel)
                            .foregroundStyle(WarmPalette.ink3)
                    }
                    TextField("Note (optional)", text: $note)
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground(style: .rivalries) }
            .navigationTitle("Log Progress")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Couldn’t save progress", isPresented: errorAlertIsPresented) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "An unexpected error occurred.")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        Task { await save() }
                    }
                    .disabled(value.isEmpty)
                }
            }
        }
    }

    private var placeholder: String {
        switch rivalry.challengeType {
        case .steps: "Steps"
        case .workout: "Workouts completed"
        case .pushups: "Push-ups"
        case .squats: "Squats"
        case .situps: "Sit-ups"
        case .plank: "Seconds held"
        case .running: "Distance or minutes"
        case .habit: "Days completed"
        case .custom: "Value"
        }
    }

    private var unitLabel: String {
        switch rivalry.challengeType {
        case .steps: "steps"
        case .workout: "workouts"
        case .pushups: "push-ups"
        case .squats: "squats"
        case .situps: "sit-ups"
        case .plank: "seconds"
        case .running: "km"
        case .habit: "days"
        case .custom: "pts"
        }
    }

    private func save() async {
        guard let numValue = Double(value) else {
            error = "Enter a valid number."
            return
        }
        do {
            try await api.addRivalryEntry(id: rivalry.id, data: [
                "member_name": memberName,
                "value": numValue,
                "note": note.isEmpty ? NSNull() : note,
                "is_verified": false
            ])
            await onSaved()
            dismiss()
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }

    private var errorAlertIsPresented: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    }
}

#Preview {
    LogProgressView(
        rivalry: RivalryResponse(id: 1, title: "Test", challenge_type: "steps", initiator_name: "Jesse", opponent_name: "Sophie", start_date: "2026-04-01", end_date: "2026-04-10", status: "active", point_value: 100, winner_name: nil, created_at: nil, participants: nil),
        memberName: "Jesse",
        onSaved: {}
    )
    .environment(APIService())
}
