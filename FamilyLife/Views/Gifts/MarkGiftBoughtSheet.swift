import SwiftUI

/// Marks a gift as bought and, optionally, quietly lets one person know — a
/// direct notification to just them, never a household post. Built for two
/// parents coordinating a kid's birthday without the kids finding out.
struct MarkGiftBoughtSheet: View {
    @Environment(APIService.self) private var api
    @Environment(AuthService.self) private var auth
    @Environment(HouseholdService.self) private var household
    @Environment(\.dismiss) private var dismiss

    let idea: GiftIdeaResponse
    let personName: String
    /// The recipient's linked account, if any — never offered for notifying.
    var recipientUserId: Int? = nil
    let onDone: () async -> Void

    /// Remembers who you last told, so "tell my partner" is one tap next time.
    @AppStorage("giftBoughtNotifyUserId") private var lastNotifiedId = 0
    @State private var notifyId = 0
    @State private var saving = false
    @State private var error: String?

    private var myId: Int? { auth.currentUser?.id }

    /// Household members who could be told: not me, not the recipient.
    private var candidates: [HouseholdService.HouseholdUser] {
        household.householdUsers.filter { $0.id != myId && $0.id != recipientUserId }
    }

    private var chosen: HouseholdService.HouseholdUser? {
        candidates.first { $0.id == notifyId }
    }

    /// Sensible default: whoever this idea is already shared with (or whoever
    /// saved it, if that's not me), else the person you told last time.
    private var suggestedId: Int {
        let ids = Set(candidates.map(\.id))
        for id in [idea.shared_with_user_id, idea.created_by, lastNotifiedId] {
            if let id, id != myId, ids.contains(id) { return id }
        }
        return 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(idea.title)
                                .font(.flHeadline)
                                .foregroundStyle(WarmPalette.ink1)
                            Text(occasionLine)
                                .font(.flFootnote)
                                .foregroundStyle(WarmPalette.ink3)
                        }
                    } icon: {
                        Image(systemName: "gift")
                            .foregroundStyle(TabAccent.gifts.color)
                    }
                }

                Section {
                    Picker("Let someone know", selection: $notifyId) {
                        Text("Don't notify anyone").tag(0)
                        ForEach(candidates) { user in
                            Text(user.name).tag(user.id)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Let someone know")
                } footer: {
                    Text(footerText)
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground(style: .gifts) }
            .navigationTitle("Mark as bought")
            .navigationBarTitleDisplayMode(.inline)
            .inlineError(error) { error = nil }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(chosen == nil ? "Mark bought" : "Mark & notify") {
                        Task { await save() }
                    }
                    .disabled(saving)
                }
            }
            .task {
                if !household.isLoaded { await household.load(api: api, currentUserId: myId) }
                notifyId = suggestedId
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var occasionLine: String {
        if let event = idea.for_event, !event.isEmpty { return "For \(personName)'s \(event)" }
        return "For \(personName)"
    }

    private var footerText: String {
        guard let chosen else { return "It'll show as bought here. Nobody gets a notification." }
        var text = "Only \(chosen.name) gets a notification — nobody else is told."
        if idea.visibilityValue == .private || (idea.visibilityValue == .shared && idea.shared_with_user_id != chosen.id && idea.created_by == myId) {
            text += " This also lets \(chosen.name) see this gift idea."
        }
        return text
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            try await api.markGiftBought(id: idea.id, notifyUserId: chosen?.id)
            if let chosen { lastNotifiedId = chosen.id }
            await onDone()
            dismiss()
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }
}

#Preview {
    MarkGiftBoughtSheet(
        idea: GiftIdeaResponse(id: 1, person_id: 2, title: "Balance bike", notes: nil, link_url: nil,
                               estimated_price: 120, status: "idea", for_event: "birthday", created_at: nil,
                               created_by: 1, visibility: "shared", shared_with_user_id: 3),
        personName: "Max",
        onDone: {}
    )
    .environment(APIService())
    .environment(AuthService())
    .environment(HouseholdService())
}
