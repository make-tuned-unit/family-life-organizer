import Foundation
import StoreKit

extension Notification.Name {
    /// Household Concierge entitlement just became active (web Checkout or StoreKit).
    static let kinrowsSubscriptionActivated = Notification.Name("kinrowsSubscriptionActivated")
}

/// Manages the Concierge subscription.
///
/// Web Stripe Checkout is the app-first path: the signed-in app opens Safari,
/// the user pays (Apple Pay works there), then a `kinrows://` return plus a
/// foreground refresh unlock the household. StoreKit remains available as
/// "Subscribe with Apple" / Restore. Entitlement is per-HOUSEHOLD and the
/// backend is authoritative: this device may have no local transaction yet
/// still be entitled because another household member subscribed — so `refresh`
/// always reconciles with the server, which also reports the tier.
@MainActor
@Observable
final class SubscriptionService {
    enum Tier: String { case lite, premium }
    enum Period: String { case monthly, yearly }

    static let productIDs: [String] = [
        "com.kinrows.app.concierge.lite.monthly",
        "com.kinrows.app.concierge.lite.yearly",
        "com.kinrows.app.concierge.premium.monthly",
        "com.kinrows.app.concierge.premium.yearly",
    ]
    // Products sold under the previous bundle ID (com.mylauft.kinrows). They can
    // no longer be BOUGHT — only the four above are offered — but a transaction
    // from before the move still resolves as an entitlement, so nobody who paid
    // loses access to what they paid for. The first is the pre-tier single
    // product, which has always mapped to premium.
    static let legacyProductIDs: [String] = [
        "com.mylauft.kinrows.concierge.monthly",
        "com.mylauft.kinrows.concierge.lite.monthly",
        "com.mylauft.kinrows.concierge.lite.yearly",
        "com.mylauft.kinrows.concierge.premium.monthly",
        "com.mylauft.kinrows.concierge.premium.yearly",
    ]
    private static let entitlementIDs = Set(productIDs + legacyProductIDs)

    static func productID(_ tier: Tier, _ period: Period) -> String {
        "com.kinrows.app.concierge.\(tier.rawValue).\(period.rawValue)"
    }

    private(set) var isPremium = false           // entitled to ANY paid tier
    private(set) var tier: Tier?                  // active tier per backend
    private(set) var products: [Product] = []
    private(set) var catalog: SubscriptionCatalog?
    private(set) var isPurchasing = false
    /// True after Safari Checkout opened; cleared on return, cancel, or unlock.
    private(set) var pendingWebCheckout = false
    var lastError: String?

    func clearError() { lastError = nil }

    @ObservationIgnored private var lastCheckoutSessionId: String?

    // `nonisolated(unsafe)` so the nonisolated `deinit` can cancel it. Plain
    // `nonisolated` is rejected on mutable stored properties; `(unsafe)` is the
    // only form allowed. Only ever assigned on the main actor, and
    // `Task.cancel()` is safe to call from anywhere.
    //
    // `@ObservationIgnored` is required: without it the @Observable macro
    // rewrites this into a computed property, and `nonisolated(unsafe)` on a
    // computed property does nothing. Nothing observes this task anyway; it is
    // bookkeeping, not state a view renders.
    @ObservationIgnored nonisolated(unsafe) private var updatesTask: Task<Void, Never>?

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
            await loadCatalog(api: api)
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
            // StoreKit catalog is optional — web Checkout is the app-first path.
        }
    }

    func loadCatalog(api: APIService) async {
        catalog = try? await api.fetchSubscriptionCatalog(currency: Self.presentmentCurrency())
    }

    func product(_ tier: Tier, _ period: Period) -> Product? {
        products.first { $0.id == Self.productID(tier, period) }
    }

    func catalogPlan(_ tier: Tier, _ period: Period) -> SubscriptionCatalog.Plan? {
        catalog?.plan(productId: Self.productID(tier, period))
    }

    static func presentmentCurrency() -> String? {
        let raw = Locale.current.currency?.identifier.lowercased() ?? ""
        if raw == "cad" || raw == "usd" || raw == "eur" { return raw }
        return nil
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
            apply(status)
        }
        return isPremium
    }

    private func apply(_ status: SubscriptionStatus) {
        isPremium = status.premium
        tier = status.tier.flatMap(Tier.init(rawValue:))
        if isPremium {
            pendingWebCheckout = false
        }
    }

    private func applyConfirm(_ status: CheckoutConfirmResponse) {
        isPremium = status.premium
        tier = status.tier.flatMap(Tier.init(rawValue:))
        if isPremium {
            pendingWebCheckout = false
            NotificationCenter.default.post(name: .kinrowsSubscriptionActivated, object: nil)
        }
    }

    /// Opens Stripe Checkout in Safari, bound to this signed-in household.
    /// Returns the Checkout URL for the view to hand to `openURL`.
    func startWebCheckout(tier: Tier, period: Period, api: APIService) async -> URL? {
        isPurchasing = true
        lastError = nil
        let productId = Self.productID(tier, period)
        do {
            let session = try await api.createCheckoutSession(
                productId: productId,
                currency: Self.presentmentCurrency(),
                source: "app"
            )
            guard let url = URL(string: session.url) else {
                lastError = "Could not open checkout."
                isPurchasing = false
                return nil
            }
            lastCheckoutSessionId = session.id
            pendingWebCheckout = true
            isPurchasing = false
            return url
        } catch {
            pendingWebCheckout = false
            lastError = error.localizedDescription
            isPurchasing = false
            return nil
        }
    }

    /// Deeplink return from `/open/subscribed` (`kinrows://subscribed?session_id=`).
    func handleCheckoutReturn(sessionId: String?, api: APIService) async {
        isPurchasing = true
        lastError = nil
        defer { isPurchasing = false }
        let id = sessionId?.isEmpty == false ? sessionId : lastCheckoutSessionId
        if let id {
            if let confirmed = try? await api.confirmCheckoutSession(id) {
                applyConfirm(confirmed)
                if isPremium { return }
            }
        }
        await refresh(api: api)
        if isPremium {
            NotificationCenter.default.post(name: .kinrowsSubscriptionActivated, object: nil)
        }
    }

    func handleCheckoutCanceled() {
        pendingWebCheckout = false
        lastCheckoutSessionId = nil
        isPurchasing = false
    }

    /// User switched back from Safari without tapping Open Kinrows — confirm
    /// the pending session with the app's own cookie.
    func handleAppForeground(api: APIService) async {
        guard pendingWebCheckout else { return }
        if let id = lastCheckoutSessionId,
           let confirmed = try? await api.confirmCheckoutSession(id) {
            applyConfirm(confirmed)
            if isPremium { return }
        }
        await refresh(api: api)
        if isPremium {
            NotificationCenter.default.post(name: .kinrowsSubscriptionActivated, object: nil)
        }
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
                if isPremium {
                    NotificationCenter.default.post(name: .kinrowsSubscriptionActivated, object: nil)
                }
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
        if isPremium {
            NotificationCenter.default.post(name: .kinrowsSubscriptionActivated, object: nil)
        }
    }
}
