import SwiftUI

struct CookView: View {
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    @Environment(APIService.self) private var api
    @State private var viewModel = CookViewModel()
    @State private var showingAIDisclosure = false
    @State private var hasAIConsent = AIConsentManager.hasConsented
    @State private var cookingRecipe: RecipeSuggestion?
    @AppStorage("cloudAIEnabled") private var cloudAIEnabled = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                headerSection
                if cloudAIEnabled { aiInputCard } else { cloudOffNote }
                filterChips
                heroRecipe
                moreIdeas
            }
            .padding(.bottom, DesignTokens.Spacing.bottomBuffer)
        }
        .background {
            if !embedded { AmbientBackground(style: .cook) }
        }
        .inlineError(viewModel.error) { viewModel.error = nil }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { PantryView() } label: {
                    Image(systemName: "cabinet")
                        .foregroundStyle(WarmPalette.ink2)
                }
                .accessibilityLabel("Pantry")
            }
            ToolbarItem(placement: .topBarTrailing) {
                AskButlerButton(prompt: "What should we make for dinner tonight?")
            }
            if !embedded {
                ToolbarItem(placement: .topBarTrailing) {
                    GlassIconButton(systemName: "gearshape", accessibilityLabel: "Concierge settings") {
                        showingAIDisclosure = true
                    }
                }
            }
        }
        .fullScreenCover(item: $cookingRecipe) { recipe in
            CookingModeView(recipe: recipe) {
                Task { await viewModel.madeRecipe(recipe, api: api) }
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
        guard cloudAIEnabled else { return }   // recipe AI sends your pantry to the cloud
        guard hasAIConsent else {
            showingAIDisclosure = true
            return
        }
        Task { await viewModel.suggest(api: api) }
    }

    // Shown in place of the AI input when the user has cloud AI off.
    private var cloudOffNote: some View {
        HStack(spacing: 12) {
            Image(systemName: "cloud.slash")
                .font(.system(size: 16))
                .foregroundStyle(WarmPalette.ink3)
            Text("Recipe suggestions are off. Turn on cloud AI in Settings → Privacy to use them.")
                .font(.flFootnote)
                .foregroundStyle(WarmPalette.ink3)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
        .padding(.bottom, 14)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TONIGHT'S DINNER")
                .font(.flOverline)
                .foregroundStyle(WarmPalette.ink3)
                .tracking(0.4)
            Text("What can I make?")
                .font(.flScreenTitle)
                .foregroundStyle(WarmPalette.ink1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
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
        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
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
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
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
                    .font(.flFootnote)
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
                                .font(.flOverline.weight(.bold))
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
                        .font(.flTitle)
                        .foregroundStyle(WarmPalette.ink1)
                    Text("\(recipe.servings) servings \u{00B7} Henry's pick")
                        .font(.flFootnote)
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
                                    .font(.flSubheadline)
                                    .foregroundStyle(WarmPalette.ink1)

                                Spacer()

                                if let qty = ingredient.quantity {
                                    Text(qty)
                                        .font(.flFootnote)
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
                            cookingRecipe = recipe
                        } label: {
                            Text("Start cooking")
                                .font(.flSubheadline.weight(.semibold))
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
                                .font(.flSubheadline.weight(.semibold))
                                .foregroundStyle(viewModel.isRecipeSaved(recipe) ? WarmPalette.good : WarmPalette.ink1)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 12)
                                .background(WarmPalette.cardSurface, in: Capsule())
                        }
                    }
                }
                .padding(18)
            }
            .clipShape(RoundedRectangle(cornerRadius: 26))
            .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: 26))
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            .padding(.bottom, 14)
        } else if viewModel.hasSearched {
            VStack(spacing: 8) {
                Image(systemName: "frying.pan")
                    .font(.system(size: 32))
                    .foregroundStyle(WarmPalette.ink4)
                Text("No recipes found. Try a different query.")
                    .font(.flSubheadline)
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
            .font(.flOverline)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(WarmPalette.cardSurface, in: Capsule())
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
                    .font(.flSubheadline.weight(.semibold))
                    .foregroundStyle(WarmPalette.ink1)
                let missing = recipe.ingredients.filter { !$0.available }.count
                Text("\(recipe.cookTime) min \u{00B7} \(missing == 0 ? "all ingredients" : "\(missing) to buy")")
                    .font(.flFootnote)
                    .foregroundStyle(WarmPalette.ink3)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(WarmPalette.ink3)
        }
        .padding(14)
        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: 20))
    }
}

#Preview {
    NavigationStack {
        CookView()
    }
    .environment(APIService())
}
