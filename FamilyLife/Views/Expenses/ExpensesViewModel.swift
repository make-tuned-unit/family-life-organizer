import Foundation

@MainActor
@Observable
final class ExpensesViewModel {
    var displayedMonth = Date()
    var budgetItems: [BudgetSummaryResponse] = []
    var isLoading = false
    var error: String?

    var displayMonthString: String {
        DateFormatter.monthYear.string(from: displayedMonth)
    }

    /// Where we actually are in the displayed month — only meaningful for the
    /// current month; past months are settled and future ones haven't begun.
    var monthPhaseString: String? {
        let cal = Calendar.current
        let now = Date()
        guard cal.isDate(displayedMonth, equalTo: now, toGranularity: .month) else {
            if displayedMonth < now { return "wrapped up" }
            return "coming up"
        }
        let day = cal.component(.day, from: now)
        let total = cal.range(of: .day, in: .month, for: now)?.count ?? 30
        switch Double(day) / Double(total) {
        case ..<0.1:  return "just started"
        case ..<0.35: return "early days"
        case ..<0.65: return "halfway through"
        case ..<0.9:  return "final stretch"
        default:      return "almost done"
        }
    }

    var monthParam: String {
        DateFormatter.yearMonth.string(from: displayedMonth)
    }

    func previousMonth() {
        displayedMonth = Calendar.current.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
    }

    func nextMonth() {
        displayedMonth = Calendar.current.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
    }

    func loadAll(api: APIService) async {
        isLoading = true
        error = nil
        do {
            budgetItems = try await api.fetchBudget(month: monthParam)
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
