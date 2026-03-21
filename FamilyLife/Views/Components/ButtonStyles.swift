import SwiftUI

// MARK: - FLPrimaryButtonStyle
// Filled glass with tab tint color. Use for the main CTA in any form.
// Usage: Button("Save") {}.buttonStyle(.flPrimary(tint: .teal))
// NOTE: ButtonStyle.makeBody uses .glassEffect() directly — ButtonStyle bodies
//       cannot chain View extension modifiers via flCard() in the standard way.

struct FLPrimaryButtonStyle: ButtonStyle {
    var tint: Color = .teal

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            .padding(.vertical, 12)
            .glassEffect(
                .regular.tint(tint.opacity(DesignTokens.Opacity.primaryButtonTint)).interactive(),
                in: .rect(cornerRadius: DesignTokens.CornerRadius.card)
            )
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
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: DesignTokens.CornerRadius.card))
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
            .glassEffect(
                .regular.tint(.red.opacity(DesignTokens.Opacity.primaryButtonTint)).interactive(),
                in: .rect(cornerRadius: DesignTokens.CornerRadius.card)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
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

// MARK: - Preview

#Preview("Button Styles") {
    ZStack {
        AmbientBackground(style: .home)

        VStack(spacing: DesignTokens.Spacing.cardGap) {
            Button("Save Changes") {}
                .buttonStyle(.flPrimary(tint: .teal))

            Button("Cancel") {}
                .buttonStyle(.flSecondary)

            Button("Delete Item") {}
                .buttonStyle(.flDestructive)
        }
        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
    }
}
