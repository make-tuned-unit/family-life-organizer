import SwiftUI

struct AddGiftIdeaView: View {
    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss

    let personID: Int
    let personName: String
    let onSaved: () async -> Void

    @State private var title = ""
    @State private var notes = ""
    @State private var linkURL = ""
    @State private var estimatedPrice = ""
    @State private var forEvent = ""
    @State private var error: String?

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
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground(style: .gifts) }
            .navigationTitle("Gift for \(personName)")
            .navigationBarTitleDisplayMode(.inline)
            .inlineError(error) { error = nil }
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
            try await api.addGiftIdea([
                "person_id": personID,
                "title": title,
                "notes": notes.isEmpty ? NSNull() : notes,
                "link_url": linkURL.isEmpty ? NSNull() : linkURL,
                "estimated_price": estimatedPriceValue,
                "for_event": forEvent.isEmpty ? NSNull() : forEvent,
                "status": GiftIdeaStatus.idea.rawValue
            ])
            await onSaved()
            dismiss()
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }
}

#Preview {
    AddGiftIdeaView(personID: 1, personName: "Sophie", onSaved: {})
        .environment(APIService())
}
