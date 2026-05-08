import SwiftUI

struct GiftsView: View {
    var showsDismissButton = false

    @Environment(\.dismiss) private var dismiss
    @Environment(APIService.self) private var api

    @State private var people: [GiftPersonResponse] = []
    @State private var events: [SpecialEventResponse] = []
    @State private var allIdeas: [GiftIdeaResponse] = []
    @State private var showingAddPerson = false
    @State private var showingAddEvent = false
    @State private var error: String?
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                upcomingSection

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
                                PersonRowRemote(person: person, ideaCount: allIdeas.filter { $0.person_id == person.id }.count)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal)
                        }
                    }
                }

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
                            EventRowRemote(event: event) {
                                await deleteEvent(event.id)
                            }
                            .padding(.horizontal)
                        }
                    }
                }

                if people.isEmpty && events.isEmpty && !isLoading {
                    ContentUnavailableView {
                        Label("Gift Lists", systemImage: "gift.fill")
                    } description: {
                        Text("Add people and track gift ideas, birthdays, and special events")
                    } actions: {
                        Button { showingAddPerson = true } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "person.badge.plus")
                                    .font(.system(size: 14))
                                Text("Add a Person")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundStyle(WarmPalette.cream1)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(WarmPalette.ink1)
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.top, DesignTokens.Spacing.large)
                }
            }
            .padding(.vertical)
        }
        .background { AmbientBackground(style: .gifts) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .toolbar {
            if showsDismissButton {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
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
            AddGiftPersonView {
                await loadAll()
            }
        }
        .sheet(isPresented: $showingAddEvent) {
            AddSpecialEventView {
                await loadAll()
            }
        }
        .refreshable {
            await loadAll()
        }
        .overlay {
            if isLoading && people.isEmpty && events.isEmpty {
                ProgressView()
            }
        }
        .alert("Couldn’t load gifts", isPresented: errorAlertIsPresented) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "An unexpected error occurred.")
        }
        .task {
            await loadAll()
        }
    }

    private var standaloneEvents: [SpecialEventResponse] {
        events.filter { $0.person_id == nil }.sorted { ($0.daysUntil ?? 999) < ($1.daysUntil ?? 999) }
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
                                .foregroundStyle(WarmPalette.ink3)
                        }
                        Spacer()
                        Text(item.countdown)
                            .font(.subheadline.bold())
                            .foregroundStyle(item.days <= 7 ? .red : item.days <= 30 ? .orange : .secondary)
                    }
                    .padding(DesignTokens.Spacing.cardGap)
                    .background(WarmPalette.ink1.opacity(0.06))
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
                        color: eventName == "Birthday" ? AccentTheme.mauve.color : AccentTheme.rose.color
                    ))
                }
            }
        }

        for event in events {
            if let days = event.daysUntil, days <= 90 {
                items.append(UpcomingItem(
                    label: event.title,
                    sublabel: event.event_type.capitalized,
                    countdown: days == 0 ? "Today!" : "\(days)d",
                    days: days,
                    icon: eventIcon(event.event_type),
                    color: TabAccent.home.color
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

    private func loadAll() async {
        isLoading = true
        error = nil
        do {
            async let fetchedPeople = api.fetchGiftPeople()
            async let fetchedEvents = api.fetchSpecialEvents()
            async let fetchedIdeas = api.fetchGiftIdeas()
            people = try await fetchedPeople
            events = try await fetchedEvents
            allIdeas = try await fetchedIdeas
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func deleteEvent(_ id: Int) async {
        do {
            try await api.deleteSpecialEvent(id: id)
            await loadAll()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private var errorAlertIsPresented: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    }
}

struct PersonRowRemote: View {
    let person: GiftPersonResponse
    let ideaCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.circle.fill")
                .font(.title2)
                .foregroundStyle(TabAccent.home.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name)
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 8) {
                    Text(person.relationship.capitalized)
                    if let (event, _) = person.upcomingEvent {
                        Text("· \(event) coming up")
                            .foregroundStyle(AccentTheme.mauve.color)
                    }
                }
                .font(.caption)
                .foregroundStyle(WarmPalette.ink3)
            }
            Spacer()
            if ideaCount > 0 {
                Text("\(ideaCount) ideas")
                    .font(.caption2)
                    .padding(.horizontal, DesignTokens.Spacing.chipPadding)
                    .padding(.vertical, DesignTokens.Spacing.tinyLabel)
                    .background(TabAccent.gifts.color.opacity(DesignTokens.Opacity.badgeFill))
                    .foregroundStyle(TabAccent.home.color)
                    .clipShape(Capsule())
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(WarmPalette.ink4)
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .flCard(tint: TabAccent.gifts.color)
    }
}

struct EventRowRemote: View {
    let event: SpecialEventResponse
    let onDelete: () async -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: eventIcon)
                .font(.title3)
                .foregroundStyle(TabAccent.home.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 8) {
                    Text(event.event_type.capitalized)
                    Text("· \(formattedDate)")
                }
                .font(.caption)
                .foregroundStyle(WarmPalette.ink3)
            }
            Spacer()
            Button(role: .destructive) {
                Task { await onDelete() }
            } label: {
                Image(systemName: "trash")
            }
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .flCard(tint: TabAccent.gifts.color)
    }

    private var eventIcon: String {
        switch event.event_type {
        case "birthday": "birthday.cake.fill"
        case "anniversary": "heart.fill"
        case "holiday": "star.fill"
        default: "calendar.circle.fill"
        }
    }

    private var formattedDate: String {
        guard let date = DateFormatter.monthDay.date(from: event.date) else { return event.date }
        return DateFormatter.longMonthDay.string(from: date)
    }
}

private extension GiftPersonResponse {
    var upcomingEvent: (String, Date)? {
        let cal = Calendar.current
        let now = Date()
        let year = cal.component(.year, from: now)

        var options: [(String, Date)] = []
        if let birthday, let parsed = DateFormatter.monthDay.date(from: birthday) {
            var comps = cal.dateComponents([.month, .day], from: parsed)
            comps.year = year
            if let date = cal.date(from: comps) {
                options.append(("Birthday", date < now ? cal.date(byAdding: .year, value: 1, to: date) ?? date : date))
            }
        }
        if let anniversary, let parsed = DateFormatter.monthDay.date(from: anniversary) {
            var comps = cal.dateComponents([.month, .day], from: parsed)
            comps.year = year
            if let date = cal.date(from: comps) {
                options.append(("Anniversary", date < now ? cal.date(byAdding: .year, value: 1, to: date) ?? date : date))
            }
        }
        return options.min(by: { $0.1 < $1.1 })
    }
}

private extension SpecialEventResponse {
    var nextOccurrence: Date? {
        let cal = Calendar.current
        let now = Date()
        let year = cal.component(.year, from: now)
        guard let parsed = DateFormatter.monthDay.date(from: date) else { return nil }
        var comps = cal.dateComponents([.month, .day], from: parsed)
        comps.year = year
        guard let candidate = cal.date(from: comps) else { return nil }
        return candidate < now ? cal.date(byAdding: .year, value: 1, to: candidate) : candidate
    }

    var daysUntil: Int? {
        guard let nextOccurrence else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: nextOccurrence).day
    }
}

#Preview {
    NavigationStack {
        GiftsView()
            .environment(APIService())
    }
}
