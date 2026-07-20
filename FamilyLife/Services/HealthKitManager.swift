import Foundation
import HealthKit

@MainActor
@Observable
final class HealthKitManager {
    var isAvailable: Bool
    var isAuthorized = false

    private let store: HKHealthStore?

    init() {
        let available = HKHealthStore.isHealthDataAvailable()
        self.store = available ? HKHealthStore() : nil
        self.isAvailable = available
    }

    func requestStepAuthorization() async -> Bool {
        guard let store, isAvailable else { return false }
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return false }

        do {
            try await store.requestAuthorization(toShare: Set(), read: Set([stepType]))
            isAuthorized = true
            return true
        } catch {
            return false
        }
    }

    func requestFlightsAuthorization() async -> Bool {
        guard let store, isAvailable else { return false }
        guard let flightsType = HKQuantityType.quantityType(forIdentifier: .flightsClimbed) else { return false }

        do {
            try await store.requestAuthorization(toShare: Set(), read: Set([flightsType]))
            isAuthorized = true
            return true
        } catch {
            return false
        }
    }

    func fetchSteps(from startDate: Date, to endDate: Date) async -> Double {
        guard let store, isAvailable else { return 0 }
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return 0 }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: min(endDate, Date()), options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, _ in
                let steps = result?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                continuation.resume(returning: steps)
            }
            store.execute(query)
        }
    }

    /// Per-day totals for a quantity type, bucketed by local calendar day.
    /// Returns one entry per day with steps/flights > 0. This is the source of
    /// truth for rivalry sync — each day is pushed as an idempotent daily total.
    func fetchDailyTotals(for identifier: HKQuantityTypeIdentifier, from startDate: Date, to endDate: Date) async -> [(day: Date, value: Double)] {
        guard let store, isAvailable else { return [] }
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else { return [] }

        let calendar = Calendar.current
        let anchor = calendar.startOfDay(for: startDate)
        let end = min(endDate, Date())
        guard end > anchor else { return [] }

        let predicate = HKQuery.predicateForSamples(withStart: anchor, end: end, options: .strictStartDate)
        var interval = DateComponents()
        interval.day = 1

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchor,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, results, _ in
                var out: [(day: Date, value: Double)] = []
                results?.enumerateStatistics(from: anchor, to: end) { stat, _ in
                    let value = stat.sumQuantity()?.doubleValue(for: .count()) ?? 0
                    if value > 0 { out.append((day: stat.startDate, value: value)) }
                }
                continuation.resume(returning: out)
            }
            store.execute(query)
        }
    }

    func fetchFlightsClimbed(from startDate: Date, to endDate: Date) async -> Double {
        guard let store, isAvailable else { return 0 }
        guard let flightsType = HKQuantityType.quantityType(forIdentifier: .flightsClimbed) else { return 0 }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: min(endDate, Date()), options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: flightsType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, _ in
                let flights = result?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                continuation.resume(returning: flights)
            }
            store.execute(query)
        }
    }
}
