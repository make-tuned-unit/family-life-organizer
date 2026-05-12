import SwiftUI

struct PantryView: View {
    var showsDismissButton = false
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    @Environment(APIService.self) private var api
    @State private var viewModel = PantryViewModel()
    @State private var showingAddItem = false
    @State private var itemToEdit: PantryItemResponse?

    private let locations = ["All", "Fridge", "Freezer", "Pantry", "Counter"]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                headerSection
                searchBar
                locationChips
                expiringSoonSection
                itemsGrid
            }
            .padding(.bottom, DesignTokens.Spacing.bottomBuffer)
        }
        .background {
            if !embedded { AmbientBackground(style: .pantry) }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .toolbar {
            if showsDismissButton {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(WarmPalette.ink2)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                GlassIconButton(systemName: "plus") { showingAddItem = true }
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
            if viewModel.isLoading && viewModel.items.isEmpty { ProgressView() }
        }
        .alert("Something went wrong", isPresented: errorAlertIsPresented) {
            Button("OK") { viewModel.error = nil }
        } message: {
            Text(viewModel.error ?? "An unexpected error occurred.")
        }
        .refreshable { await viewModel.load(api: api) }
        .task { await viewModel.load(api: api) }
    }

    private var errorAlertIsPresented: Binding<Bool> {
        Binding(get: { viewModel.error != nil }, set: { if !$0 { viewModel.error = nil } })
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(viewModel.items.count) items \u{00B7} \(expiringCount) expiring")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WarmPalette.ink3)
                    .tracking(0.4)
                    .textCase(.uppercase)
                Text("Pantry")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(WarmPalette.ink1)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(WarmPalette.ink3)
            TextField("Search pantry...", text: $viewModel.searchText)
                .font(.system(size: 15))
        }
        .padding(10)
        .background(WarmPalette.cardSurface, in: Capsule())
        .padding(.horizontal, 22)
        .padding(.bottom, 8)
    }

    // MARK: - Location Chips

    private var locationChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(locations, id: \.self) { loc in
                    let isActive = viewModel.selectedLocation == loc
                    let count = loc == "All" ? viewModel.items.count : viewModel.items.filter { ($0.location ?? "").lowercased() == loc.lowercased() }.count
                    let label = loc == "All" ? "All" : "\(loc) \u{00B7} \(count)"

                    WarmChip(label: label, isActive: isActive) {
                        viewModel.selectedLocation = loc
                    }
                }
            }
            .padding(.horizontal, 22)
        }
        .padding(.bottom, 16)
    }

    // MARK: - Expiring Soon

    @ViewBuilder
    private var expiringSoonSection: some View {
        let expiring = expiringItems
        if !expiring.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("EXPIRING SOON")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WarmPalette.warn)
                        .tracking(0.4)
                    Spacer()
                    Text("See all")
                        .font(.system(size: 13))
                        .foregroundStyle(WarmPalette.ink3)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(expiring.prefix(5)) { item in
                            ExpiringItemCard(item: item)
                        }
                    }
                }
            }
            .padding(16)
            .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: 24))
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            .padding(.bottom, 14)
        }
    }

    // MARK: - Items Grid

    @ViewBuilder
    private var itemsGrid: some View {
        let items = viewModel.filteredItems
        if items.isEmpty && !viewModel.isLoading {
            VStack(spacing: 8) {
                Image(systemName: "refrigerator")
                    .font(.system(size: 32))
                    .foregroundStyle(WarmPalette.ink4)
                Text(viewModel.selectedLocation == "All" ? "Your pantry is empty" : "Nothing in \(viewModel.selectedLocation.lowercased())")
                    .font(.system(size: 15))
                    .foregroundStyle(WarmPalette.ink3)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            let grouped = Dictionary(grouping: items) { $0.location?.capitalized ?? "Other" }
            ForEach(grouped.keys.sorted(), id: \.self) { location in
                VStack(spacing: 0) {
                    WarmSectionHeader(title: location, trailing: "\(grouped[location]?.count ?? 0) items")
                        .padding(.bottom, 8)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(grouped[location] ?? []) { item in
                            Button { itemToEdit = item } label: {
                                PantryItemTile(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                }
                .padding(.bottom, 14)
            }
        }
    }

    // MARK: - Helpers

    private var expiringCount: Int {
        viewModel.items.filter { item in
            guard let expiry = item.expiry_date,
                  let date = DateFormatter.isoDate.date(from: expiry) else { return false }
            let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 999
            return days <= 3 // includes expired (negative days)
        }.count
    }

    private var expiringItems: [PantryItemResponse] {
        viewModel.items.filter { item in
            guard let expiry = item.expiry_date,
                  let date = DateFormatter.isoDate.date(from: expiry) else { return false }
            let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 999
            return days <= 5 // includes expired (negative days)
        }.sorted { item1, item2 in
            let d1 = DateFormatter.isoDate.date(from: item1.expiry_date ?? "") ?? .distantFuture
            let d2 = DateFormatter.isoDate.date(from: item2.expiry_date ?? "") ?? .distantFuture
            return d1 < d2
        }
    }
}

// MARK: - Expiring Item Card

struct ExpiringItemCard: View {
    let item: PantryItemResponse

    private var daysLeft: Int {
        guard let expiry = item.expiry_date,
              let date = DateFormatter.isoDate.date(from: expiry) else { return 999 }
        return Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 999
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.item)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WarmPalette.ink1)
            Text(daysLeft < 0 ? "Expired" : daysLeft == 0 ? "Today" : daysLeft == 1 ? "Tomorrow" : "\(daysLeft) days")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(daysLeft <= 0 ? WarmPalette.bad : daysLeft <= 1 ? WarmPalette.warn : WarmPalette.warn)
            Text(item.location?.capitalized ?? "")
                .font(.system(size: 11))
                .foregroundStyle(WarmPalette.ink3)
                .opacity(0.7)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minWidth: 130, alignment: .leading)
        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Pantry Item Tile

struct PantryItemTile: View {
    let item: PantryItemResponse

    private var daysUntilExpiry: Int? {
        guard let expiry = item.expiry_date,
              let date = DateFormatter.isoDate.date(from: expiry) else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: date).day
    }

    private var isExpired: Bool {
        guard let days = daysUntilExpiry else { return false }
        return days < 0
    }

    private var isExpiringSoon: Bool {
        guard let days = daysUntilExpiry else { return false }
        return days <= 3 // includes expired
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: categoryIcon)
                .font(.system(size: 22))
                .foregroundStyle(WarmPalette.ink3)
                .padding(.bottom, 6)

            Text(item.item)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(WarmPalette.ink1)
                .lineLimit(2)

            if let qty = item.quantity, !qty.isEmpty {
                Text(qty + (item.unit.map { " \($0)" } ?? ""))
                    .font(.system(size: 11))
                    .foregroundStyle(WarmPalette.ink3)
            }

            if let expiry = item.expiry_date {
                let display = expiryDisplay(expiry)
                HStack(spacing: 2) {
                    if isExpiringSoon {
                        Image(systemName: isExpired ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                    }
                    Text(isExpired ? "Expired" : "Exp \u{00B7} \(display)")
                }
                .font(.system(size: 11, weight: isExpiringSoon ? .semibold : .regular))
                .foregroundStyle(isExpired ? WarmPalette.bad.opacity(0.8) : (isExpiringSoon ? WarmPalette.bad : WarmPalette.ink3))
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.tile))
    }

    private var categoryIcon: String {
        switch (item.category ?? "").lowercased() {
        case "dairy": return "cup.and.saucer.fill"
        case "meat", "protein": return "fork.knife"
        case "vegetables", "produce": return "leaf.fill"
        case "fruit": return "apple.logo"
        case "grains", "bread": return "basket.fill"
        case "condiments": return "drop.fill"
        case "frozen": return "snowflake"
        default: return "takeoutbag.and.cup.and.straw.fill"
        }
    }

    private func expiryDisplay(_ dateStr: String) -> String {
        guard let date = DateFormatter.isoDate.date(from: dateStr) else { return dateStr }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        if days < 0 { return "Expired" }
        if days == 0 { return "Today" }
        if days == 1 { return "Tomorrow" }
        return DateFormatter.shortMonthDay.string(from: date)
    }
}

// MARK: - Legacy row kept for compatibility

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
                .foregroundStyle(WarmPalette.ink3)
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
        if daysUntil < 0 { return ("Expired", WarmPalette.bad) }
        if daysUntil <= 3 { return ("Exp. soon", WarmPalette.warn) }
        return ("\(daysUntil)d", WarmPalette.good)
    }

    var body: some View {
        Text(status.0)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, DesignTokens.Spacing.chipPadding)
            .padding(.vertical, DesignTokens.Spacing.tinyLabel)
            .background(status.1.opacity(DesignTokens.Opacity.badgeFill))
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
