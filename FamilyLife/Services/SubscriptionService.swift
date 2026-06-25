import Foundation
import StoreKit

/// Manages the Concierge subscription via StoreKit 2.
///
/// Two tiers (Lite / Premium), each billed monthly or yearly. Entitlement is
/// per-HOUSEHOLD and the backend is authoritative: this device may have no local
/// transaction yet still be entitled because another household member subscribed —
/// so `refresh` always reconciles with the server, which also reports the tier.
@Observable
final class SubscriptionService {
    enum Tier: String { case lite, premium }
    enum Period: String { case monthly, yearly }

    static let productIDs: [String] = [
        "com.mylauft.kinrows.concierge.lite.monthly",
        "com.mylauft.kinrows.concierge.lite.yearly",
        "com.mylauft.kinrows.concierge.premium.monthly",
        "com.mylauft.kinrows.concierge.premium.yearly",
    ]
    // Legacy single-tier product still counts as an entitlement (maps to premium).
    static let legacyProductID = "com.mylauft.kinrows.concierge.monthly"
    private static let entitlementIDs = Set(productIDs + [legacyProductID])

    static func productID(_ tier: Tier, _ period: Period) -> String {
        "com.mylauft.kinrows.concierge.\(tier.rawValue).\(period.rawValue)"
    }

    private(set) var isPremium = false           // entitled to ANY paid tier
    private(set) var tier: Tier?                  // active tier per backend
    private(set) var products: [Product] = []
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
            await loadProducts()
            await refresh(api: api)
        }
    }

    deinit { updatesTask?.cancel() }

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            // Stable order: Premium before Lite, monthly before yearly.
            products = loaded.sorted { ($0.price, $0.id) > ($1.price, $1.id) }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func product(_ tier: Tier, _ period: Period) -> Product? {
        products.first { $0.id == Self.productID(tier, period) }
    }

    /// Reconcile entitlement: sync any local transaction to the backend, then
    /// trust the backend's household-level answer (premium flag + tier).
    @discardableResult
    func refresh(api: APIService) async -> Bool {
        var localJWS: String?
        for await result in Transaction.currentEntitlements {
            if case .verified(let txn) = result,
               Self.entitlementIDs.contains(txn.productID),
               txn.revocationDate == nil {
                localJWS = result.jwsRepresentation
            }
        }

        var status: SubscriptionStatus?
        if let localJWS {
            status = try? await api.verifySubscription(signedTransaction: localJWS)
        }
        if status == nil {
            status = try? await api.fetchSubscriptionStatus()
        }
        if let status {
            isPremium = status.premium
            tier = status.tier.flatMap(Tier.init(rawValue:))
        }
        return isPremium
    }

    func purchase(_ product: Product, api: APIService) async {
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
