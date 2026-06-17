import SwiftUI

/// Premium upsell for the conversational concierge. The daily brief stays free;
/// this unlocks the butler you can talk to and that acts on your behalf.
struct PaywallView: View {
    @Environment(APIService.self) private var api
    @Environment(SubscriptionService.self) private var subscription
    @Environment(\.dismiss) private var dismiss

    private let accent = AccentTheme.saffron.color

    private let benefits: [(String, String)] = [
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
                        benefitList
                        Spacer(minLength: 8)
                        purchaseSection
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

    private var benefitList: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(benefits, id: \.0) { icon, text in
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

    @ViewBuilder
    private var purchaseSection: some View {
        VStack(spacing: 12) {
            Button {
                Task { await subscription.purchase(api: api); if subscription.isPremium { dismiss() } }
            } label: {
                Group {
                    if subscription.isPurchasing {
                        ProgressView().tint(.white)
                    } else if let product = subscription.product {
                        Text("Subscribe — \(product.displayPrice)/month")
                    } else {
                        Text("Subscribe")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(FLPrimaryButtonStyle(tint: accent))
            .disabled(subscription.isPurchasing || subscription.product == nil)

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
