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
