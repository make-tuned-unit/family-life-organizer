import SwiftUI

struct HouseholdView: View {
    @Environment(APIService.self) private var api
    @Environment(AuthService.self) private var auth
    @Environment(HouseholdService.self) private var household
    @Environment(\.dismiss) private var dismiss

    @State private var showingAddMember = false
    @State private var editingMember: APIService.ContactResponse?
    @State private var showingAddresses = false
    @State private var error: String?

    private var otherMembers: [APIService.ContactResponse] {
        guard let user = auth.currentUser else { return household.members }
        return household.members.filter {
            $0.name.localizedCaseInsensitiveCompare(user.name) != .orderedSame
            && $0.name.localizedCaseInsensitiveCompare(user.username) != .orderedSame
        }
    }

    var body: some View {
        List {
            membersSection
            addressSection
        }
        .scrollContentBackground(.hidden)
        .background { AmbientBackground(style: .settings) }
        .navigationTitle("My Household")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAddMember = true } label: {
                    Image(systemName: "person.badge.plus")
                        .foregroundStyle(TabAccent.home.color)
                }
            }
        }
        .sheet(isPresented: $showingAddMember) {
            EditMemberSheet(member: nil) { await household.reload(api: api) }
        }
        .sheet(item: $editingMember) { member in
            EditMemberSheet(member: member) { await household.reload(api: api) }
        }
        .sheet(isPresented: $showingAddresses) {
            NavigationStack {
                FamilyAddressesView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") { showingAddresses = false }
                                .foregroundStyle(WarmPalette.ink2)
                        }
                    }
            }
        }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
        .task { await household.reload(api: api) }
    }

    // MARK: - Members

    @ViewBuilder
    private var membersSection: some View {
        Section {
            // Current user row (non-editable here)
            if let user = auth.currentUser {
                HStack(spacing: 12) {
                    FamilyAvatar(initial: String(user.name.prefix(1)).uppercased(), size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.name)
                            .font(.system(size: 15, weight: .semibold))
                        Text("You")
                            .font(.system(size: 12))
                            .foregroundStyle(WarmPalette.ink3)
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
            }

            // Family contacts (exclude current user — already shown above)
            ForEach(otherMembers) { member in
                Button { editingMember = member } label: {
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
                        VStack(alignment: .trailing, spacing: 2) {
                            if let phone = member.phone, !phone.isEmpty {
                                Label(phone, systemImage: "phone")
                                    .font(.system(size: 11))
                                    .foregroundStyle(WarmPalette.ink3)
                            }
                            if let email = member.email, !email.isEmpty {
                                Label(email, systemImage: "envelope")
                                    .font(.system(size: 11))
                                    .foregroundStyle(WarmPalette.ink3)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
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
                    Text("Add your family here and they'll appear everywhere in the app.")
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

    private var addressSection: some View {
        Section("Home Address") {
            Button { showingAddresses = true } label: {
                Label("Manage Addresses", systemImage: "mappin.and.ellipse")
                    .foregroundStyle(TabAccent.home.color)
            }
        }
    }

    // MARK: - Actions

    private func deleteMember(_ member: APIService.ContactResponse) async {
        do {
            try await api.deleteContact(id: member.id)
            await household.reload(api: api)
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
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
            if let existing = member {
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

#Preview {
    NavigationStack {
        HouseholdView()
    }
    .environment(APIService())
    .environment(AuthService())
    .environment(HouseholdService())
}
