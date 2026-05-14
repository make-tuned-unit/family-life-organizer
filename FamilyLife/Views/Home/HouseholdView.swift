import SwiftUI
import MapKit

struct HouseholdView: View {
    @Environment(APIService.self) private var api
    @Environment(AuthService.self) private var auth
    @Environment(HouseholdService.self) private var household
    @Environment(\.dismiss) private var dismiss

    @State private var showingAddMember = false
    @State private var editingMember: APIService.ContactResponse?
    @State private var showingAddAddress = false
    @State private var showingJoinSheet = false
    @State private var showingRenameSheet = false
    @State private var addresses: [FamilyAddressResponse] = []
    @State private var error: String?
    @State private var copiedCode = false

    private var otherMembers: [APIService.ContactResponse] {
        guard let user = auth.currentUser else { return household.members }
        return household.members.filter {
            $0.name.localizedCaseInsensitiveCompare(user.name) != .orderedSame
            && $0.name.localizedCaseInsensitiveCompare(user.username) != .orderedSame
        }
    }

    var body: some View {
        List {
            nameSection
            inviteSection
            membersSection
            addressSection
        }
        .scrollContentBackground(.hidden)
        .background { AmbientBackground(style: .settings) }
        .navigationTitle(household.householdGroup?.name ?? "My Household")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showingAddMember = true } label: {
                        Label("Add Member", systemImage: "person.badge.plus")
                    }
                    Button { showingRenameSheet = true } label: {
                        Label("Rename Household", systemImage: "pencil")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(TabAccent.home.color)
                }
            }
        }
        .sheet(isPresented: $showingAddMember) {
            EditMemberSheet(member: nil) { await household.reload(api: api, currentUserId: auth.currentUser?.id) }
        }
        .sheet(item: $editingMember) { member in
            EditMemberSheet(member: member) { await household.reload(api: api, currentUserId: auth.currentUser?.id) }
        }
        .sheet(isPresented: $showingJoinSheet) {
            JoinHouseholdSheet {
                await household.reload(api: api, currentUserId: auth.currentUser?.id)
            }
        }
        .sheet(isPresented: $showingAddAddress) {
            AddAddressView { address in
                Task { await addAddress(address) }
            }
        }
        .sheet(item: $editingAddress) { addr in
            EditAddressSheet(address: addr) {
                await loadAddresses()
            }
        }
        .alert("Rename Household", isPresented: $showingRenameSheet) {
            TextField("Household name", text: $pendingName)
            Button("Save") {
                Task { await renameHousehold() }
            }
            Button("Cancel", role: .cancel) { pendingName = "" }
        } message: {
            Text("Choose a name for your household (e.g. The Fairbanks)")
        }
        .onChange(of: showingRenameSheet) { _, showing in
            if showing { pendingName = household.householdGroup?.name ?? "" }
        }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
        .task {
            await household.reload(api: api, currentUserId: auth.currentUser?.id)
            await loadAddresses()
        }
    }

    // MARK: - Name

    @State private var pendingName = ""

    private func renameHousehold() async {
        guard let groupId = household.householdGroup?.id, !pendingName.isEmpty else { return }
        do {
            try await api.updateGroup(id: groupId, data: ["name": pendingName])
            await household.reload(api: api, currentUserId: auth.currentUser?.id)
            pendingName = ""
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Name

    @ViewBuilder
    private var nameSection: some View {
        Section {
            Button { showingRenameSheet = true } label: {
                HStack {
                    Image(systemName: "house.fill")
                        .foregroundStyle(TabAccent.home.color)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(household.householdGroup?.name ?? "My Household")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(WarmPalette.ink1)
                        Text("Tap to rename")
                            .font(.system(size: 12))
                            .foregroundStyle(WarmPalette.ink4)
                    }
                    Spacer()
                    Image(systemName: "pencil")
                        .font(.system(size: 14))
                        .foregroundStyle(WarmPalette.ink4)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Invite Code

    @ViewBuilder
    private var inviteSection: some View {
        if let code = household.householdGroup?.invite_code {
            Section {
                // One-tap copy
                Button {
                    UIPasteboard.general.string = code
                    copiedCode = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copiedCode = false
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Invite Code")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(WarmPalette.ink3)
                            Text(code)
                                .font(.system(size: 22, weight: .bold, design: .monospaced))
                                .foregroundStyle(WarmPalette.ink1)
                                .tracking(2)
                        }
                        Spacer()
                        Image(systemName: copiedCode ? "checkmark.circle.fill" : "doc.on.doc")
                            .font(.system(size: 18))
                            .foregroundStyle(copiedCode ? WarmPalette.good : WarmPalette.ink3)
                    }
                }
                .buttonStyle(.plain)

                // Send via iMessage / share sheet
                ShareLink(
                    item: "Join my household on Kinrows! Use invite code: \(code)",
                    subject: Text("Join my household"),
                    message: Text("I set up our family organizer. Use this code to join: \(code)")
                ) {
                    Label("Send invite to partner", systemImage: "message.fill")
                        .foregroundStyle(TabAccent.home.color)
                }
            } header: {
                Text("Invite")
            } footer: {
                Text("Tap the code to copy it, or send it directly via text.")
            }
        }

        Section {
            Button { showingJoinSheet = true } label: {
                Label("Join another household", systemImage: "person.badge.plus")
                    .foregroundStyle(TabAccent.home.color)
            }
        } footer: {
            Text("If your partner already created a household, enter their invite code to join it.")
        }
    }

    // MARK: - Members

    @ViewBuilder
    private var membersSection: some View {
        Section {
            // Current user row — tap to edit your contact info
            if let user = auth.currentUser {
                let myContact = household.member(named: user.name)
                Button {
                    // Edit own contact info — use existing contact or create new
                    if let contact = myContact {
                        editingMember = contact
                    } else {
                        editingMember = APIService.ContactResponse(
                            id: 0, name: user.name, relationship: nil,
                            phone: nil, email: nil, birthday: nil,
                            avatar_initial: nil, notes: nil, added_by: nil, created_at: nil
                        )
                    }
                } label: {
                    HStack(spacing: 12) {
                        ProfileAvatar(size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(WarmPalette.ink1)
                            if let phone = myContact?.phone, !phone.isEmpty {
                                Text(phone)
                                    .font(.system(size: 12))
                                    .foregroundStyle(WarmPalette.ink3)
                            } else {
                                Text("Tap to add your contact info")
                                    .font(.system(size: 12))
                                    .foregroundStyle(WarmPalette.ink4)
                            }
                        }
                        Spacer()
                        Image(systemName: "pencil")
                            .font(.system(size: 12))
                            .foregroundStyle(WarmPalette.ink4)
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }

            // Family contacts (exclude current user — already shown above)
            ForEach(otherMembers) { member in
                MemberRow(member: member) { editingMember = member }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await deleteMember(member) }
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
            }

            if otherMembers.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.2.slash")
                        .font(.system(size: 28))
                        .foregroundStyle(WarmPalette.ink4)
                    Text("No family members yet")
                        .font(.system(size: 14))
                        .foregroundStyle(WarmPalette.ink3)
                    Text("Share your invite code or add family members manually.")
                        .font(.system(size: 12))
                        .foregroundStyle(WarmPalette.ink4)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
        } header: {
            Text("Family Members")
        } footer: {
            Text("Add family members once and they appear across Calendar, Care, Decisions, and everywhere else.")
        }
    }

    // MARK: - Address

    @State private var editingAddress: FamilyAddressResponse?

    @ViewBuilder
    private var addressSection: some View {
        Section {
            ForEach(addresses) { addr in
                Button { editingAddress = addr } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(addr.name)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(WarmPalette.ink1)
                            if let address = addr.address, !address.isEmpty {
                                Text(address)
                                    .font(.system(size: 13))
                                    .foregroundStyle(WarmPalette.ink3)
                            }
                        }
                        Spacer()
                        Image(systemName: "pencil")
                            .font(.system(size: 12))
                            .foregroundStyle(WarmPalette.ink4)
                    }
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { await deleteAddress(addr.id) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }

            Button { showingAddAddress = true } label: {
                Label("Add address", systemImage: "plus.circle")
                    .foregroundStyle(TabAccent.home.color)
            }
        } header: {
            Text("Addresses")
        } footer: {
            Text("Tap to edit, swipe to delete. Saved locations appear in Trips and Calendar.")
        }
    }

    // MARK: - Actions

    private func loadAddresses() async {
        do { addresses = try await api.fetchFamilyAddresses() } catch {}
    }

    private func addAddress(_ data: [String: Any]) async {
        do {
            try await api.addFamilyAddress(data)
            await loadAddresses()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func deleteAddress(_ id: Int) async {
        do {
            try await api.deleteFamilyAddress(id: id)
            addresses.removeAll { $0.id == id }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func deleteMember(_ member: APIService.ContactResponse) async {
        do {
            try await api.deleteContact(id: member.id)
            await household.reload(api: api, currentUserId: auth.currentUser?.id)
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    }
}

// MARK: - Join Household Sheet

struct JoinHouseholdSheet: View {
    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var isJoining = false
    @State private var error: String?

    let onJoined: () async -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Enter invite code", text: $code)
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.center)
                } header: {
                    Text("Invite Code")
                } footer: {
                    Text("Ask your partner for their household invite code. You'll find it in their Household settings.")
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground(style: .settings) }
            .navigationTitle("Join Household")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Couldn't join", isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(WarmPalette.ink2)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join") {
                        Task { await join() }
                    }
                    .disabled(code.count < 4 || isJoining)
                }
            }
        }
    }

    private func join() async {
        isJoining = true
        do {
            _ = try await api.joinGroup(inviteCode: code.trimmingCharacters(in: .whitespaces))
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            await onJoined()
            dismiss()
        } catch {
            self.error = "Invalid invite code. Check with your partner and try again."
            isJoining = false
        }
    }
}

// MARK: - Edit / Add Member Sheet

struct EditMemberSheet: View {
    let member: APIService.ContactResponse?
    let onComplete: () async -> Void

    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var relationship: String
    @State private var phone: String
    @State private var email: String
    @State private var birthday: String
    @State private var isSaving = false

    private let relationships = [
        "wife", "husband", "partner",
        "son", "daughter", "child",
        "mom", "dad",
        "sister", "brother",
        "mother-in-law", "father-in-law",
        "sister-in-law", "brother-in-law",
        "grandparent", "aunt", "uncle", "cousin",
        "friend", "babysitter", "nanny", "other"
    ]

    init(member: APIService.ContactResponse?, onComplete: @escaping () async -> Void) {
        self.member = member
        self.onComplete = onComplete
        _name = State(initialValue: member?.name ?? "")
        _relationship = State(initialValue: member?.relationship ?? "partner")
        _phone = State(initialValue: member?.phone ?? "")
        _email = State(initialValue: member?.email ?? "")
        _birthday = State(initialValue: member?.birthday ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Person") {
                    TextField("Name", text: $name)
                    Picker("Relationship", selection: $relationship) {
                        ForEach(relationships, id: \.self) { rel in
                            Text(rel.capitalized).tag(rel)
                        }
                    }
                }
                Section("Contact Info") {
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                }
                Section("Details") {
                    TextField("Birthday (YYYY-MM-DD)", text: $birthday)
                        .keyboardType(.numbersAndPunctuation)
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground(style: .settings) }
            .navigationTitle(member == nil ? "Add Member" : "Edit Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(WarmPalette.ink2)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(member == nil ? "Add" : "Save") {
                        Task { await save() }
                    }
                    .disabled(name.isEmpty || isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        var data: [String: Any] = [
            "name": name,
            "relationship": relationship
        ]
        if !phone.isEmpty { data["phone"] = phone }
        if !email.isEmpty { data["email"] = email }
        if !birthday.isEmpty { data["birthday"] = birthday }

        do {
            if let existing = member, existing.id != 0 {
                try await api.updateContact(id: existing.id, data: data)
            } else {
                let _ = try await api.addContact(data)
            }
            await onComplete()
            dismiss()
        } catch {
            guard !error.isCancellation else { return }
            isSaving = false
        }
    }
}

// MARK: - Edit Address Sheet

struct EditAddressSheet: View {
    let address: FamilyAddressResponse
    let onSaved: () async -> Void

    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var addressQuery: String
    @State private var lat: Double
    @State private var lng: Double
    @State private var locationCompleter = LocationCompleter()
    @State private var showingSuggestions = false
    @State private var isSaving = false

    init(address: FamilyAddressResponse, onSaved: @escaping () async -> Void) {
        self.address = address
        self.onSaved = onSaved
        _name = State(initialValue: address.name)
        _addressQuery = State(initialValue: address.address ?? "")
        _lat = State(initialValue: address.lat)
        _lng = State(initialValue: address.lng)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                }

                Section("Address") {
                    TextField("Search for a new address...", text: $addressQuery)
                        .onChange(of: addressQuery) {
                            locationCompleter.search(query: addressQuery)
                            showingSuggestions = !addressQuery.isEmpty
                        }

                    if showingSuggestions && !locationCompleter.results.isEmpty {
                        ForEach(locationCompleter.results, id: \.self) { result in
                            Button {
                                let full = [result.title, result.subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
                                addressQuery = full
                                showingSuggestions = false
                                resolveCoordinates(for: result)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.title)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                    if !result.subtitle.isEmpty {
                                        Text(result.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(WarmPalette.ink3)
                                    }
                                }
                            }
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        Task {
                            try? await api.deleteFamilyAddress(id: address.id)
                            await onSaved()
                            dismiss()
                        }
                    } label: {
                        Label("Delete Address", systemImage: "trash")
                            .foregroundStyle(WarmPalette.bad)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground(style: .settings) }
            .navigationTitle("Edit Address")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(WarmPalette.ink2)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(name.isEmpty || isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        do {
            var data: [String: Any] = ["name": name, "lat": lat, "lng": lng]
            if !addressQuery.isEmpty { data["address"] = addressQuery }
            try await api.updateFamilyAddress(id: address.id, data: data)
            await onSaved()
            dismiss()
        } catch {
            isSaving = false
        }
    }

    private func resolveCoordinates(for completion: MKLocalSearchCompletion) {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        search.start { response, _ in
            guard let item = response?.mapItems.first else { return }
            lat = item.placemark.coordinate.latitude
            lng = item.placemark.coordinate.longitude
        }
    }
}

// MARK: - Member Row with hyperlinked contact info

struct MemberRow: View {
    let member: APIService.ContactResponse
    var onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            HStack(spacing: 12) {
                FamilyAvatar(
                    initial: member.avatar_initial ?? String(member.name.prefix(1)).uppercased(),
                    size: 36
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WarmPalette.ink1)
                    if let rel = member.relationship {
                        Text(rel.capitalized)
                            .font(.system(size: 12))
                            .foregroundStyle(WarmPalette.ink3)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if let phone = member.phone, !phone.isEmpty {
                        Link(destination: URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })")!) {
                            Label(phone, systemImage: "phone.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(TabAccent.home.color)
                        }
                    }
                    if let email = member.email, !email.isEmpty {
                        Link(destination: URL(string: "mailto:\(email)")!) {
                            Label(email, systemImage: "envelope.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(TabAccent.home.color)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        HouseholdView()
    }
    .environment(APIService())
    .environment(AuthService())
    .environment(HouseholdService())
    .environment(ProfileImageCache())
}
