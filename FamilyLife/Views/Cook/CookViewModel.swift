import Foundation

@Observable
final class CookViewModel {
    var query = ""
    var recipes: [RecipeSuggestion] = []
    var isLoading = false
    var hasSearched = false

    func suggest(api: APIService) async {
        guard !query.isEmpty else { return }
        isLoading = true
        hasSearched = true
        do {
            recipes = try await api.suggestRecipes(query: query)
        } catch {
            recipes = []
        }
        isLoading = false
    }

    func madeRecipe(_ recipe: RecipeSuggestion, api: APIService) async {
        let ingredients = recipe.ingredients.filter(\.available).map { $0.name }
        do {
            try await api.deductIngredients(ingredients: ingredients)
        } catch {}
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
        for item in items {
            do {
                try await api.addGrocery(item: item)
            } catch {}
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
}

struct RecipeIngredient: Codable, Identifiable {
    var id: String { name }
    let name: String
    let quantity: String?
    let available: Bool
}
