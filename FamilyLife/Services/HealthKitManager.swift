import Foundation
import HealthKit

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
            // HealthKit not available (simulator, missing entitlement, or missing Info.plist key)
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
}
