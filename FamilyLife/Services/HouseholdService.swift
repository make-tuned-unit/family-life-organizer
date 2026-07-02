import SwiftUI

@MainActor
@Observable
final class HouseholdService {
    private(set) var members: [APIService.ContactResponse] = []
    private(set) var householdGroup: APIService.GroupResponse?
    /// Lowercased names of people in the user's own household group (not clans/cross-household circles).
    private(set) var householdMemberNames: Set<String> = []
    /// Maps member names (lowercased) to their users table ID (for messaging)
    private(set) var userIdsByName: [String: Int] = [:]
    /// Actual users (id + display name) in the user's own household group,
    /// excluding the current user. Unlike `householdMembers` this never depends
    /// on a contact's name matching the group member's name — it's the group
    /// roster itself, so it's stable regardless of month, contacts, or naming.
    struct HouseholdUser: Identifiable, Hashable {
        let id: Int
        let name: String
    }
    private(set) var householdUsers: [HouseholdUser] = []
    private(set) var isLoaded = false
    private var isLoading = false

    func load(api: APIService, profileCache: ProfileImageCache? = nil, currentUserId: Int? = nil) async {
        guard !isLoading else { return }
        isLoading = true
        do {
            // Load contacts + household group users so @mentions work for everyone
            async let contactsReq = api.fetchContacts()
            async let groupsReq = api.fetchGroups()

            let contacts = (try? await contactsReq) ?? []
            let groups = (try? await groupsReq) ?? []

            // Cache the household group for invite code display
            householdGroup = groups.first { $0.group_type == "household" }

            // Start with contacts
            var combined = contacts
            let contactFirstNames = Set(contacts.map { $0.name.lowercased().split(separator: " ").first.map(String.init) ?? $0.name.lowercased() })

            // Add users from ALL groups who aren't already in contacts
            var nameToUserId: [String: Int] = [:]
            var addedNames = Set(contacts.map { $0.name.lowercased() })
            var addedUserIds = Set<Int>()
            var householdNames = Set<String>()
            var householdUserList: [HouseholdUser] = []
            for group in groups {
                let isHouseholdGroup = group.group_type == "household"
                if let groupMembers = try? await api.fetchGroupMembers(groupId: group.id) {
                    profileCache?.loadFromHousehold(groupMembers)

                    for member in groupMembers {
                        let name = member.displayName
                        let nameLC = name.lowercased()
                        // Record household membership before any skip logic so the current
                        // user and existing contacts are still captured as household members.
                        if isHouseholdGroup {
                            householdNames.insert(nameLC)
                            if let uid = member.user_id, uid != currentUserId,
                               !householdUserList.contains(where: { $0.id == uid }) {
                                householdUserList.append(HouseholdUser(id: uid, name: name))
                            }
                        }
                        // Track user_id for messaging
                        if let uid = member.user_id {
                            nameToUserId[nameLC] = uid
                            // Also map matching contacts to this user_id
                            for contact in contacts {
                                let contactFirst = contact.name.lowercased().split(separator: " ").first.map(String.init) ?? ""
                                let memberFirst = nameLC.split(separator: " ").first.map(String.init) ?? nameLC
                                if contactFirst == memberFirst || contact.name.lowercased() == nameLC {
                                    nameToUserId[contact.name.lowercased()] = uid
                                    addedUserIds.insert(uid)
                                }
                            }
                        }
                        // Skip current user
                        if let uid = member.user_id, uid == currentUserId { continue }
                        // Skip if this user_id is already represented by a contact
                        if let uid = member.user_id, addedUserIds.contains(uid) { continue }
                        // Skip exact name match
                        guard !addedNames.contains(nameLC) else { continue }
                        // Skip first-name match (e.g. "Jesse" matches contact "Jesse Sharratt")
                        let firstName = nameLC.split(separator: " ").first.map(String.init) ?? nameLC
                        guard !contactFirstNames.contains(firstName) else {
                            if let uid = member.user_id { addedUserIds.insert(uid) }
                            continue
                        }
                        addedNames.insert(nameLC)
                        if let uid = member.user_id { addedUserIds.insert(uid) }
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
            userIdsByName = nameToUserId
            householdMemberNames = householdNames
            householdUsers = householdUserList.sorted { $0.name < $1.name }
        } catch {
            guard !error.isCancellation else { isLoading = false; return }
        }
        isLoaded = true
        isLoading = false
    }

    func reload(api: APIService, profileCache: ProfileImageCache? = nil, currentUserId: Int? = nil) async {
        isLoading = false
        await load(api: api, profileCache: profileCache, currentUserId: currentUserId)
    }

    func member(named name: String) -> APIService.ContactResponse? {
        members.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    /// True when `name` belongs to the user's own household (not just a clan/circle).
    func isHouseholdMember(_ name: String) -> Bool {
        householdMemberNames.contains(name.lowercased())
    }

    /// Household-only members (used for assignment — clans are for sharing, not assigning).
    var householdMembers: [APIService.ContactResponse] {
        members.filter { isHouseholdMember($0.name) }
    }

    func userId(for name: String) -> Int? {
        userIdsByName[name.lowercased()]
    }

    func initial(for name: String) -> String {
        if let contact = member(named: name) {
            return contact.avatar_initial ?? String(contact.name.prefix(1)).uppercased()
        }
        return String(name.prefix(1)).uppercased()
    }
}
