import SwiftUI
import SwiftData

struct PersonGiftListView: View {
    @Environment(\.modelContext) private var modelContext
    let person: GiftPerson
    @Query private var allIdeas: [GiftIdea]
    @State private var showingAddIdea = false

    private var ideas: [GiftIdea] {
        allIdeas.filter { $0.personID == person.id }
    }

    private var activeIdeas: [GiftIdea] {
        ideas.filter { $0.status == .idea || $0.status == .purchased }
    }

    private var completedIdeas: [GiftIdea] {
        ideas.filter { $0.status == .wrapped || $0.status == .given }
    }

    var body: some View {
        List {
            // Person info
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.teal)
                        VStack(alignment: .leading) {
                            Text(person.name)
                                .font(.title3.bold())
                            Text(person.relationship.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let bday = person.birthday {
                        Label("Birthday: \(formatMonthDay(bday))", systemImage: "birthday.cake.fill")
                            .font(.subheadline)
                    }
                    if let ann = person.anniversary {
                        Label("Anniversary: \(formatMonthDay(ann))", systemImage: "heart.fill")
                            .font(.subheadline)
                            .foregroundStyle(.pink)
                    }
                    if let notes = person.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Gift ideas
            if !activeIdeas.isEmpty {
                Section("Gift Ideas") {
                    ForEach(activeIdeas) { idea in
                        GiftIdeaRow(idea: idea) { newStatus in
                            idea.status = newStatus
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                modelContext.delete(idea)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            if !completedIdeas.isEmpty {
                Section("Given") {
                    ForEach(completedIdeas) { idea in
                        GiftIdeaRow(idea: idea) { newStatus in
                            idea.status = newStatus
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
        .navigationTitle(person.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAddIdea = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddIdea) {
            AddGiftIdeaView(personID: person.id, personName: person.name)
        }
    }

    private func formatMonthDay(_ md: String) -> String {
        guard let d = DateFormatter.monthDay.date(from: md) else { return md }
        return DateFormatter.longMonthDay.string(from: d)
    }
}

struct GiftIdeaRow: View {
    let idea: GiftIdea
    let onStatusChange: (GiftIdeaStatus) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                let next: GiftIdeaStatus = switch idea.status {
                case .idea: .purchased
                case .purchased: .wrapped
                case .wrapped: .given
                case .given: .given
                }
                onStatusChange(next)
            } label: {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(idea.title)
                    .font(.subheadline.weight(.medium))
                    .strikethrough(idea.status == .given)
                HStack(spacing: 8) {
                    if let event = idea.forEvent, !event.isEmpty {
                        Text(event.capitalized)
                    }
                    if let price = idea.estimatedPrice {
                        Text("$\(price, specifier: "%.0f")")
                    }
                    Text(idea.status.rawValue.capitalized)
                        .foregroundStyle(statusColor)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if let url = idea.linkURL, !url.isEmpty {
                Link(destination: URL(string: url) ?? URL(string: "https://example.com")!) {
                    Image(systemName: "link")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
        }
    }

    private var statusIcon: String {
        switch idea.status {
        case .idea: "lightbulb"
        case .purchased: "bag.fill"
        case .wrapped: "gift.fill"
        case .given: "checkmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch idea.status {
        case .idea: .yellow
        case .purchased: .blue
        case .wrapped: .purple
        case .given: .green
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: GiftPerson.self, GiftIdea.self, SpecialEvent.self, configurations: config)
    let person = GiftPerson(name: "Sophie", relationship: "spouse", birthday: "06-15")
    container.mainContext.insert(person)

    return NavigationStack {
        PersonGiftListView(person: person)
    }
    .modelContainer(container)
}
