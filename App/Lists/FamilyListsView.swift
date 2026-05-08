import SwiftUI

/// Family Lists — multiple shared lists. Grocery is the default, but you can create any list.
struct FamilyListsView: View {
    @Environment(APIService.self) private var api
    @State private var viewModel = GroceryListViewModel()
    @State private var activeList: FamilyList = .grocery
    @State private var newItem = ""

    enum FamilyList: String, CaseIterable {
        case grocery = "Grocery"
        case chores = "Chores"
        case packing = "Packing"
        case custom = "Custom"

        var icon: String {
            switch self {
            case .grocery: "cart.fill"
            case .chores: "checkmark.circle.fill"
            case .packing: "suitcase.fill"
            case .custom: "list.bullet"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            listPicker
            quickAddBar

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    listContent
                }
                .padding(.bottom, DesignTokens.Spacing.bottomBuffer)
            }
        }
        .background { AmbientBackground(style: .home) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                GlassIconButton(systemName: "plus") {}
            }
        }
        .refreshable { await viewModel.load(api: api) }
        .overlay {
            if viewModel.isLoading && viewModel.groceries.isEmpty { ProgressView() }
        }
        .task { await viewModel.load(api: api) }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(viewModel.groceries.count) ITEMS")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WarmPalette.ink3)
                    .tracking(0.4)
                Text("Lists")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(WarmPalette.ink1)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    // MARK: - List Picker

    private var listPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FamilyList.allCases, id: \.self) { list in
                    WarmChip(label: list.rawValue, isActive: activeList == list) {
                        activeList = list
                    }
                }
            }
            .padding(.horizontal, 22)
        }
        .padding(.bottom, 12)
    }

    // MARK: - Quick Add

    private var quickAddBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 14))
                    .foregroundStyle(WarmPalette.ink3)
                TextField("Add item...", text: $newItem)
                    .font(.system(size: 15))
                    .foregroundStyle(WarmPalette.ink1)
                    .onSubmit { addItem() }
            }
            .padding(12)
            .background(.ultraThinMaterial, in: Capsule())

            if !newItem.isEmpty {
                Button { addItem() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(TabAccent.home.color)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
    }

    // MARK: - List Content

    @ViewBuilder
    private var listContent: some View {
        let items = viewModel.groceries
        if items.isEmpty && !viewModel.isLoading {
            WarmEmptyState(
                title: "Your list is empty",
                systemImage: "list.bullet.rectangle",
                description: "Add items above to get started"
            )
        } else {
            let grouped = Dictionary(grouping: items) { $0.category ?? "Other" }
            ForEach(grouped.keys.sorted(), id: \.self) { category in
                VStack(spacing: 0) {
                    WarmSectionHeader(title: category, trailing: "\(grouped[category]?.count ?? 0)")
                        .padding(.bottom, 6)

                    VStack(spacing: 0) {
                        ForEach(Array((grouped[category] ?? []).enumerated()), id: \.element.id) { index, grocery in
                            if index > 0 { GlassDivider() }
                            ListItemRow(grocery: grocery) {
                                Task { await viewModel.complete(grocery.id, api: api) }
                            }
                        }
                    }
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                    .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                }
                .padding(.bottom, 14)
            }
        }
    }

    private func addItem() {
        let item = newItem.trimmingCharacters(in: .whitespaces)
        guard !item.isEmpty else { return }
        newItem = ""
        Task { await viewModel.add(item: item, api: api) }
    }
}

// MARK: - List Item Row

struct ListItemRow: View {
    let grocery: GroceryResponse
    let onComplete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onComplete) {
                Image(systemName: "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(WarmPalette.good)
            }
            Text(grocery.item)
                .font(.system(size: 15))
                .foregroundStyle(WarmPalette.ink1)
            Spacer()
            if let qty = grocery.quantity, qty != "1" {
                Text("x\(qty)")
                    .font(.system(size: 13))
                    .foregroundStyle(WarmPalette.ink3)
            }
            if let cat = grocery.category {
                Text(cat)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WarmPalette.ink3)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
    }
}

// MARK: - ViewModel

@Observable
final class GroceryListViewModel {
    var groceries: [GroceryResponse] = []
    var isLoading = false

    func load(api: APIService) async {
        isLoading = true
        do { groceries = try await api.fetchGroceries() } catch {}
        isLoading = false
    }

    func add(item: String, api: APIService) async {
        do {
            try await api.addGrocery(item: item)
            await load(api: api)
        } catch {}
    }

    func complete(_ id: Int, api: APIService) async {
        do {
            try await api.completeGrocery(id: id)
            groceries.removeAll { $0.id == id }
        } catch {}
    }
}

#Preview {
    NavigationStack {
        FamilyListsView()
    }
    .environment(APIService())
}
