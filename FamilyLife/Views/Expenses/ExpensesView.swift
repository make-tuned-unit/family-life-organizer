import SwiftUI

struct ExpensesView: View {
    var showsDismissButton = false
    @Environment(\.dismiss) private var dismiss
    @Environment(APIService.self) private var api
    @State private var viewModel = ExpensesViewModel()
    @State private var showingAddReceipt = false
    @State private var showingScanner = false
    @State private var projectStore = BudgetProjectStore()
    @State private var recurringStore = RecurringPaymentsStore()
    @State private var mode: BudgetMode = .overview

    enum BudgetMode: String, CaseIterable, Identifiable {
        case overview = "Overview", stats = "Stats"
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                headerSection
                modePicker
                if mode == .overview {
                    heroSummary
                    categoriesSection
                    recurringEntry
                    projectsPreview
                } else {
                    BudgetStatsView()
                }
            }
            .padding(.bottom, DesignTokens.Spacing.bottomBuffer)
        }
        .background { AmbientBackground(style: .expenses) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                AskButlerButton(prompt: "How are we doing on our budget this month?")
            }
            if showsDismissButton {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(WarmPalette.ink2)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    NavigationLink {
                        BudgetSettingsView()
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(WarmPalette.ink2)
                    }
                    Menu {
                        Button { showingScanner = true } label: {
                            Label("Scan Receipt", systemImage: "camera")
                        }
                        Button { showingAddReceipt = true } label: {
                            Label("Add Manually", systemImage: "square.and.pencil")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(WarmPalette.ink2)
                    }
                }
            }
        }
        .sheet(isPresented: $showingScanner) {
            ReceiptScannerView(onReceiptSaved: {
                await viewModel.loadAll(api: api)
                await projectStore.loadAll(api: api)
            })
        }
        .sheet(isPresented: $showingAddReceipt) { AddReceiptView() }
        .overlay {
            if viewModel.isLoading && viewModel.budgetItems.isEmpty {
                FLLoadingState(message: "Loading budget...")
            }
        }
        .inlineError(viewModel.error) { viewModel.error = nil }
        .refreshable { await viewModel.loadAll(api: api); await projectStore.loadAll(api: api); await recurringStore.load(api: api) }
        .task { await recurringStore.load(api: api) }
        .task(id: showingScanner) { await viewModel.loadAll(api: api); await projectStore.loadAll(api: api) }
        .task(id: showingAddReceipt) { await viewModel.loadAll(api: api) }
        .onChange(of: viewModel.displayedMonth) {
            Task { await viewModel.loadAll(api: api) }
        }
    }

    // MARK: - Projects Preview

    @ViewBuilder
    private var projectsPreview: some View {
        if !projectStore.projects.isEmpty {
            VStack(spacing: 8) {
                ForEach(projectStore.projects.prefix(2)) { project in
                    NavigationLink {
                        ProjectDetailView(store: projectStore, projectID: project.id)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "hammer.fill")
                                .font(.system(size: 14))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(AccentTheme.sage.color)
                                .frame(width: 28, height: 28)
                                .background(AccentTheme.sage.color.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.name)
                                    .font(.flSubheadline.weight(.semibold))
                                    .foregroundStyle(WarmPalette.ink1)
                                Text("$\(Int(project.total_spent).formatted()) of $\(Int(project.budget).formatted())")
                                    .font(.flCaption)
                                    .foregroundStyle(WarmPalette.ink3)
                            }
                            Spacer()
                            WarmProgressBar(
                                progress: project.progress,
                                color: project.progress > 0.85 ? AccentTheme.saffron.color : AccentTheme.sage.color
                            )
                            .frame(width: 60)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(WarmPalette.ink4)
                        }
                        .padding(12)
                        .flCard()
                    }
                    .buttonStyle(.plain)
                }

                if projectStore.projects.count > 2 {
                    NavigationLink {
                        BudgetProjectsView()
                    } label: {
                        Text("View all \(projectStore.projects.count) projects")
                            .font(.flFootnote.weight(.medium))
                            .foregroundStyle(WarmPalette.ink3)
                    }
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            .padding(.bottom, 14)
        } else {
            NavigationLink {
                BudgetProjectsView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 16))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(AccentTheme.sage.color)
                        .frame(width: 36, height: 36)
                        .background(AccentTheme.sage.color.opacity(0.15))
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Project budgets")
                            .font(.flSubheadline.weight(.semibold))
                            .foregroundStyle(WarmPalette.ink1)
                        Text("Track spending on renovations, events, and more")
                            .font(.flFootnote)
                            .foregroundStyle(WarmPalette.ink3)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WarmPalette.ink4)
                }
                .padding(14)
                .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            .padding(.bottom, 14)
        }
    }

    // MARK: - Mode toggle

    private var modePicker: some View {
        Picker("View", selection: $mode.animation(.easeInOut(duration: 0.2))) {
            ForEach(BudgetMode.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
        .padding(.bottom, 14)
    }

    // MARK: - Recurring entry

    private var recurringEntry: some View {
        NavigationLink {
            RecurringPaymentsView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 16))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AccentTheme.ocean.color)
                    .frame(width: 36, height: 36)
                    .background(AccentTheme.ocean.color.opacity(0.15))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recurring payments")
                        .font(.flSubheadline.weight(.semibold))
                        .foregroundStyle(WarmPalette.ink1)
                    Text(recurringStore.items.isEmpty
                         ? "Rent, subscriptions, insurance & more"
                         : "$\(Int(recurringStore.monthlyTotal).formatted())/mo \u{00B7} \(recurringStore.items.count) payment\(recurringStore.items.count == 1 ? "" : "s")")
                        .font(.flFootnote)
                        .foregroundStyle(WarmPalette.ink3)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WarmPalette.ink4)
            }
            .padding(14)
            .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
        .padding(.bottom, 14)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(viewModel.displayMonthString) \u{00B7} halfway through")
                    .font(.flOverline)
                    .foregroundStyle(WarmPalette.ink3)
                    .tracking(0.4)
                    .textCase(.uppercase)
                Text("Budget")
                    .font(.flScreenTitle)
                    .foregroundStyle(WarmPalette.ink1)
            }
            Spacer()
            HStack(spacing: 8) {
                Button { viewModel.previousMonth() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WarmPalette.ink2)
                }
                Button { viewModel.nextMonth() } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WarmPalette.ink2)
                }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
        .padding(.top, 14)
        .padding(.bottom, 14)
    }

    // MARK: - Hero Summary

    @ViewBuilder
    private var heroSummary: some View {
        if !viewModel.budgetItems.isEmpty {
            let totalSpent = viewModel.budgetItems.reduce(0.0) { $0 + $1.spent }
            let totalBudget = viewModel.budgetItems.compactMap(\.monthly_limit).reduce(0.0, +)
            let remaining = max(0, totalBudget - totalSpent)

            ZStack(alignment: .bottomTrailing) {
                // Decorative radial orb (prototype expenses.jsx:27)
                Circle()
                    .fill(RadialGradient(colors: [AccentTheme.terracotta.color.opacity(0.3), .clear], center: .center, startRadius: 0, endRadius: 90))
                    .frame(width: 180, height: 180)
                    .offset(x: 40, y: 40)

            VStack(alignment: .leading, spacing: 0) {
                Text("SPENT THIS MONTH")
                    .font(.flOverline)
                    .foregroundStyle(WarmPalette.ink3)
                    .tracking(0.4)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("$\(Int(totalSpent).formatted())")
                        .font(.flHero)
                        .foregroundStyle(WarmPalette.ink1)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: totalSpent)
                    Text("of $\(Int(totalBudget).formatted())")
                        .font(.flFootnote)
                        .foregroundStyle(WarmPalette.ink3)
                }
                .padding(.top, 8)
                .padding(.bottom, 14)

                // Stacked bar
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        ForEach(viewModel.budgetItems, id: \.category) { item in
                            let width = totalBudget > 0 ? (item.spent / totalBudget) * geo.size.width : 0
                            Rectangle()
                                .fill(categoryColor(item))
                                .frame(width: width)
                        }
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 10)
                .background(Capsule().fill(.white.opacity(0.4)))
                .padding(.bottom, 12)

                HStack {
                    Text("$\(Int(remaining).formatted()) remaining")
                        .font(.flFootnote)
                        .foregroundStyle(WarmPalette.ink3)
                    Spacer()
                    if totalSpent < totalBudget {
                        Text("\u{2193} on track")
                            .font(.flFootnote.weight(.semibold))
                            .foregroundStyle(WarmPalette.good)
                    } else {
                        Text("\u{2191} over budget")
                            .font(.flFootnote.weight(.semibold))
                            .foregroundStyle(WarmPalette.bad)
                    }
                }
            }
            .padding(20)
            } // close ZStack
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.cardLarge))
            .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.cardLarge))
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            .padding(.bottom, 14)
        }
    }

    private func categoryColor(_ item: BudgetSummaryResponse) -> Color {
        if let hex = item.color { return Color(hex: hex) }
        return TabAccent.expenses.color
    }

    // MARK: - Categories

    @ViewBuilder
    private var categoriesSection: some View {
        if !viewModel.budgetItems.isEmpty {
            WarmSectionHeader(title: "Categories", trailing: "\(viewModel.budgetItems.count) total")
                .padding(.bottom, 8)

            VStack(spacing: 8) {
                ForEach(viewModel.budgetItems, id: \.category) { item in
                    NavigationLink {
                        BudgetCategoryDetailView(
                            category: item,
                            month: viewModel.monthParam
                        )
                    } label: {
                        BudgetCategoryCard(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            .padding(.bottom, 14)
        }
    }

}

// MARK: - Budget Category Card

struct BudgetCategoryCard: View {
    let item: BudgetSummaryResponse

    private var progress: Double {
        guard let limit = item.monthly_limit, limit > 0 else { return 0 }
        return min(item.spent / limit, 1.5)
    }

    private var color: Color {
        if let hex = item.color { return Color(hex: hex) }
        return TabAccent.expenses.color
    }

    private var progressColor: Color {
        progress > 0.9 ? WarmPalette.bad : color
    }

    private var iconName: String {
        switch item.category.lowercased() {
        case "groceries": return "cart.fill"
        case "dining", "dining out": return "fork.knife"
        case "kids": return "figure.2.and.child.holdinghands"
        case "household": return "house.fill"
        case "transport", "transportation": return "car.fill"
        case "health": return "heart.fill"
        default: return "dollarsign.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: iconName)
                .font(.system(size: 18))
                .foregroundStyle(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(item.category)
                        .font(.flSubheadline.weight(.semibold))
                        .foregroundStyle(WarmPalette.ink1)
                    Spacer()
                    HStack(spacing: 4) {
                        Text("$\(Int(item.spent))")
                            .font(.flSubheadline.weight(.bold))
                            .foregroundStyle(WarmPalette.ink1)
                        if let limit = item.monthly_limit {
                            Text("/ $\(Int(limit))")
                                .font(.flFootnote)
                                .foregroundStyle(WarmPalette.ink3)
                        }
                    }
                }
                WarmProgressBar(progress: progress, color: progressColor)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(WarmPalette.ink4)
        }
        .padding(14)
        .flCard()
    }
}

// MARK: - Receipt Row

struct ReceiptListRow: View {
    let receipt: ReceiptResponse
    @Environment(AuthService.self) private var auth

    private var isCurrentUser: Bool {
        guard let addedBy = receipt.added_by else { return false }
        return addedBy.localizedCaseInsensitiveCompare(auth.currentUser?.username ?? "") == .orderedSame
            || addedBy.localizedCaseInsensitiveCompare(auth.currentUser?.name ?? "") == .orderedSame
    }

    var body: some View {
        HStack(spacing: 12) {
            if isCurrentUser {
                ProfileAvatar(size: 28)
            } else {
                FamilyAvatar(initial: String(receipt.added_by?.prefix(1) ?? "?").uppercased(), size: 28, name: receipt.added_by)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(receipt.merchant)
                    .font(.flSubheadline.weight(.semibold))
                    .foregroundStyle(WarmPalette.ink1)
                HStack(spacing: 4) {
                    if let cat = receipt.category {
                        Text(cat)
                    }
                    Text("\u{00B7}")
                    Text(receipt.date)
                }
                .font(.flFootnote)
                .foregroundStyle(WarmPalette.ink3)
            }

            Spacer()

            Text("$\(receipt.amount, specifier: "%.2f")")
                .font(.flSubheadline.weight(.bold))
                .foregroundStyle(WarmPalette.ink1)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(WarmPalette.ink4)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
    }
}

// MARK: - Receipt Detail View

struct ReceiptDetailView: View {
    let receipt: ReceiptResponse
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Hero
                VStack(alignment: .leading, spacing: 8) {
                    Text(receipt.merchant)
                        .font(.flTitle)
                        .foregroundStyle(WarmPalette.ink1)
                    Text("$\(receipt.amount, specifier: "%.2f")")
                        .font(.flStat)
                        .foregroundStyle(WarmPalette.ink1)
                    if receipt.processed_by == "scan" {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11))
                            Text("Scanned with AI")
                                .font(.flCaption.weight(.medium))
                        }
                        .foregroundStyle(AccentTheme.saffron.color)
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.cardLarge))
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                .padding(.top, 14)
                .padding(.bottom, 14)

                // Info
                VStack(spacing: 0) {
                    detailRow(label: "Category", value: receipt.category ?? "Other")
                    GlassDivider()
                    detailRow(label: "Date", value: formatDate(receipt.date))
                    GlassDivider()
                    if let by = receipt.added_by, !by.isEmpty {
                        detailRow(label: "Added by", value: by.capitalized)
                        GlassDivider()
                    }
                    if let method = receipt.payment_method, !method.isEmpty {
                        detailRow(label: "Payment", value: method)
                        GlassDivider()
                    }
                }
                .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                .padding(.bottom, 14)

                // Item breakdown (from scanned receipts)
                if let notes = receipt.notes, !notes.isEmpty {
                    let lines = notes.split(separator: "\n").map(String.init)
                    let hasItems = lines.contains(where: { $0.contains(" — $") })

                    WarmSectionHeader(title: hasItems ? "Items" : "Notes")
                        .padding(.bottom, 6)

                    if hasItems {
                        VStack(spacing: 0) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                                if index > 0 { GlassDivider() }
                                let parts = line.components(separatedBy: " — $")
                                HStack {
                                    Text(parts.first ?? line)
                                        .font(.flSubheadline)
                                        .foregroundStyle(WarmPalette.ink1)
                                    Spacer()
                                    if parts.count > 1 {
                                        Text("$\(parts[1])")
                                            .font(.flSubheadline.weight(.semibold))
                                            .foregroundStyle(WarmPalette.ink2)
                                    }
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 14)
                            }
                        }
                        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                        .padding(.bottom, 14)
                    } else {
                        Text(notes)
                            .font(.flSubheadline)
                            .foregroundStyle(WarmPalette.ink2)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                            .padding(.bottom, 14)
                    }
                }

                // Delete
                Button(role: .destructive) {
                    onDelete()
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "trash").font(.system(size: 14))
                        Text("Delete Receipt").font(.flSubheadline.weight(.semibold))
                    }
                    .foregroundStyle(WarmPalette.bad)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .flCard()
                }
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                .padding(.bottom, DesignTokens.Spacing.bottomBuffer)
            }
        }
        .background { AmbientBackground(style: .expenses) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.flFootnote).foregroundStyle(WarmPalette.ink3)
            Spacer()
            Text(value).font(.flSubheadline.weight(.medium)).foregroundStyle(WarmPalette.ink1)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
    }

    private func formatDate(_ raw: String) -> String {
        guard let date = DateFormatter.isoDate.date(from: raw) else { return raw }
        return DateFormatter.longDate.string(from: date)
    }
}

#Preview {
    NavigationStack {
        ExpensesView()
    }
    .environment(APIService())
}
