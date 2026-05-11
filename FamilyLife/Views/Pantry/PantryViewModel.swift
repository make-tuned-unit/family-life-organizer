import Foundation

@MainActor
@Observable
final class PantryViewModel {
    var items: [PantryItemResponse] = []
    var selectedLocation = "All"
    var searchText = ""
    var isLoading = false
    var error: String?

    var filteredItems: [PantryItemResponse] {
        var result = items
        if selectedLocation != "All" {
            result = result.filter { ($0.location ?? "").lowercased() == selectedLocation.lowercased() }
        }
        if !searchText.isEmpty {
            result = result.filter { $0.item.localizedCaseInsensitiveContains(searchText) }
        }
        return result
    }

    func load(api: APIService) async {
        isLoading = true
        error = nil
        do {
            items = try await api.fetchPantry()
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func addItem(_ data: [String: Any], api: APIService) async {
        do {
            try await api.addPantryItem(data)
            await load(api: api)
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }

    func deleteItem(_ id: Int, api: APIService) async {
        do {
            try await api.deletePantryItem(id: id)
            items.removeAll { $0.id == id }
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }
}
