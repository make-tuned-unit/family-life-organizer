import SwiftUI
import SwiftData

struct GiftsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GiftPerson.name) private var people: [GiftPerson]
    @Query(sort: \SpecialEvent.date) private var events: [SpecialEvent]
    @Query private var allIdeas: [GiftIdea]

    @State private var showingAddPerson = false
    @State private var showingAddEvent = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Upcoming events
                upcomingSection

                // People
                if !people.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("People")
                                .font(.headline)
                            Spacer()
                            Button { showingAddPerson = true } label: {
                                Label("Add", systemImage: "plus")
                                    .font(.caption)
                            }
                        }
                        .padding(.horizontal)

                        ForEach(people) { person in
                            NavigationLink {
                                PersonGiftListView(person: person)
                            } label: {
                                PersonRow(person: person, ideaCount: allIdeas.filter { $0.personID == person.id }.count)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal)
                        }
                    }
                }

                // Standalone events
                if !standaloneEvents.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Special Events")
                                .font(.headline)
                            Spacer()
                            Button { showingAddEvent = true } label: {
                                Label("Add", systemImage: "plus")
                                    .font(.caption)
                            }
                        }
                        .padding(.horizontal)

                        ForEach(standaloneEvents) { event in
                            EventRow(event: event)
                                .padding(.horizontal)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        modelContext.delete(event)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }

                // Empty state
                if people.isEmpty && events.isEmpty {
                    ContentUnavailableView {
                        Label("Gift Lists", systemImage: "gift.fill")
                    } description: {
                        Text("Add people and track gift ideas, birthdays, and special events")
                    } actions: {
                        Button("Add a Person") { showingAddPerson = true }
                            .buttonStyle(.borderedProminent)
                            .tint(.teal)
                    }
                    .padding(.top, 40)
                }
            }
            .padding(.vertical)
        }
        .background { AmbientBackground(style: .gifts) }
        .navigationTitle("Gifts & Events")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showingAddPerson = true } label: {
                        Label("Add Person", systemImage: "person.badge.plus")
                    }
                    Button { showingAddEvent = true } label: {
                        Label("Add Event", systemImage: "calendar.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddPerson) {
            AddGiftPersonView()
        }
        .sheet(isPresented: $showingAddEvent) {
            AddSpecialEventView()
        }
    }

    private var standaloneEvents: [SpecialEvent] {
        events.filter { $0.personID == nil }.sorted { ($0.daysUntil ?? 999) < ($1.daysUntil ?? 999) }
    }

    @ViewBuilder
    private var upcomingSection: some View {
        let upcoming = upcomingItems
        if !upcoming.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Coming Up")
                    .font(.headline)
                    .padding(.horizontal)

                ForEach(upcoming, id: \.label) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.icon)
                            .font(.title3)
                            .foregroundStyle(item.color)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.label)
                                .font(.subheadline.weight(.medium))
                            Text(item.sublabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(item.countdown)
                            .font(.subheadline.bold())
                            .foregroundStyle(item.days <= 7 ? .red : item.days <= 30 ? .orange : .secondary)
                    }
                    .padding(12)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }
            }
        }
    }

    private struct UpcomingItem {
        let label: String
        let sublabel: String
        let countdown: String
        let days: Int
        let icon: String
        let color: Color
    }

    private var upcomingItems: [UpcomingItem] {
        var items: [UpcomingItem] = []

        for person in people {
            if let (eventName, date) = person.upcomingEvent {
                let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 999
                if days <= 90 {
                    items.append(UpcomingItem(
                        label: "\(person.name)'s \(eventName)",
                        sublabel: person.relationship.capitalized,
                        countdown: days == 0 ? "Today!" : "\(days)d",
                        days: days,
                        icon: eventName == "Birthday" ? "birthday.cake.fill" : "heart.fill",
                        color: eventName == "Birthday" ? .purple : .pink
                    ))
                }
            }
        }

        for event in events {
            if let days = event.daysUntil, days <= 90 {
                items.append(UpcomingItem(
                    label: event.title,
                    sublabel: event.eventType.capitalized,
                    countdown: days == 0 ? "Today!" : "\(days)d",
                    days: days,
                    icon: eventIcon(event.eventType),
                    color: .teal
                ))
            }
        }

        return items.sorted { $0.days < $1.days }
    }

    private func eventIcon(_ type: String) -> String {
        switch type {
        case "birthday": "birthday.cake.fill"
        case "anniversary": "heart.fill"
        case "holiday": "star.fill"
        default: "calendar.circle.fill"
        }
    }
}

struct PersonRow: View {
    let person: GiftPerson
    let ideaCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.circle.fill")
                .font(.title2)
                .foregroundStyle(.teal)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name)
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 8) {
                    Text(person.relationship.capitalized)
                    if let (event, _) = person.upcomingEvent {
                        Text("· \(event) coming up")
                            .foregroundStyle(.purple)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if ideaCount > 0 {
                Text("\(ideaCount) ideas")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.teal.opacity(0.15))
                    .foregroundStyle(.teal)
                    .clipShape(Capsule())
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

struct EventRow: View {
    let event: SpecialEvent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: eventIcon)
                .foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.subheadline.weight(.medium))
                Text("\(event.eventType.capitalized) · \(formattedDate)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let days = event.daysUntil {
                Text(days == 0 ? "Today" : "\(days)d")
                    .font(.caption.bold())
                    .foregroundStyle(days <= 7 ? .red : .secondary)
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private var eventIcon: String {
        switch event.eventType {
        case "birthday": "birthday.cake.fill"
        case "anniversary": "heart.fill"
        case "holiday": "star.fill"
        default: "calendar.circle.fill"
        }
    }

    private var formattedDate: String {
        guard let d = DateFormatter.monthDay.date(from: event.date) else { return event.date }
        return DateFormatter.shortMonthDay.string(from: d)
    }
}

#Preview {
    NavigationStack {
        GiftsView()
    }
    .modelContainer(for: [GiftPerson.self, GiftIdea.self, SpecialEvent.self])
}
