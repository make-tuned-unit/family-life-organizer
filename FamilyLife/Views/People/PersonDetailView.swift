import SwiftUI
import PhotosUI

/// One family member's card: their milestones timeline, gift ideas, key
/// dates, and the decisions the household has tagged to them.
struct PersonDetailView: View {
    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss
    let person: PersonResponse
    var onChanged: (() async -> Void)?

    private enum Tab: String, CaseIterable, Identifiable {
        case milestones = "Milestones"
        case gifts = "Gifts"
        case dates = "Key dates"
        case decisions = "Decisions"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .milestones
    @State private var milestones: [MilestoneResponse] = []
    @State private var decisions: [DecisionResponse] = []
    @State private var keyDates: [SpecialEventResponse] = []
    @State private var giftIdeas: [GiftIdeaResponse] = []
    @State private var showingAddMilestone = false
    @State private var showingAddKeyDate = false
    @State private var showingAddGift = false
    @State private var showingEditPerson = false
    @State private var showingDeleteConfirm = false
    @State private var editingMilestone: MilestoneResponse?
    @State private var editingKeyDate: SpecialEventResponse?
    /// Live copy of the person — refreshed after edits so the header updates in place.
    @State private var current: PersonResponse?

    private var display: PersonResponse { current ?? person }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                header

                Picker("Section", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                switch tab {
                case .milestones: milestonesSection
                case .gifts: giftsSection
                case .dates: datesSection
                case .decisions: decisionsSection
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        .background { AmbientBackground(style: .gifts) }
        .navigationTitle(display.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showingEditPerson = true } label: {
                        Label("Edit person", systemImage: "pencil")
                    }
                    if display.isDependent {
                        // Linked adults are recreated automatically on next fetch,
                        // so deleting them would just be confusing — dependents only.
                        Button(role: .destructive) { showingDeleteConfirm = true } label: {
                            Label("Remove person", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingAddMilestone) {
            AddMilestoneSheet(person: person) {
                await load()
                await onChanged?()
            }
        }
        .sheet(isPresented: $showingAddKeyDate) {
            AddKeyDateSheet(person: display) {
                await load()
                await onChanged?()
            }
        }
        .sheet(isPresented: $showingAddGift) {
            AddGiftIdeaView(personID: person.id, personName: display.name) {
                await load()
                await onChanged?()
            }
        }
        .sheet(isPresented: $showingEditPerson) {
            EditPersonSheet(person: display) {
                await load()
                await onChanged?()
            }
        }
        .sheet(item: $editingMilestone) { m in
            EditMilestoneSheet(milestone: m, accent: display.accentColor) {
                await load()
                await onChanged?()
            }
        }
        .sheet(item: $editingKeyDate) { ev in
            EditKeyDateSheet(event: ev, personName: display.name) {
                await load()
                await onChanged?()
            }
        }
        .confirmationDialog("Remove \(display.name)?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("Remove person and their history", role: .destructive) {
                Task {
                    try? await api.deletePerson(id: person.id)
                    await onChanged?()
                    dismiss()
                }
            }
        } message: {
            Text("Their milestones, gift ideas and key dates go too. This can't be undone.")
        }
        .task { await load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(display.accentColor.opacity(0.18))
                    .frame(width: 76, height: 76)
                Text(String(display.name.prefix(1)).uppercased())
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(display.accentColor)
            }
            HStack(spacing: 8) {
                if let rel = display.relationship, rel != "other", rel != "household" {
                    Text(rel.capitalized)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(display.accentColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(display.accentColor.opacity(0.12), in: Capsule())
                }
                if let bday = display.birthday, let date = DateFormatter.isoDate.date(from: bday) {
                    HStack(spacing: 4) {
                        Image(systemName: "birthday.cake.fill").font(.system(size: 10))
                        Text(DateFormatter.longMonthDay.string(from: date))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WarmPalette.ink3)
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Milestones

    private var milestonesSection: some View {
        VStack(spacing: 10) {
            Button { showingAddMilestone = true } label: {
                Label("Add a milestone", systemImage: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(display.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(display.accentColor)
            }
            .buttonStyle(.plain)

            if milestones.isEmpty {
                sectionEmpty("flag.fill", "No milestones yet",
                             "First steps, first goal, lost tooth — log the moments worth remembering.")
            } else {
                ForEach(milestones) { m in
                    milestoneRow(m)
                }
            }
        }
    }

    private func milestoneRow(_ m: MilestoneResponse) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11)
                    .fill(m.categoryEnum.color.opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: m.categoryEnum.icon)
                    .font(.system(size: 15))
                    .foregroundStyle(m.categoryEnum.color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(m.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WarmPalette.ink1)
                if let desc = m.description, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 13))
                        .foregroundStyle(WarmPalette.ink2)
                }
                HStack(spacing: 6) {
                    if let date = DateFormatter.isoDate.date(from: String(m.milestone_date.prefix(10))) {
                        Text(DateFormatter.mediumDisplay.string(from: date))
                    }
                    if let by = m.creator_name {
                        Text("· added by \(by)")
                    }
                }
                .font(.system(size: 11.5))
                .foregroundStyle(WarmPalette.ink3)
            }
            Spacer()
            if let b64 = m.photo_data, let data = Data(base64Encoded: b64), let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(13)
        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: 16))
        .contextMenu {
            Button { editingMilestone = m } label: {
                Label("Edit milestone", systemImage: "pencil")
            }
            Button(role: .destructive) {
                Task {
                    try? await api.deleteMilestone(id: m.id)
                    await load()
                    await onChanged?()
                }
            } label: {
                Label("Delete milestone", systemImage: "trash")
            }
        }
    }

    // MARK: - Gifts

    private var giftsSection: some View {
        VStack(spacing: 10) {
            Button { showingAddGift = true } label: {
                Label("Add a gift idea", systemImage: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(display.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(display.accentColor)
            }
            .buttonStyle(.plain)

            if giftIdeas.isEmpty {
                sectionEmpty("gift.fill", "No gift ideas yet",
                             "Jot down ideas as they come — things to save for birthdays and holidays for \(display.name).")
            } else {
                ForEach(giftIdeas) { idea in
                    giftRow(idea)
                }
            }
        }
    }

    private func giftRow(_ idea: GiftIdeaResponse) -> some View {
        let status = GiftIdeaStatus(rawValue: idea.status) ?? .idea
        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11)
                    .fill(giftStatusColor(status).opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: giftStatusIcon(status))
                    .font(.system(size: 15))
                    .foregroundStyle(giftStatusColor(status))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(idea.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WarmPalette.ink1)
                    .strikethrough(status == .given)
                if let notes = idea.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 13))
                        .foregroundStyle(WarmPalette.ink2)
                }
                HStack(spacing: 6) {
                    if let event = idea.for_event, !event.isEmpty {
                        Text(event.capitalized)
                    }
                    if let price = idea.estimated_price {
                        Text("· $\(price, specifier: "%.0f")")
                    }
                    Text("· \(status.rawValue.capitalized)")
                        .foregroundStyle(giftStatusColor(status))
                }
                .font(.system(size: 11.5))
                .foregroundStyle(WarmPalette.ink3)
            }
            Spacer()
            if let url = idea.link_url, !url.isEmpty, let parsed = URL(string: url) {
                Link(destination: parsed) {
                    Image(systemName: "link")
                        .font(.system(size: 13))
                        .foregroundStyle(AccentTheme.ocean.color)
                }
            }
        }
        .padding(13)
        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: 16))
        .contextMenu {
            if status != .given, let next = giftNextStatus(status) {
                Button {
                    Task {
                        try? await api.updateGiftIdea(id: idea.id, data: ["status": next.rawValue])
                        await load()
                        await onChanged?()
                    }
                } label: {
                    Label("Mark as \(next.rawValue.capitalized)", systemImage: giftStatusIcon(next))
                }
            }
            Button(role: .destructive) {
                Task {
                    try? await api.deleteGiftIdea(id: idea.id)
                    await load()
                    await onChanged?()
                }
            } label: {
                Label("Delete gift idea", systemImage: "trash")
            }
        }
    }

    private func giftNextStatus(_ s: GiftIdeaStatus) -> GiftIdeaStatus? {
        switch s {
        case .idea: .purchased
        case .purchased: .wrapped
        case .wrapped: .given
        case .given: nil
        }
    }

    private func giftStatusIcon(_ s: GiftIdeaStatus) -> String {
        switch s {
        case .idea: "lightbulb"
        case .purchased: "bag.fill"
        case .wrapped: "gift.fill"
        case .given: "checkmark.circle.fill"
        }
    }

    private func giftStatusColor(_ s: GiftIdeaStatus) -> Color {
        switch s {
        case .idea: AccentTheme.saffron.color
        case .purchased: AccentTheme.ocean.color
        case .wrapped: AccentTheme.mauve.color
        case .given: WarmPalette.good
        }
    }

    // MARK: - Key dates

    private var datesSection: some View {
        VStack(spacing: 10) {
            Button { showingAddKeyDate = true } label: {
                Label("Add a key date", systemImage: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(display.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(display.accentColor)
            }
            .buttonStyle(.plain)

            if let bday = display.birthday, let date = DateFormatter.isoDate.date(from: bday) {
                dateRow("birthday.cake.fill", "Birthday", DateFormatter.longMonthDay.string(from: date), AccentTheme.saffron.color)
            }
            if let ann = display.anniversary, let date = DateFormatter.isoDate.date(from: ann) {
                dateRow("heart.fill", "Anniversary", DateFormatter.longMonthDay.string(from: date), AccentTheme.rose.color)
            }
            ForEach(keyDates) { ev in
                let dateStr = DateFormatter.isoDate.date(from: String(ev.date.prefix(10)))
                    .map { DateFormatter.longMonthDay.string(from: $0) } ?? ev.date
                dateRow("calendar", ev.title, dateStr, AccentTheme.ocean.color, event: ev)
            }
            if display.birthday == nil && display.anniversary == nil && keyDates.isEmpty {
                sectionEmpty("calendar", "No key dates",
                             "Birthdays, anniversaries, gotcha days — add the dates worth remembering for \(display.name).")
            }
        }
    }

    private func dateRow(_ icon: String, _ title: String, _ value: String, _ color: Color, event: SpecialEventResponse? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .frame(width: 30)
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(WarmPalette.ink1)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(WarmPalette.ink3)
        }
        .padding(13)
        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: 14))
        .contextMenu {
            if let event {
                Button { editingKeyDate = event } label: {
                    Label("Edit key date", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    Task {
                        try? await api.deleteSpecialEvent(id: event.id)
                        await load()
                        await onChanged?()
                    }
                } label: {
                    Label("Delete key date", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Decisions

    private var decisionsSection: some View {
        VStack(spacing: 10) {
            if decisions.isEmpty {
                sectionEmpty("chart.bar.fill", "Nothing tagged yet",
                             "When you create a decision, tag \(display.name) and it will appear here — the story of what you've talked about for them.")
            } else {
                ForEach(decisions) { d in
                    NavigationLink {
                        DecisionDetailView(decision: d) { await load() }
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(d.title)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(WarmPalette.ink1)
                                    .multilineTextAlignment(.leading)
                                HStack(spacing: 6) {
                                    Text(d.status == "active" ? "Open" : d.status.capitalized)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(d.status == "active" ? AccentTheme.sage.color : WarmPalette.ink3)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2)
                                        .background((d.status == "active" ? AccentTheme.sage.color : WarmPalette.ink4).opacity(0.14), in: Capsule())
                                    Text("by \(d.creator_name)")
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(WarmPalette.ink3)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(WarmPalette.ink3)
                        }
                        .padding(13)
                        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Shared bits

    private func sectionEmpty(_ icon: String, _ title: String, _ message: String) -> some View {
        WarmEmptyState(title: title, systemImage: icon, description: message)
    }

    private func load() async {
        async let ms = api.fetchMilestones(personId: person.id)
        async let decs = api.fetchPersonDecisions(personId: person.id)
        async let events = api.fetchSpecialEvents()
        async let gifts = api.fetchGiftIdeas(personId: person.id)
        async let people = api.fetchPeople()
        milestones = (try? await ms) ?? []
        decisions = (try? await decs) ?? []
        keyDates = ((try? await events) ?? []).filter { $0.person_id == person.id }
        giftIdeas = (try? await gifts) ?? []
        if let refreshed = (try? await people)?.first(where: { $0.id == person.id }) {
            current = refreshed
        }
    }
}

// MARK: - Add milestone

struct AddMilestoneSheet: View {
    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss
    let person: PersonResponse
    var onSaved: () async -> Void

    @State private var title = ""
    @State private var note = ""
    @State private var date = Date()
    @State private var category: MilestoneCategory = .moment
    @State private var shareGroupId: Int?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("The moment") {
                    TextField("What happened? (e.g. First steps)", text: $title)
                    TextField("A little detail (optional)", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                    DatePicker("When", selection: $date, displayedComponents: .date)
                }
                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(MilestoneCategory.allCases) { c in
                            Label(c.displayName, systemImage: c.icon).tag(c)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section("Photo") {
                    if let selectedImageData, let uiImage = UIImage(data: selectedImageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .frame(maxWidth: .infinity)
                    }
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label(selectedImageData == nil ? "Add a photo (optional)" : "Change photo",
                              systemImage: selectedImageData == nil ? "photo.on.rectangle" : "arrow.triangle.2.circlepath")
                            .foregroundStyle(person.accentColor)
                    }
                    .onChange(of: selectedPhoto) {
                        Task {
                            if let data = try? await selectedPhoto?.loadTransferable(type: Data.self) {
                                selectedImageData = data
                            }
                        }
                    }
                }
                ShareWithSection(selectedGroupId: $shareGroupId)

                Section {
                    Text("Your household always gets a feed post and a nudge to cheer \(person.name) on. Sharing with a circle celebrates it there too.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(WarmPalette.ink3)
                }
                if let error {
                    Text(error).foregroundStyle(.red).font(.system(size: 13))
                }
            }
            .navigationTitle("New milestone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        var data: [String: Any] = [
            "person_id": person.id,
            "title": title.trimmingCharacters(in: .whitespaces),
            "milestone_date": DateFormatter.isoDate.string(from: date),
            "category": category.rawValue,
        ]
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNote.isEmpty { data["description"] = trimmedNote }
        if let shareGroupId { data["shared_group_id"] = shareGroupId }
        if let imageData = selectedImageData,
           let compressed = UIImage(data: imageData)?.jpegData(compressionQuality: 0.7) {
            data["photo_data"] = compressed.base64EncodedString()
        }
        Task {
            do {
                try await api.addMilestone(data)
                await onSaved()
                dismiss()
            } catch {
                self.error = "Couldn't save. Try again."
                isSaving = false
            }
        }
    }
}

// MARK: - Edit milestone

struct EditMilestoneSheet: View {
    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss
    let milestone: MilestoneResponse
    let accent: Color
    var onSaved: () async -> Void

    @State private var title: String
    @State private var note: String
    @State private var date: Date
    @State private var category: MilestoneCategory
    /// nil = untouched, .some(nil) = removed, .some(data) = replaced
    @State private var photoChange: Data?? = nil
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isSaving = false
    @State private var error: String?

    init(milestone: MilestoneResponse, accent: Color, onSaved: @escaping () async -> Void) {
        self.milestone = milestone
        self.accent = accent
        self.onSaved = onSaved
        _title = State(initialValue: milestone.title)
        _note = State(initialValue: milestone.description ?? "")
        _date = State(initialValue: DateFormatter.isoDate.date(from: String(milestone.milestone_date.prefix(10))) ?? Date())
        _category = State(initialValue: milestone.categoryEnum)
    }

    private var currentImage: UIImage? {
        if case .some(let change) = photoChange {
            return change.flatMap { UIImage(data: $0) }
        }
        if let b64 = milestone.photo_data, let data = Data(base64Encoded: b64) {
            return UIImage(data: data)
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("The moment") {
                    TextField("What happened?", text: $title)
                    TextField("A little detail (optional)", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                    DatePicker("When", selection: $date, displayedComponents: .date)
                }
                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(MilestoneCategory.allCases) { c in
                            Label(c.displayName, systemImage: c.icon).tag(c)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section("Photo") {
                    if let img = currentImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .frame(maxWidth: .infinity)
                        Button(role: .destructive) {
                            photoChange = .some(nil)
                            selectedPhoto = nil
                        } label: {
                            Label("Remove photo", systemImage: "trash")
                        }
                    }
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label(currentImage == nil ? "Add a photo" : "Change photo",
                              systemImage: currentImage == nil ? "photo.on.rectangle" : "arrow.triangle.2.circlepath")
                            .foregroundStyle(accent)
                    }
                    .onChange(of: selectedPhoto) {
                        Task {
                            if let data = try? await selectedPhoto?.loadTransferable(type: Data.self) {
                                photoChange = .some(data)
                            }
                        }
                    }
                }
                if let error {
                    Text(error).foregroundStyle(.red).font(.system(size: 13))
                }
            }
            .navigationTitle("Edit milestone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        var data: [String: Any] = [
            "title": title.trimmingCharacters(in: .whitespaces),
            "milestone_date": DateFormatter.isoDate.string(from: date),
            "category": category.rawValue,
        ]
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        data["description"] = trimmedNote.isEmpty ? NSNull() : trimmedNote
        if case .some(let change) = photoChange {
            if let imageData = change,
               let compressed = UIImage(data: imageData)?.jpegData(compressionQuality: 0.7) {
                data["photo_data"] = compressed.base64EncodedString()
            } else {
                data["photo_data"] = NSNull()
            }
        }
        Task {
            do {
                try await api.updateMilestone(id: milestone.id, data: data)
                await onSaved()
                dismiss()
            } catch {
                self.error = "Couldn't save. Try again."
                isSaving = false
            }
        }
    }
}

// MARK: - Add key date

struct AddKeyDateSheet: View {
    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss
    let person: PersonResponse
    var onSaved: () async -> Void

    @State private var title = ""
    @State private var date = Date()
    @State private var repeatsAnnually = true
    @State private var notes = ""
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("The date") {
                    TextField("What is it? (e.g. Gotcha day)", text: $title)
                        .textInputAutocapitalization(.sentences)
                    DatePicker("When", selection: $date, displayedComponents: .date)
                    Toggle("Repeats every year", isOn: $repeatsAnnually)
                }
                Section("Notes") {
                    TextField("A little detail (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
                if let error {
                    Text(error).foregroundStyle(.red).font(.system(size: 13))
                }
            }
            .navigationTitle("New key date for \(person.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        var data: [String: Any] = [
            "person_id": person.id,
            "title": title.trimmingCharacters(in: .whitespaces),
            "date": DateFormatter.isoDate.string(from: date),
            "event_type": "custom",
            "is_recurring": repeatsAnnually,
        ]
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty { data["notes"] = trimmedNotes }
        Task {
            do {
                try await api.addSpecialEvent(data)
                await onSaved()
                dismiss()
            } catch {
                self.error = "Couldn't save. Try again."
                isSaving = false
            }
        }
    }
}

// MARK: - Edit key date

struct EditKeyDateSheet: View {
    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss
    let event: SpecialEventResponse
    let personName: String
    var onSaved: () async -> Void

    @State private var title: String
    @State private var date: Date
    @State private var repeatsAnnually: Bool
    @State private var notes: String
    @State private var isSaving = false
    @State private var error: String?

    init(event: SpecialEventResponse, personName: String, onSaved: @escaping () async -> Void) {
        self.event = event
        self.personName = personName
        self.onSaved = onSaved
        _title = State(initialValue: event.title)
        _date = State(initialValue: DateFormatter.isoDate.date(from: String(event.date.prefix(10))) ?? Date())
        _repeatsAnnually = State(initialValue: (event.is_recurring ?? 0) != 0)
        _notes = State(initialValue: event.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("The date") {
                    TextField("What is it? (e.g. Gotcha day)", text: $title)
                        .textInputAutocapitalization(.sentences)
                    DatePicker("When", selection: $date, displayedComponents: .date)
                    Toggle("Repeats every year", isOn: $repeatsAnnually)
                }
                Section("Notes") {
                    TextField("A little detail (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
                if let error {
                    Text(error).foregroundStyle(.red).font(.system(size: 13))
                }
            }
            .navigationTitle("Edit key date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        var data: [String: Any] = [
            "title": title.trimmingCharacters(in: .whitespaces),
            "date": DateFormatter.isoDate.string(from: date),
            "is_recurring": repeatsAnnually,
        ]
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        data["notes"] = trimmedNotes.isEmpty ? NSNull() : trimmedNotes
        Task {
            do {
                try await api.updateSpecialEvent(id: event.id, data: data)
                await onSaved()
                dismiss()
            } catch {
                self.error = "Couldn't save. Try again."
                isSaving = false
            }
        }
    }
}

// MARK: - Edit person

struct EditPersonSheet: View {
    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss
    let person: PersonResponse
    var onSaved: () async -> Void

    @State private var name: String
    @State private var relationship: String
    @State private var hasBirthday: Bool
    @State private var birthday: Date
    @State private var avatarColor: String
    @State private var isSaving = false
    @State private var error: String?

    private let relationships = ["wife", "husband", "spouse", "partner", "son", "daughter", "parent", "sibling", "grandparent", "household", "other"]
    private let colors = ["sage", "rose", "ocean", "saffron", "mauve", "terracotta"]

    init(person: PersonResponse, onSaved: @escaping () async -> Void) {
        self.person = person
        self.onSaved = onSaved
        _name = State(initialValue: person.name)
        _relationship = State(initialValue: person.relationship ?? "other")
        let bday = person.birthday.flatMap { DateFormatter.isoDate.date(from: $0) }
        _hasBirthday = State(initialValue: bday != nil)
        _birthday = State(initialValue: bday ?? Date())
        _avatarColor = State(initialValue: person.avatar_color ?? "sage")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    Picker("Relationship", selection: $relationship) {
                        ForEach(relationships, id: \.self) { Text($0.capitalized) }
                    }
                }
                Section("Birthday") {
                    Toggle("Has a birthday set", isOn: $hasBirthday)
                    if hasBirthday {
                        DatePicker("Birthday", selection: $birthday, displayedComponents: .date)
                    }
                }
                Section("Color") {
                    HStack(spacing: 12) {
                        ForEach(colors, id: \.self) { c in
                            Circle()
                                .fill((AccentTheme(rawValue: c) ?? .sage).color)
                                .frame(width: 30, height: 30)
                                .overlay {
                                    if avatarColor == c {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .onTapGesture { avatarColor = c }
                        }
                    }
                }
                if let error {
                    Text(error).foregroundStyle(.red).font(.system(size: 13))
                }
            }
            .navigationTitle("Edit \(person.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        let data: [String: Any] = [
            "name": name.trimmingCharacters(in: .whitespaces),
            "relationship": relationship,
            "birthday": hasBirthday ? DateFormatter.isoDate.string(from: birthday) : NSNull(),
            "avatar_color": avatarColor,
        ]
        Task {
            do {
                try await api.updatePerson(id: person.id, data: data)
                await onSaved()
                dismiss()
            } catch {
                self.error = "Couldn't save. Try again."
                isSaving = false
            }
        }
    }
}

#Preview {
    NavigationStack {
        PersonDetailView(person: PersonResponse(
            id: 1, name: "Rowan", relationship: "son", birthday: "2019-04-12",
            anniversary: nil, notes: nil, user_id: nil, is_dependent: 1,
            avatar_color: "ocean", created_at: nil, gift_idea_count: 2,
            milestone_count: 3, decision_count: 1, key_date_count: 1))
    }
    .environment(APIService())
}
