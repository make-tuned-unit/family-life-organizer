import Foundation

@Observable
final class ExpensesViewModel {
    var displayedMonth = Date()
    var budgetItems: [BudgetSummaryResponse] = []
    var receipts: [ReceiptResponse] = []
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
        async let budgetReq: () = loadBudget(api: api)
        async let receiptsReq: () = loadReceipts(api: api)
        _ = await (budgetReq, receiptsReq)
        isLoading = false
    }

    private func loadBudget(api: APIService) async {
        do {
            budgetItems = try await api.fetchBudget(month: monthParam)
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }

    private func loadReceipts(api: APIService) async {
        do {
            receipts = try await api.fetchReceipts(month: monthParam)
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }


    func deleteReceipt(_ id: Int, api: APIService) async {
        do {
            try await api.deleteReceipt(id: id)
            receipts.removeAll { $0.id == id }
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }
}
