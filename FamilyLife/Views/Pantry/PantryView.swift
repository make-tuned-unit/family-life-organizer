import SwiftUI

struct PantryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(APIService.self) private var api
    @State private var viewModel = PantryViewModel()
    @State private var showingAddItem = false
    @State private var itemToEdit: PantryItemResponse?

    private let locations = ["All", "Fridge", "Freezer", "Pantry", "Counter"]

    var body: some View {
        VStack(spacing: 0) {
            locationPicker
            searchBar
            itemList
        }
        .background { AmbientBackground(style: .pantry) }
        .navigationTitle("Pantry")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAddItem = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddItem) {
            AddPantryItemView { item in
                Task { await viewModel.addItem(item, api: api) }
            }
        }
        .sheet(item: $itemToEdit) { item in
            EditPantryItemView(item: item) {
                Task { await viewModel.load(api: api) }
            }
        }
        .overlay {
            if viewModel.isLoading && viewModel.items.isEmpty {
                ProgressView()
            }
        }
        .refreshable {
            await viewModel.load(api: api)
        }
        .task {
            await viewModel.load(api: api)
        }
    }

    private var locationPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(locations, id: \.self) { location in
                    Button {
                        viewModel.selectedLocation = location
                    } label: {
                        Text(location)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, DesignTokens.Spacing.rowHorizontal)
                            .padding(.vertical, DesignTokens.Spacing.rowVertical)
                            .glassEffect(.regular.tint(viewModel.selectedLocation == location ? .teal : .clear).interactive(), in: .capsule)
                            .foregroundStyle(viewModel.selectedLocation == location ? .white : .primary)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, DesignTokens.Spacing.rowVertical)
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search pantry...", text: $viewModel.searchText)
        }
        .padding(DesignTokens.Spacing.inset)
        .background(.fill.tertiary)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Spacing.inset))
        .padding(.horizontal)
        .padding(.bottom, DesignTokens.Spacing.rowVertical)
    }

    @ViewBuilder
    private var itemList: some View {
        if viewModel.filteredItems.isEmpty && !viewModel.isLoading {
            let desc = viewModel.selectedLocation == "All" ? "Your pantry is empty" : "Nothing in \(viewModel.selectedLocation.lowercased())"
            ContentUnavailableView("No Items", systemImage: "refrigerator", description: Text(desc))
        } else {
            List {
                ForEach(groupedCategories, id: \.self) { category in
                    Section(category) {
                        ForEach(itemsFor(category)) { item in
                            Button { itemToEdit = item } label: {
                                PantryItemRow(item: item)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { await viewModel.deleteItem(item.id, api: api) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button { itemToEdit = item } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var groupedCategories: [String] {
        Array(Set(viewModel.filteredItems.map { $0.category ?? "Other" })).sorted()
    }

    private func itemsFor(_ category: String) -> [PantryItemResponse] {
        viewModel.filteredItems.filter { ($0.category ?? "Other") == category }
    }
}

struct PantryItemRow: View {
    let item: PantryItemResponse

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.item)
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 8) {
                    if let qty = item.quantity, !qty.isEmpty {
                        Label(qty + (item.unit.map { " \($0)" } ?? ""), systemImage: "number")
                    }
                    if let loc = item.location {
                        Label(loc.capitalized, systemImage: "mappin")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let expiry = item.expiry_date {
                ExpiryBadge(dateString: expiry)
            }
        }
    }
}

struct ExpiryBadge: View {
    let dateString: String

    private var daysUntil: Int {
        guard let date = DateFormatter.isoDate.date(from: dateString) else { return 999 }
        return Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 999
    }

    private var status: (String, Color) {
        if daysUntil < 0 { return ("Expired", .red) }
        if daysUntil <= 3 { return ("Exp. soon", .orange) }
        return ("\(daysUntil)d", .green)
    }

    var body: some View {
        Text(status.0)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, DesignTokens.Spacing.chipPadding)
            .padding(.vertical, DesignTokens.Spacing.tinyLabel)
            .background(status.1.opacity(DesignTokens.Opacity.badgeFill)) // DS-05: replaced raw opacity fill
            .foregroundStyle(status.1)
            .clipShape(Capsule())
    }
}

#Preview {
    NavigationStack {
        PantryView()
    }
    .environment(APIService())
}
