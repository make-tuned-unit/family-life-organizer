import SwiftUI

// MARK: - Coverage Cascade (end-to-end wired)
// 1. User picks contacts from care team, sets windows + reason → sends request
// 2. Each contact gets an invite token/link → they approve a window with their time
// 3. Approval triggers notification → user sees confirmed coverage
// 4. User books their own appointment into the unlocked window

/// Seeds the cascade from a calendar event ("cover this") — the event's slot
/// becomes the proposed window and the request stays linked to the event.
struct CoveragePrefill: Identifiable {
    var eventTitle: String
    var date: String            // yyyy-MM-dd
    var startTime: String       // HH:MM
    var endTime: String         // HH:MM
    var appointmentId: Int? = nil
    var externalEventId: String? = nil
    var id: String { "\(appointmentId.map(String.init) ?? externalEventId ?? eventTitle)-\(date)-\(startTime)" }
}

struct CoverageCascadeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(APIService.self) private var api
    @Environment(AuthService.self) private var auth
    @Environment(HouseholdService.self) private var household
    @State private var currentStep: CoverageStep = .ask

    var prefill: CoveragePrefill?

    // Step 1 state. Recipients are identity-first: app users travel as user
    // ids (visibility never depends on contact display names), the whole
    // household as its group id, and only true outside contacts as contact ids.
    @State private var selectedContactIds: Set<Int> = []
    @State private var selectedUserIds: Set<Int> = []
    @State private var sendToHousehold = false
    @State private var coverageReason: String = "Watch the kids"
    @State private var candidateWindows: [WindowDraft] = []
    @State private var noteText: String = ""
    @State private var didSeedPrefill = false

    // After send
    @State private var createdRequestId: Int?
    @State private var shareURLs: [Int: URL] = [:]       // the client id the picker used -> branded link
    /// Snapshot of who the request went to, for the pending list (household
    /// fan-out means the server can add people the picker never showed).
    @State private var sentRecipients: [SentRecipient] = []
    @State private var requestDetail: APIService.CoverageDetailResponse?

    struct SentRecipient: Identifiable {
        let id: Int          // client id: -userId for app users, contact id otherwise
        let name: String
    }

    // Step 4 state
    @State private var selectedApproval: APIService.CoverageApprovalResponse?

    enum CoverageStep: Int, CaseIterable {
        case ask = 1, pending, confirmed, booking
    }

    @State private var errorMessage: String?

    var body: some View {
        Group {
            switch currentStep {
            case .ask:      askView
            case .pending:  pendingView
            case .confirmed: confirmedView
            case .booking:  bookingView
            }
        }
        .background { AmbientBackground(style: .care) }
        .task {
            guard let prefill, !didSeedPrefill else { return }
            didSeedPrefill = true
            candidateWindows = [WindowDraft(date: prefill.date, startTime: prefill.startTime,
                                            endTime: prefill.endTime, description: prefill.eventTitle)]
        }
        .inlineError(errorMessage) { errorMessage = nil }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if currentStep != .ask {
                    Button {
                        if let prev = CoverageStep(rawValue: currentStep.rawValue - 1) {
                            currentStep = prev
                        }
                    } label: {
                        Image(systemName: "chevron.left").foregroundStyle(WarmPalette.ink2)
                    }
                    .accessibilityLabel("Back")
                } else {
                    Button("Cancel") { dismiss() }.foregroundStyle(WarmPalette.ink2)
                }
            }
            ToolbarItem(placement: .principal) {
                Text("Step \(currentStep.rawValue) of 4")
                    .font(.flOverline)
                    .foregroundStyle(WarmPalette.ink3)
                    .textCase(.uppercase).tracking(0.4)
            }
        }
    }

    // MARK: - Step 1: Ask

    private var askView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                FLScreenHeader(
                    eyebrow: "New coverage request",
                    title: "Ask your care team\nto cover a time slot.",
                    subtitle: "Pick contacts, propose windows, and send. They'll get a link to approve.",
                    accent: TabAccent.care.color
                )

                // Attached event (from the calendar path)
                if let prefill {
                    HStack(spacing: 10) {
                        Image(systemName: "calendar.badge.checkmark")
                            .font(.system(size: 18)).foregroundStyle(TabAccent.care.color)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(prefill.eventTitle).font(.flSubheadline.weight(.semibold)).foregroundStyle(WarmPalette.ink1)
                            Text("\(prefill.date) · \(prefill.startTime)–\(prefill.endTime)")
                                .font(.flFootnote).foregroundStyle(WarmPalette.ink3)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(TabAccent.care.color.opacity(0.1), in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.tile))
                    .padding(.horizontal, DesignTokens.Spacing.horizontalMargin).padding(.bottom, 14)
                }

                // Care team selection — the household group, its app users, and
                // outside contacts, each carried by the id kind the server can
                // match reliably.
                sectionLabel("Who to ask")
                if household.householdUsers.isEmpty && outsideContacts.isEmpty {
                    Text("Add family members in Family > Add Family Member first.")
                        .font(.flFootnote).foregroundStyle(WarmPalette.ink3)
                        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin).padding(.bottom, 14)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            if household.householdGroup != nil && household.householdUsers.count > 1 {
                                recipientChip(name: "Whole household", initial: "⌂",
                                              selected: sendToHousehold) {
                                    sendToHousehold.toggle()
                                    if sendToHousehold { selectedUserIds.removeAll() }
                                }
                            }
                            ForEach(household.householdUsers) { user in
                                recipientChip(name: user.name,
                                              initial: household.initial(for: user.name),
                                              selected: sendToHousehold || selectedUserIds.contains(user.id)) {
                                    guard !sendToHousehold else { return }
                                    if selectedUserIds.contains(user.id) { selectedUserIds.remove(user.id) }
                                    else { selectedUserIds.insert(user.id) }
                                }
                            }
                            ForEach(outsideContacts) { contact in
                                recipientChip(name: contact.name,
                                              initial: contact.avatar_initial ?? String(contact.name.prefix(1)).uppercased(),
                                              selected: selectedContactIds.contains(contact.id)) {
                                    if selectedContactIds.contains(contact.id) { selectedContactIds.remove(contact.id) }
                                    else { selectedContactIds.insert(contact.id) }
                                }
                            }
                        }
                        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                    }
                    .padding(.bottom, 14)
                }

                // Reason
                sectionLabel("What needs coverage")
                VStack(spacing: 8) {
                    ForEach(["Watch the kids", "Watch the dog", "Cat care", "House sitting", "Plant care", "Pet sitting", "Eldercare"], id: \.self) { reason in
                        reasonChip(label: reason, icon: reasonIcon(reason), selected: coverageReason == reason)
                            .onTapGesture { coverageReason = reason }
                    }
                    // Custom
                    HStack(spacing: 10) {
                        Image(systemName: "pencil").font(.system(size: 16)).foregroundStyle(WarmPalette.ink3).frame(width: 28)
                        TextField("Custom reason...", text: $coverageReason)
                            .font(.flSubheadline).foregroundStyle(WarmPalette.ink1)
                    }
                    .padding(12)
                    .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.tile))
                }
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin).padding(.bottom, 18)

                // Windows
                sectionLabel("Candidate windows")
                VStack(spacing: 10) {
                    ForEach(candidateWindows.indices, id: \.self) { i in
                        windowEditor(index: i)
                    }
                    Button { addWindow() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus").font(.system(size: 16))
                            Text("Add a window").font(.flFootnote)
                        }
                        .foregroundStyle(WarmPalette.ink3)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .overlay(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.tile).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6])).foregroundStyle(WarmPalette.ink1.opacity(0.08)))
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin).padding(.bottom, 14)

                // Note
                VStack(alignment: .leading, spacing: 6) {
                    Text("OPTIONAL NOTE").font(.flOverline).foregroundStyle(WarmPalette.ink3).tracking(0.4)
                    TextField("Add a note for them...", text: $noteText)
                        .font(.flSubheadline).foregroundStyle(WarmPalette.ink2)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.tile))
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin).padding(.bottom, 14)

                // Send
                Button { Task { await sendRequest() } } label: {
                    HStack(spacing: 8) {
                        Text("Send request")
                        Image(systemName: "paperplane.fill").font(.system(size: 14))
                    }
                }
                .buttonStyle(.flCTA)
                .disabled(!hasRecipients || candidateWindows.isEmpty)
                .opacity(!hasRecipients || candidateWindows.isEmpty ? 0.5 : 1)
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)

                Text("They'll get a shareable link to approve.")
                    .font(.flFootnote).foregroundStyle(WarmPalette.ink3)
                    .frame(maxWidth: .infinity).padding(.top, 10).padding(.bottom, 40)
            }
        }
    }

    private var outsideContacts: [APIService.ContactResponse] {
        household.members.filter { $0.id > 0 && !household.isHouseholdMember($0.name) }
    }

    private var hasRecipients: Bool {
        sendToHousehold || !selectedUserIds.isEmpty || !selectedContactIds.isEmpty
    }

    private func sendRequest() async {
        let windows: [[String: Any]] = candidateWindows.map { w in
            ["window_date": w.date, "start_time": w.startTime, "end_time": w.endTime, "description": w.description]
        }
        // App users travel as user ids (even outside contacts that resolve to
        // one); only true non-app contacts fall back to contact ids.
        var userIds = Array(selectedUserIds)
        var contactIds: [Int] = []
        var snapshot: [SentRecipient] = []
        for uid in selectedUserIds {
            let name = household.householdUsers.first { $0.id == uid }?.name ?? "Family member"
            snapshot.append(SentRecipient(id: -uid, name: name))
        }
        for cid in selectedContactIds {
            guard let contact = household.members.first(where: { $0.id == cid }) else { continue }
            if let uid = household.userId(for: contact.name), !userIds.contains(uid) {
                userIds.append(uid)
                snapshot.append(SentRecipient(id: -uid, name: contact.name))
            } else {
                contactIds.append(cid)
                snapshot.append(SentRecipient(id: cid, name: contact.name))
            }
        }
        if sendToHousehold {
            snapshot = household.householdUsers.map { SentRecipient(id: -$0.id, name: $0.name) }
        }
        do {
            let result = try await api.createCoverageRequest(
                reason: coverageReason,
                note: noteText.isEmpty ? nil : noteText,
                windows: windows,
                contactIds: contactIds,
                userIds: sendToHousehold ? [] : userIds,
                groupId: sendToHousehold ? household.householdGroup?.id : nil,
                appointmentId: prefill?.appointmentId,
                externalEventId: prefill?.externalEventId,
                eventTitle: prefill?.eventTitle
            )
            createdRequestId = result.id
            sentRecipients = snapshot
            for rec in result.recipients {
                let key = rec.client_contact_id ?? rec.contact_id ?? rec.id
                if let s = rec.share_url, let url = URL(string: s) { shareURLs[key] = url }
                else if let url = approvalURL(token: rec.invite_token) { shareURLs[key] = url }
            }
            currentStep = .pending
        } catch {
            guard !error.isCancellation else { return }
            errorMessage = "Couldn't send the request — \(error.localizedDescription)"
        }
    }

    // MARK: - Step 2: Pending

    private var pendingView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                FLScreenHeader(
                    eyebrow: "Coverage request sent",
                    title: "Waiting for reply",
                    subtitle: "It's saved under Coverage — close this any time. Send each person their own link; they can answer without the app.",
                    accent: TabAccent.care.color
                )

                // Recipients with share buttons
                ForEach(sentRecipients) { contact in
                    let url = shareURLs[contact.id]
                    HStack(spacing: 12) {
                        FamilyAvatar(initial: household.initial(for: contact.name), size: 36, name: contact.name)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(contact.name).font(.flSubheadline.weight(.semibold))
                            HStack(spacing: 6) {
                                Circle().fill(WarmPalette.warn).frame(width: 6, height: 6)
                                Text("Pending").font(.flFootnote).foregroundStyle(WarmPalette.ink3)
                            }
                        }
                        Spacer()
                        if let url {
                            ShareLink(item: url,
                                      subject: Text("Can you help \(coverageReason.lowercased())?"),
                                      message: Text("\(auth.currentUser?.name ?? "We") could use a hand with \(coverageReason.lowercased()). Pick a time here — no app needed: \(url.absoluteString)")) {
                                Text("Send link")
                                    .font(.flCaption.weight(.semibold))
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(WarmPalette.cardSurface, in: Capsule())
                            }
                        }
                    }
                    .padding(14)
                    .flCard()
                    .padding(.horizontal, DesignTokens.Spacing.horizontalMargin).padding(.bottom, 8)
                }

                // Check for approvals
                Button {
                    Task { await checkApprovals() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 14))
                        Text("Check for approvals").font(.flSubheadline.weight(.semibold))
                    }
                    .foregroundStyle(TabAccent.care.color).frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                }
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin).padding(.top, 8)

                Button { dismiss() } label: { Text("Done for now") }
                    .buttonStyle(.flCTA)
                    .padding(.horizontal, DesignTokens.Spacing.horizontalMargin).padding(.top, 10).padding(.bottom, 40)
            }
        }
    }

    private func checkApprovals() async {
        guard let id = createdRequestId else { return }
        do {
            requestDetail = try await api.fetchCoverageDetail(id: id)
            if let detail = requestDetail, !detail.approvals.isEmpty {
                selectedApproval = detail.approvals.first
                currentStep = .confirmed
            }
        } catch {
            guard !error.isCancellation else { return }
        }
    }

    // MARK: - Step 3: Confirmed

    private var confirmedView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                if let approval = selectedApproval {
                    // Hero
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            FamilyAvatar(initial: approval.avatar_initial ?? "?", size: 36, name: approval.helper_name)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(approval.helper_name ?? "Someone") confirmed")
                                    .font(.flSubheadline.weight(.semibold))
                                Text("Coverage approved")
                                    .font(.flFootnote).foregroundStyle(WarmPalette.ink3)
                            }
                            Spacer()
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 26, height: 26).background(WarmPalette.good).clipShape(Circle())
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("CONFIRMED WINDOW").font(.flOverline).foregroundStyle(WarmPalette.good).tracking(0.4)
                            Text("\(approval.approved_date)")
                                .font(.flTitle).foregroundStyle(WarmPalette.ink1)
                            Text("\(approval.approved_start) - \(approval.approved_end)")
                                .font(.flHeadline).foregroundStyle(TabAccent.care.color)
                            if let note = approval.helper_note, !note.isEmpty {
                                Text("\"\(note)\"").font(.flSubheadline).foregroundStyle(WarmPalette.ink2).italic().padding(.top, 4)
                            }
                        }
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(WarmPalette.good.opacity(0.12))
                        .overlay(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.tile).stroke(WarmPalette.good.opacity(0.28), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.tile))
                    }
                    .padding(22)
                    .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.cardLarge))
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(LinearGradient(colors: [WarmPalette.good, .clear], startPoint: .leading, endPoint: .trailing))
                            .frame(height: 3).clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.cardLarge))
                    }
                    .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                    .padding(.top, 14).padding(.bottom, 18)

                    Button { currentStep = .booking } label: {
                        Text("Book into this window")
                    }
                    .buttonStyle(.flCTA)
                    .padding(.horizontal, DesignTokens.Spacing.horizontalMargin).padding(.bottom, 40)
                }
            }
        }
    }

    // MARK: - Step 4: Book

    @State private var bookingTitle = ""
    @State private var bookingLocation = ""

    private var bookingView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                if let approval = selectedApproval {
                    // Unlocked banner
                    HStack(spacing: 12) {
                        Image(systemName: "lock.open.fill").font(.system(size: 18)).foregroundStyle(WarmPalette.good)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Coverage confirmed - \(approval.approved_start) to \(approval.approved_end)")
                                .font(.flSubheadline.weight(.semibold)).foregroundStyle(WarmPalette.good)
                            Text("\(approval.helper_name ?? "Helper") - \(approval.approved_date)")
                                .font(.flFootnote).foregroundStyle(WarmPalette.ink3)
                        }
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(WarmPalette.good.opacity(0.14))
                    .overlay(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card).stroke(WarmPalette.good.opacity(0.32), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                    .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                    .padding(.top, 12).padding(.bottom, 14)

                    // Booking form
                    VStack(alignment: .leading, spacing: 0) {
                        Text("BOOK YOUR APPOINTMENT").font(.flOverline).foregroundStyle(TabAccent.care.color).tracking(0.4).padding(.bottom, 12)
                        VStack(spacing: 0) {
                            BookingFormField(label: "What", placeholder: "e.g. Dental cleaning", text: $bookingTitle)
                            GlassDivider()
                            BookingFormField(label: "Location", placeholder: "Optional", text: $bookingLocation)
                        }
                        HStack(spacing: 8) {
                            Button { Task { await bookAppointment(approval: approval) } } label: {
                                Text("Add to calendar")
                            }
                            .buttonStyle(.flCTA)
                            .disabled(bookingTitle.isEmpty).opacity(bookingTitle.isEmpty ? 0.5 : 1)
                        }
                        .padding(.top, 16)
                    }
                    .padding(18)
                    .flCard()
                    .padding(.horizontal, DesignTokens.Spacing.horizontalMargin).padding(.bottom, 40)
                }
            }
        }
    }

    private func bookAppointment(approval: APIService.CoverageApprovalResponse) async {
        let appointment: [String: Any] = [
            "title": bookingTitle,
            "appointment_date": approval.approved_date,
            "appointment_time": approval.approved_start,
            "location": bookingLocation,
            "person_tags": [auth.currentUser?.name ?? "Me"],
            "category": "personal"
        ]
        do {
            try await api.addAppointment(appointment)
            NotificationService.shared.scheduleCoverageBooked(title: bookingTitle, date: approval.approved_date, time: approval.approved_start)
            dismiss()
        } catch {
            guard !error.isCancellation else { return }
            errorMessage = "Couldn't add it to the calendar — \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    /// Fallback only — the server normally returns the branded kinrows.com link.
    private func approvalURL(token: String) -> URL? {
        URL(string: "\(api.baseURL)/c/\(token)")
    }

    private func addWindow() {
        let cal = Calendar.current
        let date = cal.date(byAdding: .day, value: candidateWindows.count + 1, to: Date()) ?? Date()
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        candidateWindows.append(WindowDraft(date: fmt.string(from: date), startTime: "09:00", endTime: "15:00", description: ""))
    }

    private func reasonIcon(_ reason: String) -> String {
        switch reason {
        case "Watch the kids": "figure.and.child.holdinghands"
        case "Watch the dog": "dog.fill"
        case "Cat care": "cat.fill"
        case "House sitting": "house.fill"
        case "Plant care": "leaf.fill"
        case "Pet sitting": "pawprint.fill"
        case "Eldercare": "heart.fill"
        default: "pencil"
        }
    }

    private func recipientChip(name: String, initial: String, selected: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if initial == "⌂" {
                    Image(systemName: "house.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TabAccent.care.color)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(TabAccent.care.color.opacity(0.14)))
                } else {
                    FamilyAvatar(initial: initial, size: 28, name: name)
                }
                Text(name)
                    .font(.flFootnote.weight(.semibold))
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(TabAccent.care.color)
                }
            }
            .padding(.vertical, 8).padding(.leading, 8).padding(.trailing, 14)
            .background(WarmPalette.cardSurface, in: Capsule())
            .overlay(Capsule().stroke(selected ? TabAccent.care.color.opacity(0.3) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.flOverline).foregroundStyle(WarmPalette.ink3).tracking(0.4)
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin).padding(.bottom, 8)
    }

    private func reasonChip(label: String, icon: String, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(selected ? TabAccent.care.color : WarmPalette.ink3).frame(width: 28)
            Text(label).font(.flSubheadline.weight(selected ? .semibold : .regular)).foregroundStyle(selected ? WarmPalette.ink1 : WarmPalette.ink2)
            Spacer()
            if selected {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 18)).foregroundStyle(TabAccent.care.color)
            }
        }
        .padding(12)
        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.tile))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.tile).stroke(selected ? TabAccent.care.color.opacity(0.3) : .clear, lineWidth: 1))
    }

    private func windowEditor(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Window \(index + 1)").font(.flFootnote.weight(.semibold))
                Spacer()
                Button { candidateWindows.remove(at: index) } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(WarmPalette.ink4)
                }
            }
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Date").font(.flOverline).foregroundStyle(WarmPalette.ink3)
                    TextField("YYYY-MM-DD", text: $candidateWindows[index].date)
                        .font(.system(size: 14, design: .monospaced))
                        .padding(8)
                        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Start").font(.flOverline).foregroundStyle(WarmPalette.ink3)
                    TextField("HH:MM", text: $candidateWindows[index].startTime)
                        .font(.system(size: 14, design: .monospaced))
                        .padding(8)
                        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("End").font(.flOverline).foregroundStyle(WarmPalette.ink3)
                    TextField("HH:MM", text: $candidateWindows[index].endTime)
                        .font(.system(size: 14, design: .monospaced))
                        .padding(8)
                        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small))
                }
            }
            TextField("What's happening? (optional)", text: $candidateWindows[index].description)
                .font(.flFootnote).foregroundStyle(WarmPalette.ink3)
        }
        .padding(14)
        .flCard()
    }
}

// Keep old name as typealias so CalendarView reference compiles
typealias CareCascadeView = CoverageCascadeView

// MARK: - Data Types

struct WindowDraft {
    var date: String
    var startTime: String
    var endTime: String
    var description: String
}

struct BookingFormField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack {
            Text(label).font(.flFootnote).foregroundStyle(WarmPalette.ink3).frame(width: 70, alignment: .leading)
            TextField(placeholder, text: $text).font(.flSubheadline.weight(.medium)).foregroundStyle(WarmPalette.ink1)
        }
        .padding(.vertical, 10)
    }
}

#Preview("Coverage Cascade") {
    NavigationStack { CoverageCascadeView() }
        .environment(APIService())
        .environment(AuthService())
        .environment(HouseholdService())
}
