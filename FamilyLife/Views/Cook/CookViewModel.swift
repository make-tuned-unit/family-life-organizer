import Foundation

@MainActor
@Observable
final class CookViewModel {
    var query = ""
    var recipes: [RecipeSuggestion] = []
    var isLoading = false
    var hasSearched = false
    var error: String?

    func suggest(api: APIService) async {
        guard !query.isEmpty else { return }
        isLoading = true
        hasSearched = true
        error = nil
        do {
            recipes = try await api.suggestRecipes(query: query)
        } catch {
            guard !error.isCancellation else { return }
            // Keep previous recipes visible, but say the search failed.
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func madeRecipe(_ recipe: RecipeSuggestion, api: APIService) async {
        let ingredients = recipe.ingredients.filter(\.available).map { $0.name }
        do {
            try await api.deductIngredients(ingredients: ingredients)
        } catch {
            guard !error.isCancellation else { return }
            self.error = "Couldn't update the pantry — \(error.localizedDescription)"
        }
    }

    private var savedRecipeNames: Set<String> {
        Set((UserDefaults.standard.stringArray(forKey: "saved_recipes") ?? []))
    }

    func saveRecipe(_ recipe: RecipeSuggestion) {
        var saved = UserDefaults.standard.stringArray(forKey: "saved_recipes") ?? []
        if !saved.contains(recipe.name) {
            saved.append(recipe.name)
            UserDefaults.standard.set(saved, forKey: "saved_recipes")
        }
    }

    func isRecipeSaved(_ recipe: RecipeSuggestion) -> Bool {
        savedRecipeNames.contains(recipe.name)
    }

    func addMissingToGroceries(_ items: [String], api: APIService) async {
        var failed: [String] = []
        for item in items {
            do {
                try await api.addGrocery(item: item)
            } catch {
                guard !error.isCancellation else { return }
                failed.append(item)
            }
        }
        if !failed.isEmpty {
            error = "Couldn't add \(failed.joined(separator: ", ")) to groceries"
        }
    }
}

struct RecipeSuggestion: Codable, Identifiable {
    var id: String { name }
    let name: String
    let cookTime: Int
    let difficulty: String
    let servings: Int
    let ingredients: [RecipeIngredient]
    let steps: [String]

    enum CodingKeys: String, CodingKey {
        case name
        case cookTime = "cook_time"
        case difficulty, servings, ingredients, steps
    }

    // The backend forwards raw AI-extracted JSON: any field may be missing or
    // arrive as a string ("30 min"). One malformed recipe must not sink all three.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        cookTime = Self.lenientInt(c, .cookTime) ?? 0
        difficulty = (try? c.decode(String.self, forKey: .difficulty)) ?? "Easy"
        servings = Self.lenientInt(c, .servings) ?? 0
        ingredients = (try? c.decode([RecipeIngredient].self, forKey: .ingredients)) ?? []
        steps = (try? c.decode([String].self, forKey: .steps)) ?? []
    }

    private static func lenientInt(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int? {
        if let i = try? c.decode(Int.self, forKey: key) { return i }
        if let d = try? c.decode(Double.self, forKey: key) { return Int(d) }
        if let s = try? c.decode(String.self, forKey: key) {
            return Int(s.filter(\.isNumber))
        }
        return nil
    }
}

struct RecipeIngredient: Codable, Identifiable {
    var id: String { name }
    let name: String
    let quantity: String?
    let available: Bool

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        quantity = try? c.decode(String.self, forKey: .quantity)
        available = (try? c.decode(Bool.self, forKey: .available))
            ?? ((try? c.decode(Int.self, forKey: .available)).map { $0 != 0 } ?? false)
    }
}
