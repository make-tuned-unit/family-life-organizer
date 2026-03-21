import SwiftUI

// MARK: - FLCard ViewModifier
// Single entry point for all glass card surfaces in the app.
// Usage:
//   .flCard(tint: .blue)                      // display-only card
//   .flCard(tint: .blue, interactive: true)   // tappable card (scale + shimmer)
//
// IMPORTANT: Apply padding INSIDE the card content BEFORE calling .flCard().
//   ✓  content.padding(DesignTokens.Spacing.cardPadding).flCard(tint: color)
//   ✗  content.flCard(tint: color).padding(...)   ← clips glass blur halo

struct FLCardModifier: ViewModifier {
    var tint: Color = .clear
    var interactive: Bool = false

    func body(content: Content) -> some View {
        let effect: GlassEffectStyle = interactive
            ? .regular.tint(tint.opacity(DesignTokens.Opacity.interactiveTint)).interactive()
            : .regular.tint(tint.opacity(DesignTokens.Opacity.cardTint))
        content
            .glassEffect(effect, in: .rect(cornerRadius: DesignTokens.CornerRadius.card))
    }
}

extension View {
    /// Apply the standard FamilyLife glass card surface.
    /// - Parameters:
    ///   - tint: The tab accent color to tint the glass surface. Pass `.clear` for untinted.
    ///   - interactive: If true, adds `.interactive()` for scale/shimmer on press. Use for tappable rows.
    func flCard(tint: Color = .clear, interactive: Bool = false) -> some View {
        modifier(FLCardModifier(tint: tint, interactive: interactive))
    }
}

// MARK: - Preview

#Preview("FLCard Variants") {
    ZStack {
        AmbientBackground(style: .home)

        VStack(spacing: DesignTokens.Spacing.cardGap) {
            // Standard display card
            VStack(alignment: .leading, spacing: 8) {
                Label("Standard Card", systemImage: "rectangle.fill")
                    .font(.headline)
                Text("Use for non-tappable content areas. Glass refracts the ambient gradient behind it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(DesignTokens.Spacing.cardPadding)
            .flCard(tint: .teal)
            .frame(maxWidth: .infinity)

            // Interactive card
            Button {
                // preview tap
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Interactive Card", systemImage: "hand.tap.fill")
                        .font(.headline)
                    Text("Use for tappable rows. Adds scale and shimmer on press via .interactive().")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(DesignTokens.Spacing.cardPadding)
                .flCard(tint: .purple, interactive: true)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            // Untinted card
            VStack(alignment: .leading, spacing: 8) {
                Label("Untinted Card (.clear)", systemImage: "square.dashed")
                    .font(.headline)
                Text("Pass .clear for a neutral glass surface with no color tint.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(DesignTokens.Spacing.cardPadding)
            .flCard()
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
    }
}
