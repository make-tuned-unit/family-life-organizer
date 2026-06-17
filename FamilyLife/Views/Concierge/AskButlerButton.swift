import SwiftUI

/// App-wide channel for requesting the concierge chat with a seeded prompt.
/// Feature views call `ask(_:)`; MainTabView switches to the Concierge tab and
/// ConciergeView presents the chat (or the paywall, if not premium).
@Observable
final class ConciergeLaunch {
    var requestedPrompt: String?

    func ask(_ prompt: String) { requestedPrompt = prompt }

    /// Read and clear the pending prompt.
    func consume() -> String? {
        defer { requestedPrompt = nil }
        return requestedPrompt
    }
}

/// A small toolbar entry that hands a contextual prompt to the concierge.
/// Hidden until the user opts into the AI concierge.
struct AskButlerButton: View {
    @Environment(ConciergeLaunch.self) private var launch
    @AppStorage("aiConciergeEnabled") private var aiConciergeEnabled = false
    let prompt: String

    var body: some View {
        if aiConciergeEnabled {
            Button { launch.ask(prompt) } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AccentTheme.saffron.color)
            }
            .accessibilityLabel("Ask your concierge")
        }
    }
}

/// Opt-in / intro screen for the AI concierge. Reached discreetly from More.
/// Until enabled here, every AI surface (floating launcher, contextual ✨
/// buttons) stays hidden.
struct ConciergeIntroView: View {
    @Environment(SubscriptionService.self) private var subscription
    @AppStorage("aiConciergeEnabled") private var aiConciergeEnabled = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(AccentTheme.saffron.color)
                    Text("AI Concierge")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(WarmPalette.ink1)
                    Text("A warm daily brief of what needs you across the family, plus a chat that can look things up and add to your calendar, lists, and budget.")
                        .font(.system(size: 15))
                        .foregroundStyle(WarmPalette.ink3)
                }

                Toggle(isOn: $aiConciergeEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable AI Concierge")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(WarmPalette.ink1)
                        Text(aiConciergeEnabled
                             ? "A ✨ button now appears across from chat."
                             : "Adds a discreet ✨ launcher to your home screen.")
                            .font(.system(size: 13))
                            .foregroundStyle(WarmPalette.ink3)
                    }
                }
                .tint(AccentTheme.saffron.color)
                .padding(14)
                .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))

                VStack(alignment: .leading, spacing: 6) {
                    Label("The daily brief is free.", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(WarmPalette.ink2)
                    Label(subscription.isPremium
                          ? "Concierge chat is active on your household."
                          : "Concierge chat needs Premium.",
                          systemImage: subscription.isPremium ? "checkmark.seal.fill" : "lock.fill")
                        .foregroundStyle(WarmPalette.ink2)
                }
                .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            .padding(.top, 8)
            .padding(.bottom, DesignTokens.Spacing.bottomBuffer)
        }
        .background { AmbientBackground(style: .home) }
        .navigationTitle("AI Concierge")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
    }
}
