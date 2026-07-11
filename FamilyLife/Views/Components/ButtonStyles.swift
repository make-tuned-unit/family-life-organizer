import SwiftUI

// MARK: - FLPrimaryButtonStyle
// Filled glass with tab tint color. Use for the main CTA in any form.
// Usage: Button("Save") {}.buttonStyle(.flPrimary(tint: TabAccent.home.color))
// NOTE: ButtonStyle.makeBody applies material backgrounds directly because
//       ButtonStyle bodies cannot chain View extension modifiers via flCard().

struct FLPrimaryButtonStyle: ButtonStyle {
    var tint: Color = TabAccent.home.color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            .padding(.vertical, 12)
            .background(tint, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - FLSecondaryButtonStyle
// Untinted interactive glass. Use for secondary actions.

struct FLSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            .padding(.vertical, 12)
            .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - FLDestructiveButtonStyle
// Red-tinted glass. Use for delete/cancel/irreversible actions.

struct FLDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            .padding(.vertical, 12)
            .background(.red, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - FLCTAButtonStyle
// THE primary call-to-action: full-width warm-ink bar with cream text,
// card-radius corners, press scale. One CTA look everywhere — "Send request",
// "Start cooking", "Confirm availability" — so the eye always knows the main
// move. Pass a fill for semantic variants (e.g. WarmPalette.good for a
// final confirm).

struct FLCTAButtonStyle: ButtonStyle {
    var fill: Color = WarmPalette.ink1

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.flSubheadline.weight(.semibold))
            .foregroundStyle(WarmPalette.cream1)
            .tint(WarmPalette.cream1)  // inner ProgressView spinners read cream
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background(fill, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

// MARK: - FLCardPressStyle
// Press feedback for tappable CARDS (whole-card buttons / navigation rows):
// a gentle scale + dim, matching Apple's own card-press behavior. Use with
// content that already draws its own .flCard() surface.

struct FLCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

// MARK: - Convenience accessors

extension ButtonStyle where Self == FLPrimaryButtonStyle {
    static var flPrimary: FLPrimaryButtonStyle { .init() }
    static func flPrimary(tint: Color) -> FLPrimaryButtonStyle { .init(tint: tint) }
}

extension ButtonStyle where Self == FLSecondaryButtonStyle {
    static var flSecondary: FLSecondaryButtonStyle { .init() }
}

extension ButtonStyle where Self == FLDestructiveButtonStyle {
    static var flDestructive: FLDestructiveButtonStyle { .init() }
}

extension ButtonStyle where Self == FLCardPressStyle {
    static var flCardPress: FLCardPressStyle { .init() }
}

extension ButtonStyle where Self == FLCTAButtonStyle {
    static var flCTA: FLCTAButtonStyle { .init() }
    static func flCTA(fill: Color) -> FLCTAButtonStyle { .init(fill: fill) }
}

// MARK: - Preview

#Preview("Button Styles") {
    ZStack {
        AmbientBackground(style: .home)

        VStack(spacing: DesignTokens.Spacing.cardGap) {
            Button("Save Changes") {}
                .buttonStyle(.flPrimary(tint: TabAccent.home.color))

            Button("Cancel") {}
                .buttonStyle(.flSecondary)

            Button("Delete Item") {}
                .buttonStyle(.flDestructive)
        }
        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
    }
}
