import SwiftUI

struct AddGiftIdeaView: View {
    @Environment(APIService.self) private var api
    @Environment(AuthService.self) private var auth
    @Environment(HouseholdService.self) private var household
    @Environment(\.dismiss) private var dismiss

    let personID: Int
    let personName: String
    /// The recipient's linked account, if they have one — never offered as
    /// someone to share with (it would spoil the surprise).
    var recipientUserId: Int? = nil
    let onSaved: () async -> Void

    @State private var title = ""
    @State private var notes = ""
    @State private var linkURL = ""
    @State private var estimatedPrice = ""
    @State private var forEvent = ""
    /// "household", "private", or "user:<id>" for sharing with one person.
    @State private var audience = "household"
    @State private var error: String?

    /// Household members this idea could be shared with: not me, not them.
    private var partners: [HouseholdService.HouseholdUser] {
        household.householdUsers.filter { $0.id != auth.currentUser?.id && $0.id != recipientUserId }
    }

    private let events = ["birthday", "anniversary", "christmas", "valentines", "mothers day", "fathers day", "other"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Gift idea", text: $title)
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2)
                }

                Section("Details") {
                    TextField("Link (optional)", text: $linkURL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    HStack {
                        Text("$")
                            .foregroundStyle(WarmPalette.ink3)
                        TextField("Price estimate", text: $estimatedPrice)
                            .keyboardType(.decimalPad)
                    }
                }

                Section("For") {
                    Picker("Occasion", selection: $forEvent) {
                        Text("Any time").tag("")
                        ForEach(events, id: \.self) {
                            Text($0.capitalized).tag($0)
                        }
                    }
                }

                Section {
                    Picker("Who can see this", selection: $audience) {
                        Label("Everyone at home", systemImage: "house").tag("household")
                        Label("Just me", systemImage: "lock").tag("private")
                        ForEach(partners) { user in
                            Label("Me and \(user.name)", systemImage: "person.2").tag("user:\(user.id)")
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Who can see this")
                } footer: {
                    Text(recipientUserId != nil
                         ? "\(personName) never sees gift ideas saved for them."
                         : "Only the people you choose will see this idea.")
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground(style: .gifts) }
            .navigationTitle("Gift for \(personName)")
            .navigationBarTitleDisplayMode(.inline)
            .inlineError(error) { error = nil }
            .task { if !household.isLoaded { await household.load(api: api, currentUserId: auth.currentUser?.id) } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }

    private func save() async {
        do {
            let estimatedPriceValue: Any = Double(estimatedPrice) ?? NSNull()
            var scope: [String: Any] = ["visibility": audience]
            if audience.hasPrefix("user:"), let partnerId = Int(audience.dropFirst(5)) {
                scope = ["visibility": GiftVisibility.shared.rawValue, "shared_with_user_id": partnerId]
            }
            try await api.addGiftIdea(scope.merging([
                "person_id": personID,
                "title": title,
                "notes": notes.isEmpty ? NSNull() : notes,
                "link_url": linkURL.isEmpty ? NSNull() : linkURL,
                "estimated_price": estimatedPriceValue,
                "for_event": forEvent.isEmpty ? NSNull() : forEvent,
                "status": GiftIdeaStatus.idea.rawValue
            ]) { current, _ in current })
            await onSaved()
            dismiss()
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }
}

#Preview {
    AddGiftIdeaView(personID: 1, personName: "Max", onSaved: {})
        .environment(APIService())
        .environment(AuthService())
        .environment(HouseholdService())
}
