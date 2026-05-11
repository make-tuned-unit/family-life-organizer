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
            members = try await api.fetchContacts()
        } catch {
            guard !error.isCancellation else { isLoading = false; return }
        }
        isLoaded = true
        isLoading = false
    }

    func reload(api: APIService) async {
        isLoading = false // allow forced reload
        await load(api: api)
    }

    /// Lookup a member by name (case-insensitive prefix match for person_tags)
    func member(named name: String) -> APIService.ContactResponse? {
        members.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    /// Avatar initial for a given name — uses contact data if available, falls back to first letter
    func initial(for name: String) -> String {
        if let contact = member(named: name) {
            return contact.avatar_initial ?? String(contact.name.prefix(1)).uppercased()
        }
        return String(name.prefix(1)).uppercased()
    }
}
