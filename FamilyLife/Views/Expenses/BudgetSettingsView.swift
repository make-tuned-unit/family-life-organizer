import SwiftUI

struct BudgetSettingsView: View {
    @Environment(APIService.self) private var api
    @State private var categories: [APIService.BudgetCategoryResponse] = []
    @State private var isLoading = false
    @State private var showingAdd = false
    @State private var editingCategory: APIService.BudgetCategoryResponse?
    @State private var error: String?

    var body: some View {
        List {
            Section {
                ForEach(categories) { cat in
                    Button { editingCategory = cat } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(cat.color.map { Color(hex: $0) } ?? TabAccent.expenses.color)
                                .frame(width: 12, height: 12)
                            Text(cat.name)
                                .font(.flSubheadline.weight(.medium))
                                .foregroundStyle(WarmPalette.ink1)
                            Spacer()
                            if let limit = cat.monthly_limit {
                                Text("$\(Int(limit))/mo")
                                    .font(.flFootnote)
                                    .foregroundStyle(WarmPalette.ink3)
                            } else {
                                Text("No limit")
                                    .font(.flFootnote)
                                    .foregroundStyle(WarmPalette.ink4)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await deleteCategory(cat.id) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }

                if categories.isEmpty && !isLoading {
                    WarmEmptyState(
                        title: "Set up your first budget",
                        systemImage: "chart.pie",
                        description: "Create categories with monthly limits to see where the money goes.",
                        actionLabel: "Add a category",
                        action: { showingAdd = true }
                    )
                }
            } header: {
                Text("Categories")
            } footer: {
                Text("Receipts are automatically matched to categories by name. Set monthly limits to track spending.")
            }
        }
        .scrollContentBackground(.hidden)
        .background { AmbientBackground(style: .expenses) }
        .navigationTitle("Budget Categories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAdd = true } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(TabAccent.expenses.color)
                }
                .accessibilityLabel("Add budget category")
            }
        }
        .sheet(isPresented: $showingAdd) {
            EditBudgetCategorySheet(category: nil) { await load() }
        }
        .sheet(item: $editingCategory) { cat in
            EditBudgetCategorySheet(category: cat) { await load() }
        }
        .inlineError(error) { error = nil }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        do {
            categories = try await api.fetchBudgetCategories()
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func deleteCategory(_ id: Int) async {
        do {
            try await api.deleteBudgetCategory(id: id)
            categories.removeAll { $0.id == id }
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }

}

struct EditBudgetCategorySheet: View {
    let category: APIService.BudgetCategoryResponse?
    let onComplete: () async -> Void

    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var monthlyLimit: String
    @State private var isSaving = false

    init(category: APIService.BudgetCategoryResponse?, onComplete: @escaping () async -> Void) {
        self.category = category
        self.onComplete = onComplete
        _name = State(initialValue: category?.name ?? "")
        _monthlyLimit = State(initialValue: category?.monthly_limit.map { String(Int($0)) } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    TextField("Name (e.g. Groceries)", text: $name)
                }
                Section("Budget") {
                    TextField("Monthly limit ($)", text: $monthlyLimit)
                        .keyboardType(.numberPad)
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground(style: .expenses) }
            .navigationTitle(category == nil ? "Add Category" : "Edit Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(WarmPalette.ink2)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(category == nil ? "Add" : "Save") {
                        Task { await save() }
                    }
                    .disabled(name.isEmpty || isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        var data: [String: Any] = ["name": name]
        if let limit = Double(monthlyLimit) {
            data["monthly_limit"] = limit
        }

        do {
            if let existing = category {
                try await api.updateBudgetCategory(id: existing.id, data: data)
            } else {
                try await api.addBudgetCategory(data)
            }
            await onComplete()
            dismiss()
        } catch {
            guard !error.isCancellation else { return }
            isSaving = false
        }
    }
}

#Preview {
    NavigationStack {
        BudgetSettingsView()
    }
    .environment(APIService())
}
