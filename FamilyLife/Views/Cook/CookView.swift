import SwiftUI

struct CookView: View {
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    @Environment(APIService.self) private var api
    @State private var viewModel = CookViewModel()
    @State private var showingAIDisclosure = false
    @State private var hasAIConsent = AIConsentManager.hasConsented

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                headerSection
                aiInputCard
                filterChips
                heroRecipe
                moreIdeas
            }
            .padding(.bottom, DesignTokens.Spacing.bottomBuffer)
        }
        .background {
            if !embedded { AmbientBackground(style: .cook) }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .toolbar {
            if !embedded {
                ToolbarItem(placement: .topBarTrailing) {
                    GlassIconButton(systemName: "gearshape") {}
                }
            }
        }
        .sheet(isPresented: $showingAIDisclosure) {
            AIDisclosureView(
                onAccept: {
                    AIConsentManager.grant()
                    hasAIConsent = true
                    showingAIDisclosure = false
                    getSuggestions()
                },
                onDecline: {
                    showingAIDisclosure = false
                }
            )
        }
    }

    private func getSuggestions() {
        guard hasAIConsent else {
            showingAIDisclosure = true
            return
        }
        Task { await viewModel.suggest(api: api) }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TONIGHT'S DINNER")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WarmPalette.ink3)
                .tracking(0.4)
            Text("What can I make?")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(WarmPalette.ink1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 14)
    }

    // MARK: - AI Input

    private var aiInputCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "star.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(
                    LinearGradient(colors: [WarmPalette.peach, AccentTheme.terracotta.color], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .clipShape(Circle())

            TextField("Something quick with chicken...", text: $viewModel.query)
                .font(.system(size: 15))
                .foregroundStyle(WarmPalette.ink1)
                .onSubmit { getSuggestions() }

            Button(action: getSuggestions) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(TabAccent.cook.color)
            }
            .disabled(viewModel.query.isEmpty || viewModel.isLoading)
        }
        .padding(14)
        .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: DesignTokens.CornerRadius.card))
        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
        .padding(.bottom, 14)
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                WarmChip(label: "Under 30 min", isActive: true)
                WarmChip(label: "Use spinach")
                WarmChip(label: "Family-friendly")
                WarmChip(label: "Vegetarian")
            }
            .padding(.horizontal, 22)
        }
        .padding(.bottom, 14)
    }

    // MARK: - Hero Recipe

    @ViewBuilder
    private var heroRecipe: some View {
        if viewModel.isLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text("Checking your pantry and finding recipes...")
                    .font(.system(size: 13))
                    .foregroundStyle(WarmPalette.ink3)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else if let recipe = viewModel.recipes.first {
            VStack(spacing: 0) {
                // Recipe image placeholder
                ZStack(alignment: .topLeading) {
                    LinearGradient(
                        colors: [WarmPalette.sunset, AccentTheme.terracotta.color],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(height: 180)
                    .overlay {
                        // Subtle stripe pattern
                        GeometryReader { geo in
                            Path { path in
                                for i in stride(from: 0, to: geo.size.width + geo.size.height, by: 14) {
                                    path.move(to: CGPoint(x: i, y: 0))
                                    path.addLine(to: CGPoint(x: i - geo.size.height, y: geo.size.height))
                                }
                            }
                            .stroke(.white.opacity(0.06), lineWidth: 6)
                        }
                    }

                    // Tags overlay
                    HStack(spacing: 6) {
                        RecipeTag(text: "\(recipe.cookTime) min")
                        RecipeTag(text: recipe.difficulty)
                    }
                    .padding(12)

                    // Availability badge
                    let missing = recipe.ingredients.filter { !$0.available }.count
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(missing == 0 ? "You have it all" : "\(missing) to buy")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .textCase(.uppercase)
                                .tracking(0.4)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(missing == 0 ? WarmPalette.good.opacity(0.95) : WarmPalette.warn.opacity(0.95))
                                .clipShape(Capsule())
                                .padding(12)
                        }
                    }
                    .frame(height: 180)
                }

                // Recipe details
                VStack(alignment: .leading, spacing: 4) {
                    Text(recipe.name)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(WarmPalette.ink1)
                    Text("\(recipe.servings) servings \u{00B7} Henry's pick")
                        .font(.system(size: 13))
                        .foregroundStyle(WarmPalette.ink3)
                        .padding(.bottom, 14)

                    // Ingredients
                    VStack(spacing: 6) {
                        ForEach(recipe.ingredients) { ingredient in
                            HStack(spacing: 10) {
                                Image(systemName: ingredient.available ? "checkmark" : "plus")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(ingredient.available ? WarmPalette.good : WarmPalette.bad)
                                    .frame(width: 18, height: 18)
                                    .background((ingredient.available ? WarmPalette.good : WarmPalette.bad).opacity(0.18))
                                    .clipShape(Circle())

                                Text(ingredient.name)
                                    .font(.system(size: 15))
                                    .foregroundStyle(WarmPalette.ink1)

                                Spacer()

                                if let qty = ingredient.quantity {
                                    Text(qty)
                                        .font(.system(size: 13))
                                        .foregroundStyle(WarmPalette.ink3)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(.bottom, 14)

                    // Actions
                    HStack(spacing: 8) {
                        Button {
                            Task { await viewModel.madeRecipe(recipe, api: api) }
                        } label: {
                            Text("Start cooking")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(WarmPalette.cream1)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(WarmPalette.ink1)
                                .clipShape(Capsule())
                        }
                        Button {
                            viewModel.saveRecipe(recipe)
                        } label: {
                            Text(viewModel.isRecipeSaved(recipe) ? "Saved" : "Save")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(viewModel.isRecipeSaved(recipe) ? WarmPalette.good : WarmPalette.ink1)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 12)
                                .glassEffect(.regular.tint(.white.opacity(0.05)), in: .capsule)
                        }
                    }
                }
                .padding(18)
            }
            .clipShape(RoundedRectangle(cornerRadius: 26))
            .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 26))
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            .padding(.bottom, 14)
        } else if viewModel.hasSearched {
            VStack(spacing: 8) {
                Image(systemName: "frying.pan")
                    .font(.system(size: 32))
                    .foregroundStyle(WarmPalette.ink4)
                Text("No recipes found. Try a different query.")
                    .font(.system(size: 15))
                    .foregroundStyle(WarmPalette.ink3)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        }
    }

    // MARK: - More Ideas

    @ViewBuilder
    private var moreIdeas: some View {
        let others = Array(viewModel.recipes.dropFirst())
        if !others.isEmpty {
            WarmSectionHeader(title: "\(others.count) more idea\(others.count == 1 ? "" : "s")")
                .padding(.bottom, 8)

            VStack(spacing: 10) {
                ForEach(others) { recipe in
                    RecipeRowCard(recipe: recipe) {
                        Task { await viewModel.madeRecipe(recipe, api: api) }
                    } onAddToGroceries: { items in
                        Task { await viewModel.addMissingToGroceries(items, api: api) }
                    }
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
        }
    }
}

// MARK: - Recipe Tag

struct RecipeTag: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassEffect(.regular.tint(.black.opacity(0.35)), in: .capsule)
    }
}

// MARK: - Recipe Row Card

struct RecipeRowCard: View {
    let recipe: RecipeSuggestion
    let onMade: () -> Void
    let onAddToGroceries: ([String]) -> Void

    private var color: Color {
        let missing = recipe.ingredients.filter { !$0.available }.count
        if missing == 0 { return WarmPalette.good }
        if missing <= 2 { return AccentTheme.saffron.color }
        return AccentTheme.terracotta.color
    }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(colors: [color, color.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 48, height: 48)
                .overlay {
                    // Subtle stripe
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.white.opacity(0.1))
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WarmPalette.ink1)
                let missing = recipe.ingredients.filter { !$0.available }.count
                Text("\(recipe.cookTime) min \u{00B7} \(missing == 0 ? "all ingredients" : "\(missing) to buy")")
                    .font(.system(size: 13))
                    .foregroundStyle(WarmPalette.ink3)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(WarmPalette.ink3)
        }
        .padding(14)
        .glassEffect(.regular.tint(color.opacity(0.04)), in: .rect(cornerRadius: 20))
    }
}

#Preview {
    NavigationStack {
        CookView()
    }
    .environment(APIService())
}
