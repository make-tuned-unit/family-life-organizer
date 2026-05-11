import SwiftUI

struct PersonGiftListView: View {
    @Environment(APIService.self) private var api
    let person: GiftPersonResponse

    @State private var ideas: [GiftIdeaResponse] = []
    @State private var showingAddIdea = false
    @State private var error: String?

    private var activeIdeas: [GiftIdeaResponse] {
        ideas.filter { $0.status == GiftIdeaStatus.idea.rawValue || $0.status == GiftIdeaStatus.purchased.rawValue }
    }

    private var completedIdeas: [GiftIdeaResponse] {
        ideas.filter { $0.status == GiftIdeaStatus.wrapped.rawValue || $0.status == GiftIdeaStatus.given.rawValue }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(TabAccent.home.color)
                        VStack(alignment: .leading) {
                            Text(person.name)
                                .font(.title3.bold())
                            Text(person.relationship.capitalized)
                                .font(.caption)
                                .foregroundStyle(WarmPalette.ink3)
                        }
                    }
                    if let birthday = person.birthday {
                        Label("Birthday: \(formatMonthDay(birthday))", systemImage: "birthday.cake.fill")
                            .font(.subheadline)
                    }
                    if let anniversary = person.anniversary {
                        Label("Anniversary: \(formatMonthDay(anniversary))", systemImage: "heart.fill")
                            .font(.subheadline)
                            .foregroundStyle(AccentTheme.rose.color)
                    }
                    if let notes = person.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(WarmPalette.ink3)
                    }
                }
            }

            if !activeIdeas.isEmpty {
                Section("Gift Ideas") {
                    ForEach(activeIdeas) { idea in
                        GiftIdeaRowRemote(idea: idea) { newStatus in
                            await updateStatus(for: idea.id, status: newStatus)
                        } onDelete: {
                            await deleteIdea(idea.id)
                        }
                    }
                }
            }

            if !completedIdeas.isEmpty {
                Section("Given") {
                    ForEach(completedIdeas) { idea in
                        GiftIdeaRowRemote(idea: idea) { newStatus in
                            await updateStatus(for: idea.id, status: newStatus)
                        } onDelete: {
                            await deleteIdea(idea.id)
                        }
                        .opacity(0.6)
                    }
                }
            }

            if ideas.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No Gift Ideas", systemImage: "gift")
                    } description: {
                        Text("Save ideas for \(person.name)")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background { AmbientBackground(style: .gifts) }
        .navigationTitle(person.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAddIdea = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddIdea) {
            AddGiftIdeaView(personID: person.id, personName: person.name) {
                await loadIdeas()
            }
        }
        .refreshable {
            await loadIdeas()
        }
        .alert("Couldn’t update gift list", isPresented: errorAlertIsPresented) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "An unexpected error occurred.")
        }
        .task {
            await loadIdeas()
        }
    }

    private func loadIdeas() async {
        do {
            ideas = try await api.fetchGiftIdeas(personId: person.id)
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }

    private func updateStatus(for id: Int, status: GiftIdeaStatus) async {
        do {
            try await api.updateGiftIdea(id: id, data: ["status": status.rawValue])
            await loadIdeas()
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }

    private func deleteIdea(_ id: Int) async {
        do {
            try await api.deleteGiftIdea(id: id)
            await loadIdeas()
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }

    private func formatMonthDay(_ value: String) -> String {
        guard let date = DateFormatter.monthDay.date(from: value) else { return value }
        return DateFormatter.longMonthDay.string(from: date)
    }

    private var errorAlertIsPresented: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    }
}

struct GiftIdeaRowRemote: View {
    let idea: GiftIdeaResponse
    let onStatusChange: (GiftIdeaStatus) async -> Void
    let onDelete: () async -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                Task {
                    let next: GiftIdeaStatus = switch idea.statusValue {
                    case .idea: .purchased
                    case .purchased: .wrapped
                    case .wrapped: .given
                    case .given: .given
                    }
                    await onStatusChange(next)
                }
            } label: {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(idea.title)
                    .font(.subheadline.weight(.medium))
                    .strikethrough(idea.statusValue == .given)
                HStack(spacing: 8) {
                    if let event = idea.for_event, !event.isEmpty {
                        Text(event.capitalized)
                    }
                    if let price = idea.estimated_price {
                        Text("$\(price, specifier: "%.0f")")
                    }
                    Text(idea.statusValue.rawValue.capitalized)
                        .foregroundStyle(statusColor)
                }
                .font(.caption)
                .foregroundStyle(WarmPalette.ink3)
            }

            Spacer()

            if let url = idea.link_url, !url.isEmpty, let parsedURL = URL(string: url) {
                Link(destination: parsedURL) {
                    Image(systemName: "link")
                        .font(.caption)
                        .foregroundStyle(AccentTheme.ocean.color)
                }
            }

            Button(role: .destructive) {
                Task { await onDelete() }
            } label: {
                Image(systemName: "trash")
            }
        }
    }

    private var statusIcon: String {
        switch idea.statusValue {
        case .idea: "lightbulb"
        case .purchased: "bag.fill"
        case .wrapped: "gift.fill"
        case .given: "checkmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch idea.statusValue {
        case .idea: AccentTheme.saffron.color
        case .purchased: AccentTheme.ocean.color
        case .wrapped: AccentTheme.mauve.color
        case .given: WarmPalette.good
        }
    }
}

private extension GiftIdeaResponse {
    var statusValue: GiftIdeaStatus {
        GiftIdeaStatus(rawValue: status) ?? .idea
    }
}

#Preview {
    NavigationStack {
        PersonGiftListView(person: GiftPersonResponse(id: 1, name: "Sophie", relationship: "spouse", birthday: "06-15", anniversary: nil, notes: nil, created_at: nil))
            .environment(APIService())
    }
}
