import SwiftUI
import Charts

// MARK: - Model (decoded from GET /api/budget/stats)

struct BudgetStats: Codable {
    let month: String
    let monthly: [MonthlyPoint]
    let byCategory: [CategorySpend]
    let budgetVsActual: [BudgetSummaryResponse]
    let currentTotal: Double
    let previousTotal: Double
    let momPct: Int?
    let trailingAvg: Double
    let projectedMonthEnd: Double
    let recurringMonthly: Double
    let variableThisMonth: Double
    let overBudget: [OverBudgetItem]

    struct MonthlyPoint: Codable, Identifiable {
        let ym: String
        let total: Double
        var id: String { ym }
        /// "2026-06" -> "Jun"
        var shortMonth: String {
            guard let d = DateFormatter.yearMonth.date(from: ym) else { return ym }
            let f = DateFormatter(); f.dateFormat = "MMM"
            return f.string(from: d)
        }
    }
    struct CategorySpend: Codable, Identifiable {
        let category: String
        let spent: Double
        var id: String { category }
    }
    struct OverBudgetItem: Codable, Identifiable {
        let category: String
        let spent: Double
        let limit: Double
        var id: String { category }
    }
}

// MARK: - Store

@MainActor
@Observable
final class BudgetStatsStore {
    var stats: BudgetStats?
    var isLoading = false
    var error: String?

    func load(api: APIService, months: Int = 6) async {
        isLoading = true
        defer { isLoading = false }
        do {
            stats = try await api.fetchBudgetStats(months: months)
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Stats View (rendered inside ExpensesView's ScrollView)

struct BudgetStatsView: View {
    @Environment(APIService.self) private var api
    @State private var store = BudgetStatsStore()

    var body: some View {
        VStack(spacing: 14) {
            if let s = store.stats {
                hero(s)
                trendCard(s)
                if !insightCards(s).isEmpty { insightStrip(s) }
                categoryCard(s)
                fixedVsVariable(s)
            } else if store.isLoading {
                FLLoadingState(message: "Loading spending stats...")
            } else {
                emptyState
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
        .padding(.bottom, 14)
        .task { await store.load(api: api) }
    }

    // MARK: Hero — this month, MoM delta, projected month-end

    private func hero(_ s: BudgetStats) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SPENT THIS MONTH")
                .font(.flOverline)
                .foregroundStyle(WarmPalette.ink3)
                .tracking(0.4)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("$\(Int(s.currentTotal).formatted())")
                    .font(.flStat)
                    .foregroundStyle(WarmPalette.ink1)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: s.currentTotal)
                if let pct = s.momPct {
                    let up = pct > 0
                    HStack(spacing: 2) {
                        Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 11, weight: .bold))
                        Text("\(abs(pct))%")
                            .font(.flFootnote.weight(.semibold))
                    }
                    .foregroundStyle(up ? WarmPalette.bad : WarmPalette.good)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background((up ? WarmPalette.bad : WarmPalette.good).opacity(0.14), in: Capsule())
                }
            }
            .padding(.top, 8)
            Text("Projected month-end \u{00B7} $\(Int(s.projectedMonthEnd).formatted())")
                .font(.flFootnote)
                .foregroundStyle(WarmPalette.ink3)
                .padding(.top, 6)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.cardLarge))
    }

    // MARK: Trend — monthly spend over time (area + line)

    private func trendCard(_ s: BudgetStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            WarmSectionHeader(title: "Monthly trend", trailing: "Last \(s.monthly.count) mo")
            Chart(s.monthly) { p in
                AreaMark(x: .value("Month", p.shortMonth), y: .value("Spent", p.total))
                    .foregroundStyle(.linearGradient(colors: [AccentTheme.terracotta.color.opacity(0.35), AccentTheme.terracotta.color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Month", p.shortMonth), y: .value("Spent", p.total))
                    .foregroundStyle(AccentTheme.terracotta.color)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 150)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
    }

    // MARK: Insight cards — "where the leaks are"

    private struct Insight: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
        let tint: Color
    }

    private func insightCards(_ s: BudgetStats) -> [Insight] {
        var out: [Insight] = []
        if let first = s.overBudget.first {
            let extra = Int(first.spent - first.limit)
            out.append(Insight(icon: "exclamationmark.triangle.fill",
                               title: "\(first.category) over budget",
                               detail: "$\(extra.formatted()) over the limit",
                               tint: WarmPalette.bad))
        }
        if let top = s.byCategory.first {
            out.append(Insight(icon: "chart.bar.fill",
                               title: "Top category",
                               detail: "\(top.category) \u{00B7} $\(Int(top.spent).formatted())",
                               tint: AccentTheme.saffron.color))
        }
        if s.recurringMonthly > 0, s.currentTotal > 0 {
            let pct = Int((s.recurringMonthly / max(s.currentTotal, s.recurringMonthly)) * 100)
            out.append(Insight(icon: "arrow.triangle.2.circlepath",
                               title: "Fixed costs",
                               detail: "\(pct)% of spend is recurring",
                               tint: AccentTheme.ocean.color))
        }
        if s.trailingAvg > 0 {
            out.append(Insight(icon: "calendar",
                               title: "Monthly average",
                               detail: "$\(Int(s.trailingAvg).formatted()) over \(s.monthly.count) mo",
                               tint: AccentTheme.sage.color))
        }
        return out
    }

    private func insightStrip(_ s: BudgetStats) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(insightCards(s)) { card in
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: card.icon)
                            .font(.system(size: 16))
                            .foregroundStyle(card.tint)
                            .frame(width: 32, height: 32)
                            .background(card.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                        Text(card.title)
                            .font(.flFootnote.weight(.semibold))
                            .foregroundStyle(WarmPalette.ink1)
                        Text(card.detail)
                            .font(.flCaption)
                            .foregroundStyle(WarmPalette.ink3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(width: 180, alignment: .leading)
                    .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                }
            }
        }
    }

    // MARK: Category breakdown — horizontal bars, sorted desc

    private func categoryCard(_ s: BudgetStats) -> some View {
        let top = Array(s.byCategory.prefix(6))
        let maxSpent = top.map(\.spent).max() ?? 1
        return VStack(alignment: .leading, spacing: 12) {
            WarmSectionHeader(title: "By category", trailing: s.month)
            Chart(top) { c in
                BarMark(x: .value("Spent", c.spent), y: .value("Category", c.category))
                    .foregroundStyle(AccentTheme.terracotta.color.gradient)
                    .cornerRadius(6)
                    .annotation(position: .trailing, alignment: .leading) {
                        Text("$\(Int(c.spent).formatted())")
                            .font(.flOverline)
                            .foregroundStyle(WarmPalette.ink3)
                    }
            }
            .chartXScale(domain: 0...(maxSpent * 1.2))
            .chartXAxis(.hidden)
            .frame(height: CGFloat(top.count) * 38 + 10)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
    }

    // MARK: Fixed vs variable split

    private func fixedVsVariable(_ s: BudgetStats) -> some View {
        let total = max(s.recurringMonthly + s.variableThisMonth, 1)
        let fixedFrac = s.recurringMonthly / total
        return VStack(alignment: .leading, spacing: 10) {
            WarmSectionHeader(title: "Fixed vs variable")
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Rectangle().fill(AccentTheme.ocean.color)
                        .frame(width: geo.size.width * fixedFrac)
                    Rectangle().fill(AccentTheme.saffron.color)
                }
                .clipShape(Capsule())
            }
            .frame(height: 12)
            HStack {
                legendDot(AccentTheme.ocean.color, "Fixed \u{00B7} $\(Int(s.recurringMonthly).formatted())")
                Spacer()
                legendDot(AccentTheme.saffron.color, "Variable \u{00B7} $\(Int(s.variableThisMonth).formatted())")
            }
            .font(.flCaption)
            .foregroundStyle(WarmPalette.ink3)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }

    private var emptyState: some View {
        WarmEmptyState(
            title: "See where your money goes",
            systemImage: "chart.line.uptrend.xyaxis",
            description: "Add receipts to see trends and insights."
        )
    }
}
