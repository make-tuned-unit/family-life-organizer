import SwiftUI

struct BudgetCategoryDetailView: View {
    let category: BudgetSummaryResponse
    let month: String

    @Environment(APIService.self) private var api
    @State private var receipts: [ReceiptResponse] = []
    @State private var isLoading = false

    private var color: Color {
        if let hex = category.color { return Color(hex: hex) }
        return TabAccent.expenses.color
    }

    private var progress: Double {
        guard let limit = category.monthly_limit, limit > 0 else { return 0 }
        return min(category.spent / limit, 1.5)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Hero
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(category.category)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(WarmPalette.ink1)
                        Spacer()
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("$\(Int(category.spent))")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(WarmPalette.ink1)
                            .tracking(-0.8)
                        if let limit = category.monthly_limit {
                            Text("of $\(Int(limit))")
                                .font(.system(size: 15))
                                .foregroundStyle(WarmPalette.ink3)
                        }
                    }

                    WarmProgressBar(progress: progress, color: progress > 0.9 ? WarmPalette.bad : color, height: 8)

                    if let limit = category.monthly_limit {
                        let remaining = max(0, limit - category.spent)
                        Text("$\(Int(remaining)) remaining this month")
                            .font(.system(size: 13))
                            .foregroundStyle(WarmPalette.ink3)
                    }
                }
                .padding(20)
                .glassEffect(.regular.tint(color.opacity(0.04)), in: .rect(cornerRadius: DesignTokens.CornerRadius.cardLarge))
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                .padding(.top, 14)
                .padding(.bottom, 14)

                // Receipts list
                if !receipts.isEmpty {
                    WarmSectionHeader(title: "Receipts", trailing: "\(receipts.count) total")
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        ForEach(Array(receipts.enumerated()), id: \.element.id) { index, receipt in
                            if index > 0 { GlassDivider() }
                            NavigationLink {
                                ReceiptDetailView(receipt: receipt) {
                                    Task {
                                        try? await api.deleteReceipt(id: receipt.id)
                                        await loadReceipts()
                                    }
                                }
                            } label: {
                                ReceiptListRow(receipt: receipt)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: DesignTokens.CornerRadius.card))
                    .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                } else if !isLoading {
                    VStack(spacing: 8) {
                        Image(systemName: "receipt")
                            .font(.system(size: 28))
                            .foregroundStyle(WarmPalette.ink4)
                        Text("No receipts in \(category.category)")
                            .font(.system(size: 14))
                            .foregroundStyle(WarmPalette.ink3)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            }
            .padding(.bottom, DesignTokens.Spacing.bottomBuffer)
        }
        .background { AmbientBackground(style: .expenses) }
        .navigationTitle(category.category)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .overlay {
            if isLoading && receipts.isEmpty { ProgressView() }
        }
        .task { await loadReceipts() }
    }

    private func loadReceipts() async {
        isLoading = true
        do {
            let all = try await api.fetchReceipts(month: month, category: category.category)
            receipts = all.sorted { $0.date > $1.date }
        } catch {
            guard !error.isCancellation else { return }
        }
        isLoading = false
    }
}

#Preview {
    NavigationStack {
        BudgetCategoryDetailView(
            category: BudgetSummaryResponse(category: "Groceries", monthly_limit: 800, color: "#43e97b", spent: 53),
            month: "2026-05"
        )
    }
    .environment(APIService())
}
