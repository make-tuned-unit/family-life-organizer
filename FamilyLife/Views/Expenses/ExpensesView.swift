import SwiftUI

struct ExpensesView: View {
    var showsDismissButton = false
    @Environment(\.dismiss) private var dismiss
    @Environment(APIService.self) private var api
    @State private var viewModel = ExpensesViewModel()
    @State private var showingAddReceipt = false
    @State private var showingScanner = false
    @State private var projectStore = BudgetProjectStore()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                headerSection
                heroSummary
                categoriesSection
                receiptsSection
                projectsPreview
            }
            .padding(.bottom, DesignTokens.Spacing.bottomBuffer)
        }
        .background { AmbientBackground(style: .expenses) }
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
        .sheet(isPresented: $showingScanner) { ReceiptScannerView() }
        .sheet(isPresented: $showingAddReceipt) { AddReceiptView() }
        .overlay {
            if viewModel.isLoading && viewModel.budgetItems.isEmpty { ProgressView() }
        }
        .alert("Something went wrong", isPresented: errorAlertIsPresented) {
            Button("OK") { viewModel.error = nil }
        } message: {
            Text(viewModel.error ?? "An unexpected error occurred.")
        }
        .refreshable { await viewModel.loadAll(api: api); await projectStore.loadAll(api: api) }
        .task { await viewModel.loadAll(api: api); await projectStore.loadAll(api: api) }
        .onChange(of: viewModel.displayedMonth) {
            Task { await viewModel.loadAll(api: api) }
        }
    }

    private var errorAlertIsPresented: Binding<Bool> {
        Binding(get: { viewModel.error != nil }, set: { if !$0 { viewModel.error = nil } })
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
                                .foregroundStyle(AccentTheme.sage.color)
                                .frame(width: 28, height: 28)
                                .background(AccentTheme.sage.color.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(WarmPalette.ink1)
                                Text("$\(Int(project.total_spent).formatted()) of $\(Int(project.budget).formatted())")
                                    .font(.system(size: 12))
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
                        .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                }

                if projectStore.projects.count > 2 {
                    NavigationLink {
                        BudgetProjectsView()
                    } label: {
                        Text("View all \(projectStore.projects.count) projects")
                            .font(.system(size: 13, weight: .medium))
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
                        .foregroundStyle(AccentTheme.sage.color)
                        .frame(width: 36, height: 36)
                        .background(AccentTheme.sage.color.opacity(0.15))
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Project budgets")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(WarmPalette.ink1)
                        Text("Track spending on renovations, events, and more")
                            .font(.system(size: 13))
                            .foregroundStyle(WarmPalette.ink3)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WarmPalette.ink4)
                }
                .padding(14)
                .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: DesignTokens.CornerRadius.card))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            .padding(.bottom, 14)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(viewModel.displayMonthString) \u{00B7} halfway through")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WarmPalette.ink3)
                    .tracking(0.4)
                    .textCase(.uppercase)
                Text("Budget")
                    .font(.system(size: 28, weight: .bold))
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
        .padding(.horizontal, 22)
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
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(WarmPalette.ink3)
                    .tracking(0.4)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("$\(Int(totalSpent).formatted())")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(WarmPalette.ink1)
                        .tracking(-0.88)
                    Text("of $\(Int(totalBudget).formatted())")
                        .font(.system(size: 13))
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
                        .font(.system(size: 13))
                        .foregroundStyle(WarmPalette.ink3)
                    Spacer()
                    if totalSpent < totalBudget {
                        Text("\u{2193} on track")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WarmPalette.good)
                    } else {
                        Text("\u{2191} over budget")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WarmPalette.bad)
                    }
                }
            }
            .padding(20)
            } // close ZStack
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.cardLarge))
            .glassEffect(.regular.tint(AccentTheme.terracotta.color.opacity(0.04)), in: .rect(cornerRadius: DesignTokens.CornerRadius.cardLarge))
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            .padding(.bottom, 14)
        }
    }

    // MARK: - Categories

    @ViewBuilder
    private var categoriesSection: some View {
        if !viewModel.budgetItems.isEmpty {
            WarmSectionHeader(title: "Categories", trailing: "\(viewModel.budgetItems.count) total")
                .padding(.bottom, 8)

            VStack(spacing: 8) {
                ForEach(viewModel.budgetItems, id: \.category) { item in
                    BudgetCategoryCard(item: item)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            .padding(.bottom, 14)
        }
    }

    // MARK: - Receipts

    @ViewBuilder
    private var receiptsSection: some View {
        if !viewModel.receipts.isEmpty {
            WarmSectionHeader(title: "Recent receipts", trailing: "View all")
                .padding(.bottom, 6)

            VStack(spacing: 0) {
                ForEach(Array(viewModel.receipts.prefix(5).enumerated()), id: \.element.id) { index, receipt in
                    if index > 0 { GlassDivider() }
                    ReceiptListRow(receipt: receipt)
                }
            }
            .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: DesignTokens.CornerRadius.card))
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
        } else if !viewModel.isLoading {
            VStack(spacing: 8) {
                Image(systemName: "receipt")
                    .font(.system(size: 32))
                    .foregroundStyle(WarmPalette.ink4)
                Text("No receipts yet")
                    .font(.system(size: 15))
                    .foregroundStyle(WarmPalette.ink3)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        }
    }

    private func categoryColor(_ item: BudgetSummaryResponse) -> Color {
        if let hex = item.color { return Color(hex: hex) }
        return TabAccent.expenses.color
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
                .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(item.category)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WarmPalette.ink1)
                    Spacer()
                    HStack(spacing: 4) {
                        Text("$\(Int(item.spent))")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(WarmPalette.ink1)
                        if let limit = item.monthly_limit {
                            Text("/ $\(Int(limit))")
                                .font(.system(size: 13))
                                .foregroundStyle(WarmPalette.ink3)
                        }
                    }
                }
                WarmProgressBar(progress: progress, color: progressColor)
            }
        }
        .padding(14)
        .glassEffect(.regular.tint(color.opacity(0.04)), in: .rect(cornerRadius: 20))
    }
}

// MARK: - Receipt Row

struct ReceiptListRow: View {
    let receipt: ReceiptResponse

    var body: some View {
        HStack(spacing: 12) {
            FamilyAvatar(initial: "J", size: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(receipt.merchant)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WarmPalette.ink1)
                HStack(spacing: 4) {
                    if let cat = receipt.category {
                        Text(cat)
                    }
                    Text("\u{00B7}")
                    Text(receipt.date)
                }
                .font(.system(size: 13))
                .foregroundStyle(WarmPalette.ink3)
            }

            Spacer()

            Text("$\(receipt.amount, specifier: "%.2f")")
                .font(.system(size: 15, weight: .bold, design: .default))
                .foregroundStyle(WarmPalette.ink1)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
    }
}

// Color(hex:) is defined in DesignTokens.swift

#Preview {
    NavigationStack {
        ExpensesView()
    }
    .environment(APIService())
}
