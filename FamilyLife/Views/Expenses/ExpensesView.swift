import SwiftUI

struct ExpensesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(APIService.self) private var api
    @State private var viewModel = ExpensesViewModel()
    @State private var showingAddReceipt = false
    @State private var showingScanner = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // Month selector
                HStack {
                    Button { viewModel.previousMonth() } label: {
                        Image(systemName: "chevron.left")
                            .font(.title3.weight(.semibold))
                    }
                    Spacer()
                    Text(viewModel.displayMonthString)
                        .font(.title2.bold())
                    Spacer()
                    Button { viewModel.nextMonth() } label: {
                        Image(systemName: "chevron.right")
                            .font(.title3.weight(.semibold))
                    }
                }
                .padding(.horizontal)

                // Total summary
                if !viewModel.budgetItems.isEmpty {
                    let totalSpent = viewModel.budgetItems.reduce(0) { $0 + $1.spent }
                    let totalBudget = viewModel.budgetItems.compactMap(\.monthly_limit).reduce(0, +)
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Total Spent")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("$\(totalSpent, specifier: "%.0f")")
                                .font(.title.bold())
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("Budget")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("$\(totalBudget, specifier: "%.0f")")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(DesignTokens.Spacing.cardPadding)
                    .flCard(tint: TabAccent.expenses.color)
                    .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                }

                // Budget categories
                VStack(spacing: 12) {
                    ForEach(viewModel.budgetItems, id: \.category) { item in
                        BudgetCategoryRow(item: item)
                    }
                }
                .padding(.horizontal)

                // Recent receipts
                if !viewModel.receipts.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recent Receipts")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(viewModel.receipts) { receipt in
                            ReceiptRow(receipt: receipt)
                                .padding(.horizontal)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        Task { await viewModel.deleteReceipt(receipt.id, api: api) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }

                // Empty state for receipts
                if viewModel.receipts.isEmpty && !viewModel.isLoading {
                    ContentUnavailableView("No Receipts", systemImage: "receipt", description: Text("Scan or add a receipt"))
                        .padding(.top, DesignTokens.Spacing.bottomBuffer)
                }
            }
            .padding(.vertical)
        }
        .background { AmbientBackground(style: .expenses) }
        .navigationTitle("Expenses")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
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
                }
            }
        }
        .sheet(isPresented: $showingScanner) {
            ReceiptScannerView()
        }
        .sheet(isPresented: $showingAddReceipt) {
            AddReceiptView()
        }
        .overlay {
            if viewModel.isLoading && viewModel.budgetItems.isEmpty {
                ProgressView()
            }
        }
        .refreshable {
            await viewModel.loadAll(api: api)
        }
        .task {
            await viewModel.loadAll(api: api)
        }
        .onChange(of: viewModel.displayedMonth) {
            Task { await viewModel.loadAll(api: api) }
        }
    }
}

struct BudgetCategoryRow: View {
    let item: BudgetSummaryResponse

    private var progress: Double {
        guard let limit = item.monthly_limit, limit > 0 else { return 0 }
        return min(item.spent / limit, 1.5)
    }

    private var progressColor: Color {
        if progress > 1.0 { return .red }
        if progress > 0.75 { return .yellow }
        return .green
    }

    private var hexColor: Color {
        if let hex = item.color {
            return Color(hex: hex)
        }
        return .teal
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(hexColor)
                    .frame(width: 10, height: 10)
                Text(item.category)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("$\(item.spent, specifier: "%.0f")")
                    .font(.subheadline.bold())
                if let limit = item.monthly_limit {
                    Text("/ $\(limit, specifier: "%.0f")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.fill.tertiary)
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(progressColor)
                        .frame(width: geo.size.width * min(progress, 1.0), height: 8)
                }
            }
            .frame(height: 8)
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .flCard(tint: hexColor)
    }
}

struct ReceiptRow: View {
    let receipt: ReceiptResponse

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "receipt")
                .foregroundStyle(.teal)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(receipt.merchant)
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 8) {
                    Text(receipt.date)
                    if let cat = receipt.category {
                        Text(cat)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text("$\(receipt.amount, specifier: "%.2f")")
                .font(.subheadline.bold())
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .flCard(tint: TabAccent.expenses.color)
    }
}

// Hex color extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

#Preview {
    NavigationStack {
        ExpensesView()
    }
    .environment(APIService())
}
