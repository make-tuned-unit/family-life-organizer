import SwiftUI

// MARK: - Section shown on EventDetailView

// Lists items attached to an event. Tapping a row opens the item's full detail
// in the relevant feature; long-press removes it. The "+" opens the picker.
struct EventAttachmentsSection: View {
    let appointmentId: Int

    @Environment(APIService.self) private var api
    @State private var attachments: [EventAttachmentResponse] = []
    @State private var loading = true
    @State private var showingPicker = false
    @State private var routed: EventAttachmentResponse?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                WarmSectionHeader(title: "Attached")
                Spacer()
                Button { showingPicker = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(TabAccent.calendar.color)
                }
            }
            .padding(.bottom, 8)

            if loading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else if attachments.isEmpty {
                Button { showingPicker = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(TabAccent.calendar.color)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Attach something")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(WarmPalette.ink1)
                            Text("Link a task, list, note, decision, receipt, or trip.")
                                .font(.system(size: 13))
                                .foregroundStyle(WarmPalette.ink3)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 14)
                    .contentShape(Rectangle())
                    .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(attachments.enumerated()), id: \.element.id) { index, att in
                        if index > 0 { GlassDivider() }
                        attachmentRow(att)
                    }
                }
                .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
        .padding(.bottom, 14)
        .task { await load() }
        .sheet(isPresented: $showingPicker) {
            AttachmentPickerView(appointmentId: appointmentId, existing: attachments) {
                await load()
            }
        }
        .sheet(item: $routed) { att in
            AttachmentDestinationView(attachment: att)
        }
    }

    @ViewBuilder
    private func attachmentRow(_ att: EventAttachmentResponse) -> some View {
        let kind = att.kind
        Button { routed = att } label: {
            HStack(spacing: 12) {
                Image(systemName: kind?.icon ?? "paperclip")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(kind?.color ?? WarmPalette.ink2)
                    .frame(width: 30, height: 30)
                    .background((kind?.color ?? WarmPalette.ink2).opacity(0.12), in: RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 2) {
                    Text(att.title ?? kind?.label ?? "Item")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(WarmPalette.ink1)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Text(kind?.label ?? att.attachment_type.capitalized)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(kind?.color ?? WarmPalette.ink3)
                        if let sub = att.subtitle, !sub.isEmpty {
                            Text("·").foregroundStyle(WarmPalette.ink3)
                            Text(sub)
                                .font(.system(size: 12))
                                .foregroundStyle(WarmPalette.ink3)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WarmPalette.ink3)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                Task { await remove(att) }
            } label: {
                Label("Remove Attachment", systemImage: "trash")
            }
        }
    }

    private func load() async {
        loading = true
        attachments = (try? await api.fetchEventAttachments(appointmentId: appointmentId)) ?? []
        loading = false
    }

    private func remove(_ att: EventAttachmentResponse) async {
        try? await api.deleteEventAttachment(appointmentId: appointmentId, attachmentId: att.id)
        await load()
    }
}

// MARK: - Picker

private struct PickItem: Identifiable {
    let id: Int
    let title: String
    let subtitle: String?
}

// Choose an entity type, then pick one of its items to attach to the event.
struct AttachmentPickerView: View {
    let appointmentId: Int
    let existing: [EventAttachmentResponse]
    var onDone: () async -> Void

    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss

    @State private var kind: AttachmentKind = .note
    @State private var items: [PickItem] = []
    @State private var loading = false
    @State private var saving = false

    private var attachedIds: Set<Int> {
        Set(existing.filter { $0.attachment_type == kind.rawValue }.map { $0.attachment_id })
    }

    private var available: [PickItem] {
        items.filter { !attachedIds.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Type", selection: $kind) {
                    ForEach(AttachmentKind.allCases) { k in
                        Text(k.label).tag(k)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                .padding(.vertical, 12)

                if loading {
                    Spacer(); ProgressView(); Spacer()
                } else if available.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: kind.icon)
                            .font(.system(size: 32))
                            .foregroundStyle(WarmPalette.ink3)
                        Text("Nothing to attach")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(WarmPalette.ink2)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(available.enumerated()), id: \.element.id) { index, item in
                                if index > 0 { GlassDivider() }
                                Button { Task { await attach(item) } } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: kind.icon)
                                            .font(.system(size: 15))
                                            .foregroundStyle(kind.color)
                                            .frame(width: 28, height: 28)
                                            .background(kind.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.title)
                                                .font(.system(size: 15, weight: .medium))
                                                .foregroundStyle(WarmPalette.ink1)
                                                .lineLimit(1)
                                            if let sub = item.subtitle, !sub.isEmpty {
                                                Text(sub)
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(WarmPalette.ink3)
                                                    .lineLimit(1)
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: "plus.circle.fill")
                                            .foregroundStyle(kind.color)
                                    }
                                    .padding(.vertical, 11)
                                    .padding(.horizontal, 14)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(saving)
                            }
                        }
                        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                        .padding(.bottom, 20)
                    }
                }
            }
            .background { AmbientBackground(style: .calendar) }
            .navigationTitle("Attach Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: kind) { await loadItems() }
        }
    }

    private func loadItems() async {
        loading = true
        defer { loading = false }
        do {
            switch kind {
            case .task:
                items = try await api.fetchTasks(status: "active").map {
                    PickItem(id: $0.id, title: $0.title, subtitle: $0.category.capitalized)
                }
            case .note:
                items = try await api.fetchNotes().map {
                    PickItem(id: $0.id, title: ($0.title?.isEmpty == false ? $0.title! : "Untitled note"),
                             subtitle: $0.body)
                }
            case .list:
                items = try await api.fetchLists().map {
                    PickItem(id: $0.id, title: $0.name, subtitle: $0.list_type)
                }
            case .decision:
                items = try await api.fetchDecisions().map {
                    PickItem(id: $0.id, title: $0.title, subtitle: $0.decision_type)
                }
            case .receipt:
                items = try await api.fetchReceipts().map {
                    PickItem(id: $0.id, title: $0.merchant, subtitle: String(format: "$%.2f", $0.amount))
                }
            case .trip:
                items = try await api.fetchTrips().map {
                    PickItem(id: $0.id, title: $0.destination, subtitle: $0.traveler)
                }
            case .itinerary:
                items = try await api.fetchItineraries().map {
                    PickItem(id: $0.id, title: $0.title, subtitle: $0.start_date)
                }
            }
        } catch {
            items = []
        }
    }

    private func attach(_ item: PickItem) async {
        saving = true
        defer { saving = false }
        do {
            try await api.addEventAttachment(appointmentId: appointmentId, type: kind.rawValue, attachmentId: item.id)
            await onDone()
            dismiss()
        } catch { }
    }
}

// MARK: - Destination router

// Fetches the full source entity for a tapped attachment and presents the
// feature's real detail view. Notes bring their own NavigationStack (the editor);
// everything else is wrapped here so it gets a title bar + Done button.
struct AttachmentDestinationView: View {
    let attachment: EventAttachmentResponse

    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .loading
    @State private var decision: DecisionResponse?
    @State private var receipt: ReceiptResponse?
    @State private var itinerary: ItineraryResponse?
    @State private var note: Note?
    @State private var trip: TripResponse?
    @State private var list: APIService.ListResponse?
    @State private var task: TaskResponse?

    enum Phase { case loading, ready, notFound }

    var body: some View {
        Group {
            if let note {
                NoteEditorView(existing: note, onSave: {})
            } else {
                NavigationStack {
                    wrapped
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { dismiss() }
                            }
                        }
                }
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private var wrapped: some View {
        if let task {
            AttachedTaskDetail(task: task)
        } else if let decision {
            DecisionDetailView(decision: decision)
        } else if let receipt {
            ReceiptDetailView(receipt: receipt) {
                Task { try? await api.deleteReceipt(id: receipt.id); dismiss() }
            }
        } else if let itinerary {
            ItineraryDetailView(itinerary: itinerary)
        } else if let trip {
            AttachedTripDetail(trip: trip)
        } else if let list {
            ScrollView {
                ListDetailSection(list: list, api: api)
                    .padding(.top, 8)
            }
            .background { AmbientBackground(style: .home) }
            .navigationTitle(list.name)
            .navigationBarTitleDisplayMode(.inline)
        } else if phase == .notFound {
            ContentUnavailableView("Item Unavailable",
                                   systemImage: "questionmark.folder",
                                   description: Text("This attachment may have been deleted."))
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func load() async {
        let id = attachment.attachment_id
        do {
            switch attachment.attachment_type {
            case "decision":  decision = try await api.fetchDecision(id: id)
            case "receipt":   receipt = try await api.fetchReceipts().first { $0.id == id }
            case "itinerary": itinerary = try await api.fetchItineraries().first { $0.id == id }
            case "note":      note = try await api.fetchNotes().first { $0.id == id }
            case "trip":      trip = try await api.fetchTrips().first { $0.id == id }
            case "list":      list = try await api.fetchLists().first { $0.id == id }
            case "task":
                async let active = api.fetchTasks(status: "active")
                async let done = api.fetchTasks(status: "completed")
                task = (try await (active + done)).first { $0.id == id }
            default: break
            }
        } catch { }
        let found = decision != nil || receipt != nil || itinerary != nil || note != nil || trip != nil || list != nil || task != nil
        phase = found ? .ready : .notFound
    }
}

// Minimal detail for an attached task (Tasks live in the Lists tab, no standalone screen).
private struct AttachedTaskDetail: View {
    let task: TaskResponse

    private var isDone: Bool { task.status != "active" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24))
                        .foregroundStyle(isDone ? WarmPalette.good : WarmPalette.ink4)
                    Text(task.title)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(WarmPalette.ink1)
                        .strikethrough(isDone, color: WarmPalette.ink4)
                }

                row("folder", task.category.capitalized)
                row("flag.fill", task.priority.capitalized + " priority")
                if let assignee = task.assigned_to, !assignee.isEmpty {
                    row("person.fill", "Assigned to \(assignee.capitalized)")
                }
                if let due = task.due_date, !due.isEmpty {
                    row("calendar", "Due \(due)")
                }
                if let desc = task.description, !desc.isEmpty {
                    row("text.alignleft", desc)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
            .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.cardLarge))
            .padding(DesignTokens.Spacing.horizontalMargin)
        }
        .background { AmbientBackground(style: .calendar) }
        .navigationTitle("Task")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func row(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(TabAccent.calendar.color)
                .frame(width: 22)
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(WarmPalette.ink2)
        }
    }
}

// Minimal detail for an attached trip (the Trips feature has no standalone screen).
private struct AttachedTripDetail: View {
    let trip: TripResponse

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(trip.destination)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(WarmPalette.ink1)

                row("person.fill", trip.traveler)
                if let origin = trip.origin, !origin.isEmpty {
                    row("arrow.up.forward", "From \(origin)")
                }
                if let purpose = trip.purpose, !purpose.isEmpty {
                    row("text.alignleft", purpose)
                }
                row("flag.fill", trip.status.capitalized)
                if let eta = trip.eta_minutes {
                    row("clock", "ETA \(eta) min")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
            .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.cardLarge))
            .padding(DesignTokens.Spacing.horizontalMargin)
        }
        .background { AmbientBackground(style: .calendar) }
        .navigationTitle("Trip")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func row(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(TabAccent.calendar.color)
                .frame(width: 22)
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(WarmPalette.ink2)
        }
    }
}
