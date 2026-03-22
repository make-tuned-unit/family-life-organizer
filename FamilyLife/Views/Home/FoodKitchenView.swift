import SwiftUI

enum FoodTab: String, CaseIterable {
    case groceries = "Groceries"
    case cook = "Cook"
}

struct FoodKitchenView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: FoodTab = .groceries

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(FoodTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, DesignTokens.Spacing.sectionTop)

            switch selectedTab {
            case .groceries:
                GroceryListContent()
            case .cook:
                CookContent()
            }
        }
        .background { AmbientBackground(style: .cook) }
        .navigationTitle("Food & Kitchen")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
            }
        }
    }
}

/// Grocery list content without its own nav title/toolbar (embedded in FoodKitchenView)
struct GroceryListContent: View {
    @Environment(APIService.self) private var api
    @State private var viewModel = GroceryListViewModel()
    @State private var newItem = ""
    @State private var searchText = ""
    @State private var groceryToMigrate: GroceryResponse?
    @State private var showingPantryMigrate = false

    private var filteredGroceries: [GroceryResponse] {
        if searchText.isEmpty { return viewModel.groceries }
        return viewModel.groceries.filter { $0.item.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Quick add
            HStack(spacing: 12) {
                TextField("Add item...", text: $newItem)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addItem() }
                Button { addItem() } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.teal)
                }
                .disabled(newItem.isEmpty)
            }
            .padding()

            if filteredGroceries.isEmpty && !viewModel.isLoading {
                ContentUnavailableView("All Done", systemImage: "cart.badge.checkmark", description: Text("No items on your list"))
                    .frame(maxHeight: .infinity)
            } else {
                List {
                    let grouped = Dictionary(grouping: filteredGroceries) { $0.category ?? "Other" }
                    ForEach(grouped.keys.sorted(), id: \.self) { category in
                        Section(category) {
                            ForEach(grouped[category] ?? []) { grocery in
                                HStack {
                                    Text(grocery.item)
                                    Spacer()
                                    if let qty = grocery.quantity, qty != "1" {
                                        Text("x\(qty)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button {
                                        groceryToMigrate = grocery
                                        showingPantryMigrate = true
                                    } label: {
                                        Label("Purchased", systemImage: "checkmark")
                                    }
                                    .tint(.green)
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .searchable(text: $searchText, prompt: "Search groceries")
            }
        }
        .overlay {
            if viewModel.isLoading && viewModel.groceries.isEmpty {
                ProgressView()
            }
        }
        .refreshable {
            await viewModel.load(api: api)
        }
        .alert("Add to Pantry?", isPresented: $showingPantryMigrate) {
            Button("Yes") {
                if let grocery = groceryToMigrate {
                    Task {
                        try? await api.addPantryItem(["item": grocery.item, "category": grocery.category ?? "Other", "location": "pantry"])
                        await viewModel.complete(grocery.id, api: api)
                    }
                }
            }
            Button("No") {
                if let grocery = groceryToMigrate {
                    Task { await viewModel.complete(grocery.id, api: api) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Move \"\(groceryToMigrate?.item ?? "")\" to your pantry inventory?")
        }
        .task {
            await viewModel.load(api: api)
        }
    }

    private func addItem() {
        let item = newItem.trimmingCharacters(in: .whitespaces)
        guard !item.isEmpty else { return }
        newItem = ""
        Task { await viewModel.add(item: item, api: api) }
    }
}

/// Cook content without its own nav title/toolbar (embedded in FoodKitchenView)
struct CookContent: View {
    @Environment(APIService.self) private var api
    @State private var viewModel = CookViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 12) {
                    Text("What should we make?")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 12) {
                        TextField("e.g. Quick dinner for the family", text: $viewModel.query)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { getSuggestions() }

                        Button { getSuggestions() } label: {
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

                ForEach(viewModel.recipes) { recipe in
                    RecipeCard(recipe: recipe) {
                        Task { await viewModel.madeRecipe(recipe, api: api) }
                    } onAddToGroceries: { items in
                        Task { await viewModel.addMissingToGroceries(items, api: api) }
                    }
                    .padding(.horizontal)
                }

                if !viewModel.isLoading && viewModel.recipes.isEmpty && viewModel.hasSearched {
                    ContentUnavailableView("No Recipes Found", systemImage: "frying.pan", description: Text("Try a different query"))
                }
            }
            .padding(.vertical)
        }
    }

    private func getSuggestions() {
        Task { await viewModel.suggest(api: api) }
    }
}

#Preview {
    NavigationStack {
        FoodKitchenView()
    }
    .environment(APIService())
}
