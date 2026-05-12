import SwiftUI

@MainActor
@Observable
final class HouseholdService {
    private(set) var members: [APIService.ContactResponse] = []
    private(set) var isLoaded = false
    private var isLoading = false

    func load(api: APIService) async {
        guard !isLoading else { return }
        isLoading = true
        do {
            // Load contacts + household group users so @mentions work for everyone
            async let contactsReq = api.fetchContacts()
            async let groupsReq = api.fetchGroups()

            let contacts = (try? await contactsReq) ?? []
            let groups = (try? await groupsReq) ?? []

            // Start with contacts
            var combined = contacts
            let contactNames = Set(contacts.map { $0.name.lowercased() })

            // Add users from household/family groups who aren't already in contacts
            for group in groups where group.group_type == "household" || group.group_type == "family" {
                if let groupMembers = try? await api.fetchGroupMembers(groupId: group.id) {
                    for member in groupMembers {
                        let name = member.displayName
                        guard !contactNames.contains(name.lowercased()) else { continue }
                        // Create a ContactResponse-compatible entry for the user
                        combined.append(APIService.ContactResponse(
                            id: -(member.user_id ?? member.id),
                            name: name,
                            relationship: "household",
                            phone: nil,
                            email: nil,
                            birthday: nil,
                            avatar_initial: member.avatar_initial,
                            notes: nil,
                            added_by: nil,
                            created_at: nil
                        ))
                    }
                }
            }

            members = combined
        } catch {
            guard !error.isCancellation else { isLoading = false; return }
        }
        isLoaded = true
        isLoading = false
    }

    func reload(api: APIService) async {
        isLoading = false
        await load(api: api)
    }

    func member(named name: String) -> APIService.ContactResponse? {
        members.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    func initial(for name: String) -> String {
        if let contact = member(named: name) {
            return contact.avatar_initial ?? String(contact.name.prefix(1)).uppercased()
        }
        return String(name.prefix(1)).uppercased()
    }
}
