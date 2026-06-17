import Foundation
import StoreKit

/// Manages the Concierge premium subscription via StoreKit 2.
///
/// Entitlement is per-HOUSEHOLD: the backend is authoritative. This device may
/// have no local transaction yet still be premium because another household
/// member subscribed — so `refresh` always reconciles with the server.
@Observable
final class SubscriptionService {
    static let productID = "com.mylauft.kinrows.concierge.monthly"

    private(set) var isPremium = false
    private(set) var product: Product?
    private(set) var isPurchasing = false
    var lastError: String?

    private var updatesTask: Task<Void, Never>?

    /// Begin listening for transaction updates and load initial state.
    func start(api: APIService) {
        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let txn) = update { await txn.finish() }
                await self?.refresh(api: api)
            }
        }
        Task {
            await loadProduct()
            await refresh(api: api)
        }
    }

    deinit { updatesTask?.cancel() }

    func loadProduct() async {
        do {
            product = try await Product.products(for: [Self.productID]).first
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Reconcile entitlement: sync any local transaction to the backend, then
    /// trust the backend's household-level answer.
    @discardableResult
    func refresh(api: APIService) async -> Bool {
        var localJWS: String?
        for await result in Transaction.currentEntitlements {
            if case .verified(let txn) = result,
               txn.productID == Self.productID,
               txn.revocationDate == nil {
                localJWS = result.jwsRepresentation
            }
        }

        if let localJWS, let status = try? await api.verifySubscription(signedTransaction: localJWS) {
            isPremium = status.premium
        } else if let status = try? await api.fetchSubscriptionStatus() {
            isPremium = status.premium
        }
        return isPremium
    }

    func purchase(api: APIService) async {
        guard let product else { lastError = "Product unavailable"; return }
        isPurchasing = true
        lastError = nil
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let txn) = verification {
                    // Finish only once the backend has recorded the entitlement,
                    // otherwise leave it for Transaction.updates to retry.
                    let synced = (try? await api.verifySubscription(signedTransaction: verification.jwsRepresentation)) != nil
                    if synced { await txn.finish() }
                }
                await refresh(api: api)
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func restore(api: APIService) async {
        try? await AppStore.sync()
        await refresh(api: api)
    }
}
