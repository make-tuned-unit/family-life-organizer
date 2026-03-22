import SwiftUI

struct CookView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(APIService.self) private var api
    @State private var viewModel = CookViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Query input
                VStack(spacing: 12) {
                    Text("What should we make?")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 12) {
                        TextField("e.g. Quick dinner for the family", text: $viewModel.query)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { getSuggestions() }

                        Button {
                            getSuggestions()
                        } label: {
                            Image(systemName: "sparkles")
                                .font(.title3)
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 36)
                                .background(.teal)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .disabled(viewModel.query.isEmpty || viewModel.isLoading)
                    }
                }
                .padding(.horizontal)

                if viewModel.isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Checking your pantry and finding recipes...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, DesignTokens.Spacing.large)
                }

                // Recipe cards
                ForEach(viewModel.recipes) { recipe in
                    RecipeCard(recipe: recipe) {
                        Task { await viewModel.madeRecipe(recipe, api: api) }
                    } onAddToGroceries: { items in
                        Task { await viewModel.addMissingToGroceries(items, api: api) }
                    }
                    .padding(.horizontal)
                }

                if !viewModel.isLoading && viewModel.recipes.isEmpty && viewModel.hasSearched {
                    ContentUnavailableView(
                        "No Recipes Found",
                        systemImage: "frying.pan",
                        description: Text("Try a different query")
                    )
                }
            }
            .padding(.vertical)
        }
        .background { AmbientBackground(style: .cook) }
        .navigationTitle("Cook")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func getSuggestions() {
        Task { await viewModel.suggest(api: api) }
    }
}

struct RecipeCard: View {
    let recipe: RecipeSuggestion
    let onMade: () -> Void
    let onAddToGroceries: ([String]) -> Void

    @State private var isExpanded = false
    @State private var addedToGroceries = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(recipe.name)
                        .font(.headline)
                    HStack(spacing: 12) {
                        Label("\(recipe.cookTime) min", systemImage: "clock")
                        Label(recipe.difficulty, systemImage: "chart.bar")
                        Label("\(recipe.servings) servings", systemImage: "person.2")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }

            // Ingredients
            VStack(alignment: .leading, spacing: 6) {
                Text("Ingredients")
                    .font(.subheadline.weight(.semibold))
                ForEach(recipe.ingredients) { ingredient in
                    HStack(spacing: 8) {
                        Image(systemName: ingredient.available ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(ingredient.available ? .green : .red)
                            .font(.caption)
                        Text(ingredient.name)
                            .font(.subheadline)
                            .strikethrough(!ingredient.available, color: .red)
                        Spacer()
                        if let qty = ingredient.quantity {
                            Text(qty)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Steps (expandable)
            if isExpanded {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Steps")
                        .font(.subheadline.weight(.semibold))
                    ForEach(Array(recipe.steps.enumerated()), id: \.offset) { idx, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(idx + 1).")
                                .font(.caption.bold())
                                .foregroundStyle(.teal)
                                .frame(width: 20, alignment: .trailing)
                            Text(step)
                                .font(.subheadline)
                        }
                    }
                }
            }

            // Missing ingredients action
            let missing = recipe.ingredients.filter { !$0.available }
            if !missing.isEmpty {
                Button {
                    onAddToGroceries(missing.map(\.name))
                    addedToGroceries = true
                } label: {
                    Label(
                        addedToGroceries ? "Added to Groceries" : "Add \(missing.count) Missing to Groceries",
                        systemImage: addedToGroceries ? "checkmark.circle.fill" : "cart.badge.plus"
                    )
                    .font(.caption)
                }
                .buttonStyle(.flSecondary)
                .disabled(addedToGroceries)
            }

            // Actions
            HStack {
                Button {
                    withAnimation { isExpanded.toggle() }
                } label: {
                    Label(isExpanded ? "Less" : "Steps", systemImage: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.subheadline)
                }
                .buttonStyle(.flSecondary)

                Spacer()

                Button {
                    onMade()
                } label: {
                    Label("I Made This", systemImage: "checkmark")
                        .font(.subheadline)
                }
                .buttonStyle(.flPrimary(tint: TabAccent.cook.color))
            }
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .flCard(tint: TabAccent.cook.color)
    }
}

#Preview {
    NavigationStack {
        CookView()
    }
    .environment(APIService())
}
