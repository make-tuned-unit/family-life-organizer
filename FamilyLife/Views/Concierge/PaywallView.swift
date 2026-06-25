import SwiftUI
import StoreKit

/// Premium upsell for the conversational concierge. The daily brief stays free;
/// this unlocks the butler you can talk to and that acts on your behalf.
///
/// Two tiers — Lite and Premium — each billable monthly or yearly (yearly = two
/// months free). Both tiers get every feature; they differ only by how many chats
/// per day the household gets.
struct PaywallView: View {
    @Environment(APIService.self) private var api
    @Environment(SubscriptionService.self) private var subscription
    @Environment(\.dismiss) private var dismiss

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
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(accent)
            Text("Your AI Life Concierge")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(WarmPalette.ink1)
            Text("A personal butler for your family — always organized, always one step ahead.")
                .font(.system(size: 16))
                .foregroundStyle(WarmPalette.ink3)
        }
    }

    private var perkList: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(perks, id: \.0) { icon, text in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 28, height: 28)
                        .background(accent.opacity(0.15), in: Circle())
                    Text(text)
                        .font(.system(size: 15))
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
        let product = subscription.product(tier, period)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(WarmPalette.ink1)
                if recommended {
                    Text("Best value")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(accent.opacity(0.15), in: Capsule())
                }
                Spacer()
                Text(priceLabel(product))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WarmPalette.ink1)
            }
            Text(blurb)
                .font(.system(size: 14))
                .foregroundStyle(WarmPalette.ink3)

            Button {
                guard let product else { return }
                Task { await subscription.purchase(product, api: api); if subscription.isPremium { dismiss() } }
            } label: {
                Group {
                    if subscription.isPurchasing {
                        ProgressView().tint(.white)
                    } else {
                        Text("Subscribe").frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(FLPrimaryButtonStyle(tint: recommended ? accent : AccentTheme.sage.color))
            .disabled(subscription.isPurchasing || product == nil)
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .flCard(tint: recommended ? accent : AccentTheme.sage.color)
    }

    private func priceLabel(_ product: Product?) -> String {
        guard let product else { return "—" }
        return period == .yearly ? "\(product.displayPrice)/yr" : "\(product.displayPrice)/mo"
    }

    private var restoreAndLegal: some View {
        VStack(spacing: 12) {
            Button("Restore Purchases") {
                Task { await subscription.restore(api: api); if subscription.isPremium { dismiss() } }
            }
            .buttonStyle(FLSecondaryButtonStyle())

            if let error = subscription.lastError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(AccentTheme.terracotta.color)
                    .multilineTextAlignment(.center)
            }

            Text("Auto-renewing subscription. Cancel anytime in Settings.")
                .font(.system(size: 11))
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
