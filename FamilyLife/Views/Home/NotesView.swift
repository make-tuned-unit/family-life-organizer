import SwiftUI

// MARK: - Model (GET /api/notes)

struct Note: Codable, Identifiable {
    let id: Int
    var title: String?
    var body: String?
    var color: String?
    var pinned: Int?
    var user_id: Int?
    var shared_scope: String?
    var group_id: Int?
    var can_collaborate: Int?
    var author_name: String?
    var shared_group_name: String?
    var updated_at: String?

    var isPinned: Bool { (pinned ?? 0) == 1 }
    var scope: String { shared_scope ?? "private" }
    var isShared: Bool { scope != "private" }
    var canCollaborate: Bool { (can_collaborate ?? 0) == 1 }
}

// MARK: - Store

@MainActor
@Observable
final class NotesStore {
    var notes: [Note] = []
    var isLoading = false
    var error: String?

    func load(api: APIService) async {
        isLoading = true
        defer { isLoading = false }
        do { notes = try await api.fetchNotes() }
        catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }

    func delete(api: APIService, id: Int) async {
        do { try await api.deleteNote(id: id); await load(api: api) }
        catch { self.error = error.localizedDescription }
    }
}

// MARK: - List

struct NotesView: View {
    @Environment(APIService.self) private var api
    @Environment(AuthService.self) private var auth
    @State private var store = NotesStore()
    @State private var editing: Note?
    @State private var showingAdd = false

    private var myId: Int? { auth.currentUser?.id }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                if store.notes.isEmpty && !store.isLoading {
                    emptyState
                } else {
                    ForEach(store.notes) { note in
                        Button { editing = note } label: {
                            NoteCard(note: note, isOwner: note.user_id == myId)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            if note.user_id == myId {
                                Button(role: .destructive) {
                                    Task { await store.delete(api: api, id: note.id) }
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            .padding(.top, 14)
            .padding(.bottom, DesignTokens.Spacing.bottomBuffer)
        }
        .background { AmbientBackground(style: .home) }
        .navigationTitle("Notes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAdd = true } label: { Image(systemName: "square.and.pencil") }
                    .foregroundStyle(WarmPalette.ink2)
                    .accessibilityLabel("New note")
            }
        }
        .sheet(isPresented: $showingAdd) {
            NoteEditorView(existing: nil) { await store.load(api: api) }
        }
        .sheet(item: $editing) { note in
            NoteEditorView(existing: note) { await store.load(api: api) }
        }
        .task { await store.load(api: api) }
        .refreshable { await store.load(api: api) }
    }

    private var emptyState: some View {
        WarmEmptyState(
            title: "Jot down your first note",
            systemImage: "note.text",
            description: "Notes are private until you share them.",
            actionLabel: "New note",
            action: { showingAdd = true }
        )
    }
}

private struct NoteCard: View {
    let note: Note
    let isOwner: Bool

    private var shareLabel: (String, String) {
        switch note.scope {
        case "household": return ("house.fill", "Household")
        case "group": return ("person.2.fill", "Shared")
        default: return ("lock.fill", "Private")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(note.title?.isEmpty == false ? note.title! : "Untitled")
                    .font(.flHeadline)
                    .foregroundStyle(WarmPalette.ink1)
                    .lineLimit(1)
                Spacer()
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 11)).foregroundStyle(AccentTheme.saffron.color)
                }
            }
            if let b = note.body, !b.isEmpty {
                Text(b)
                    .font(.flFootnote)
                    .foregroundStyle(WarmPalette.ink3)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            HStack(spacing: 5) {
                Image(systemName: shareLabel.0).font(.system(size: 10))
                if !isOwner, let author = note.author_name, !author.isEmpty {
                    Text("Shared by \(author)").font(.flCaption2.weight(.medium))
                    if note.canCollaborate {
                        Text("\u{00B7} you can edit").font(.flCaption2)
                    }
                } else {
                    Text(shareLabel.1).font(.flCaption2.weight(.medium))
                }
            }
            .foregroundStyle(note.isShared ? AccentTheme.sage.color : WarmPalette.ink4)
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
    }
}

// MARK: - Editor

struct NoteEditorView: View {
    let existing: Note?
    let onSave: () async -> Void

    @Environment(APIService.self) private var api
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var bodyText = ""
    @State private var scope = "private"
    @State private var selectedGroupId: Int?
    @State private var pinned = false
    @State private var collaborate = false
    @State private var groups: [APIService.GroupResponse] = []
    @State private var saving = false

    private var householdGroup: APIService.GroupResponse? {
        groups.first { $0.group_type == "household" }
    }
    private var clanGroups: [APIService.GroupResponse] {
        groups.filter { $0.group_type != "household" }
    }

    // New notes: you're the owner. Existing: owner only if it's yours.
    private var isOwner: Bool {
        guard let e = existing else { return true }
        return e.user_id == auth.currentUser?.id
    }
    // Non-owners may edit content only when the note was shared to them with
    // collaboration enabled. Everyone else sees it read-only.
    private var canEdit: Bool {
        isOwner || (existing?.isShared == true && existing?.canCollaborate == true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title).disabled(!canEdit)
                    TextField("Write a note\u{2026}", text: $bodyText, axis: .vertical)
                        .lineLimit(4...12).disabled(!canEdit)
                }

                if isOwner {
                    Section("Sharing") {
                        Picker("Visible to", selection: $scope) {
                            Label("Private", systemImage: "lock.fill").tag("private")
                            if householdGroup != nil {
                                Label("Household", systemImage: "house.fill").tag("household")
                            }
                            if !clanGroups.isEmpty {
                                Label("A group", systemImage: "person.2.fill").tag("group")
                            }
                        }
                        if scope == "group" {
                            Picker("Group", selection: $selectedGroupId) {
                                ForEach(clanGroups) { g in Text(g.name).tag(Optional(g.id)) }
                            }
                        }
                        if scope != "private" {
                            Toggle("Allow editing (Collaborate)", isOn: $collaborate)
                        }
                    }

                    Section {
                        Toggle("Pin to top", isOn: $pinned)
                    }
                } else {
                    Section {
                        Label(canEdit ? "Shared with you \u{00B7} you can edit" : "Shared with you \u{00B7} view only",
                              systemImage: canEdit ? "pencil" : "eye")
                            .font(.flFootnote)
                            .foregroundStyle(WarmPalette.ink3)
                    }
                }
            }
            .navigationTitle(existing == nil ? "New Note" : (isOwner ? "Edit Note" : "Note"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(canEdit ? "Cancel" : "Done") { dismiss() } }
                if canEdit {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { Task { await save() } }
                            .disabled(saving || (title.isEmpty && bodyText.isEmpty))
                    }
                }
            }
            .task {
                if isOwner { groups = (try? await api.fetchGroups()) ?? [] }
                hydrate()
            }
        }
    }

    private func hydrate() {
        guard let e = existing else { return }
        title = e.title ?? ""
        bodyText = e.body ?? ""
        scope = e.scope
        selectedGroupId = e.group_id
        pinned = e.isPinned
        collaborate = e.canCollaborate
    }

    private func save() async {
        saving = true
        defer { saving = false }
        // Owners send the full payload; collaborators send content only (the
        // backend ignores non-content fields from non-owners anyway).
        var data: [String: Any] = ["title": title, "body": bodyText]
        if isOwner {
            data["pinned"] = pinned
            data["shared_scope"] = scope
            data["can_collaborate"] = (scope != "private") && collaborate
            if scope == "group", let gid = selectedGroupId ?? clanGroups.first?.id {
                data["group_id"] = gid
            }
        }
        do {
            if let e = existing {
                try await api.updateNote(id: e.id, data: data)
            } else {
                try await api.addNote(data)
            }
            await onSave()
            dismiss()
        } catch { /* surfaced on next load */ }
    }
}
