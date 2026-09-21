import SwiftUI
import StoreKit

/// Premium upsell for the conversational concierge. The daily brief stays free;
/// this unlocks the butler you can talk to and that acts on your behalf.
///
/// In-app purchases use StoreKit in every storefront. Web subscriptions remain
/// available on the website and unlock the same household entitlement.
///
/// Two tiers — Lite and Premium — each billable monthly or yearly (yearly = two
/// months free). Both tiers get every feature; they differ only by how many chats
/// per day the household gets.
struct PaywallView: View {
    @Environment(APIService.self) private var api
    @Environment(SubscriptionService.self) private var subscription
    @Environment(\.dismiss) private var dismiss

    @State private var period: SubscriptionService.Period = .yearly

    private let accent = KinrowsBrand.evergreen

    private let perks: [(String, String)] = [
        ("bubble.left.and.bubble.right.fill", "Chat with your concierge — ask anything about your household"),
        ("wand.and.stars", "It takes action: add events, tasks, and groceries for you"),
        ("brain.head.profile", "Remembers your family's preferences and routines"),
        ("house.fill", "One subscription covers your whole household"),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(style: .home)
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        if subscription.isPremium {
                            unlockedCard
                        } else {
                            perkList
                            periodToggle
                            planCard(tier: .premium,
                                     title: "Premium",
                                     blurb: "Up to 40 concierge chats a day",
                                     recommended: true)
                            planCard(tier: .lite,
                                     title: "Lite",
                                     blurb: "Up to 10 concierge chats a day",
                                     recommended: false)
                            restoreAndLegal
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                    .padding(.vertical, 24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .inlineError(subscription.lastError) { subscription.clearError() }
            .task { await subscription.loadProducts() }
            .onChange(of: subscription.isPremium) { _, premium in
                if premium { dismiss() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .kinrowsSubscriptionActivated)) { _ in
                dismiss()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            KinrowsIllustration(.mascot(.excited), maxWidth: 120, maxHeight: 130)
            Text("Meet Rowan, your Concierge")
                .font(.flDisplay)
                .foregroundStyle(KinrowsBrand.evergreen)
            Text("A personal butler for your family — always organized, always one step ahead.")
                .font(.flBody)
                .foregroundStyle(WarmPalette.ink3)
        }
    }

    private var unlockedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            KinrowsIllustration(.mascot(.celebrating), maxWidth: 88, maxHeight: 88)
            Text("You are in")
                .font(.flDisplaySmall)
                .foregroundStyle(KinrowsBrand.evergreen)
            Text("Concierge is on for everyone in this household.")
                .font(.flSubheadline)
                .foregroundStyle(WarmPalette.ink3)
            Button("Continue") { dismiss() }
                .buttonStyle(.flCTA)
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .flCard(tint: accent)
    }

    private var perkList: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(perks, id: \.0) { icon, text in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(accent)
                        .frame(width: 28, height: 28)
                        .background(accent.opacity(0.15), in: Circle())
                    Text(text)
                        .font(.flSubheadline)
                        .foregroundStyle(WarmPalette.ink1)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .flCard(tint: accent)
    }

    private var periodToggle: some View {
        Picker("Billing period", selection: $period) {
            Text("Monthly").tag(SubscriptionService.Period.monthly)
            Text("Yearly").tag(SubscriptionService.Period.yearly)
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private func planCard(tier: SubscriptionService.Tier, title: String, blurb: String, recommended: Bool) -> some View {
        let storeProduct = subscription.product(tier, period)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.flTitle)
                    .foregroundStyle(WarmPalette.ink1)
                if recommended {
                    Text("Best value")
                        .font(.flOverline)
                        .foregroundStyle(accent)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(accent.opacity(0.15), in: Capsule())
                }
                Spacer()
                Text(priceLabel(tier: tier, product: storeProduct))
                    .font(.flSubheadline.weight(.semibold))
                    .foregroundStyle(WarmPalette.ink1)
            }
            Text(blurb)
                .font(.flSubheadline)
                .foregroundStyle(WarmPalette.ink3)

            Button {
                guard let storeProduct else { return }
                Task { await subscription.purchase(storeProduct, api: api) }
            } label: {
                if subscription.isPurchasing {
                    ProgressView()
                } else {
                    Text(storeProduct == nil ? "Currently unavailable" : "Subscribe with Apple")
                }
            }
            .buttonStyle(.flCTA(fill: recommended ? accent : AccentTheme.sage.color))
            .disabled(subscription.isPurchasing || storeProduct == nil)

        }
        .padding(DesignTokens.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .flCard(tint: recommended ? accent : AccentTheme.sage.color)
    }

    private func priceLabel(tier: SubscriptionService.Tier, product: Product?) -> String {
        if let product {
            return period == .yearly ? "\(product.displayPrice)/yr" : "\(product.displayPrice)/mo"
        }
        return "—"
    }

    private var restoreAndLegal: some View {
        VStack(spacing: 12) {
            Text("Payment is handled by the App Store. One subscription covers your household.")
                .font(.flCaption)
                .foregroundStyle(WarmPalette.ink2)
                .multilineTextAlignment(.center)

            Button("Restore Purchases") {
                Task { await subscription.restore(api: api) }
            }
            .buttonStyle(FLSecondaryButtonStyle())
            .disabled(subscription.isPurchasing)

            if subscription.products.isEmpty {
                Button("Retry loading plans") {
                    Task { await subscription.loadProducts() }
                }
                .buttonStyle(FLSecondaryButtonStyle())
                .disabled(subscription.isPurchasing)
            }

            Text("Payment is charged to your Apple ID at confirmation. Your subscription automatically renews unless cancelled at least 24 hours before the current period ends. Manage or cancel your subscription in your App Store account settings.")
                .font(.flCaption2)
                .foregroundStyle(WarmPalette.ink3)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Link("Privacy Policy", destination: AppConfig.privacyPolicyURL)
                Link("Terms of Use", destination: AppConfig.termsOfUseURL)
            }
            .font(.flCaption.weight(.medium))
        }
    }
}

#Preview {
    PaywallView()
        .environment(APIService())
        .environment(SubscriptionService())
}
