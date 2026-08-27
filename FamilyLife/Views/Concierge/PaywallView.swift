import SwiftUI
import StoreKit

/// Premium upsell for the conversational concierge. The daily brief stays free;
/// this unlocks the butler you can talk to and that acts on your behalf.
///
/// App-first path: Subscribe opens Safari Checkout (Apple Pay lives there),
/// then a `kinrows://` return unlocks the household without a second sign-in.
/// StoreKit remains as Restore / Subscribe with Apple.
///
/// Two tiers — Lite and Premium — each billable monthly or yearly (yearly = two
/// months free). Both tiers get every feature; they differ only by how many chats
/// per day the household gets.
struct PaywallView: View {
    @Environment(APIService.self) private var api
    @Environment(SubscriptionService.self) private var subscription
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var period: SubscriptionService.Period = .yearly

    private let accent = AccentTheme.saffron.color

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
            .task { await subscription.loadCatalog(api: api) }
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
            Image(systemName: "sparkles")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(accent)
            Text("Your AI Life Concierge")
                .font(.flScreenTitle)
                .foregroundStyle(WarmPalette.ink1)
            Text(subscription.pendingWebCheckout
                 ? "Finish in Safari, then we will bring you back and unlock Concierge."
                 : "A personal butler for your family — always organized, always one step ahead.")
                .font(.flBody)
                .foregroundStyle(WarmPalette.ink3)
        }
    }

    private var unlockedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("You are in")
                .font(.flTitle)
                .foregroundStyle(WarmPalette.ink1)
            Text("Concierge is on for everyone in this household.")
                .font(.flSubheadline)
                .foregroundStyle(WarmPalette.ink3)
            Button("Continue") { dismiss() }
                .buttonStyle(.flCTA(fill: accent))
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
            Text("Yearly · 2 months free").tag(SubscriptionService.Period.yearly)
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
                Task {
                    guard let url = await subscription.startWebCheckout(tier: tier, period: period, api: api) else { return }
                    openURL(url)
                }
            } label: {
                if subscription.isPurchasing {
                    ProgressView()
                } else if subscription.pendingWebCheckout {
                    Text("Opening Safari…")
                } else {
                    Text("Subscribe")
                }
            }
            .buttonStyle(.flCTA(fill: recommended ? accent : AccentTheme.sage.color))
            .disabled(subscription.isPurchasing || subscription.pendingWebCheckout)

            if let storeProduct {
                Button("Subscribe with Apple") {
                    Task { await subscription.purchase(storeProduct, api: api) }
                }
                .font(.flCaption)
                .foregroundStyle(WarmPalette.ink3)
                .disabled(subscription.isPurchasing || subscription.pendingWebCheckout)
            }
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .flCard(tint: recommended ? accent : AccentTheme.sage.color)
    }

    private func priceLabel(tier: SubscriptionService.Tier, product: Product?) -> String {
        if let product {
            return period == .yearly ? "\(product.displayPrice)/yr" : "\(product.displayPrice)/mo"
        }
        guard let plan = subscription.catalogPlan(tier, period) else { return "—" }
        return period == .yearly ? "\(plan.displayPrice)/yr" : "\(plan.displayPrice)/mo"
    }

    private var restoreAndLegal: some View {
        VStack(spacing: 12) {
            Text("You will finish in Safari with Apple Pay, then return here automatically. No second sign-in.")
                .font(.flCaption)
                .foregroundStyle(WarmPalette.ink2)
                .multilineTextAlignment(.center)

            Button("Restore Purchases") {
                Task { await subscription.restore(api: api) }
            }
            .buttonStyle(FLSecondaryButtonStyle())

            Text("Billed on the web via Stripe. Cancel anytime. Apple subscriptions restore from Settings.")
                .font(.flCaption2)
                .foregroundStyle(WarmPalette.ink3)
                .multilineTextAlignment(.center)
        }
    }
}

#Preview {
    PaywallView()
        .environment(APIService())
        .environment(SubscriptionService())
}
