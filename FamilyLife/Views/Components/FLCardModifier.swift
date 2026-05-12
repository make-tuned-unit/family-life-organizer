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
        if interactive {
            content
                .flGlassSurface(
                    tint: tint,
                    in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                )
        } else {
            content
                .flGlassSurface(
                    tint: tint,
                    in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                )
        }
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

    @ViewBuilder
    func flGlassSurface<S: Shape>(tint: Color = .clear, strokeOpacity: Double = 0.15, in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.tint(tint), in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(tint.opacity(strokeOpacity), lineWidth: 0.5))
        }
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
                    .foregroundStyle(WarmPalette.ink3)
            }
            .padding(DesignTokens.Spacing.cardPadding)
            .flCard(tint: TabAccent.home.color)
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
                        .foregroundStyle(WarmPalette.ink3)
                }
                .padding(DesignTokens.Spacing.cardPadding)
                .flCard(tint: AccentTheme.mauve.color, interactive: true)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            // Untinted card
            VStack(alignment: .leading, spacing: 8) {
                Label("Untinted Card (.clear)", systemImage: "square.dashed")
                    .font(.headline)
                Text("Pass .clear for a neutral glass surface with no color tint.")
                    .font(.caption)
                    .foregroundStyle(WarmPalette.ink3)
            }
            .padding(DesignTokens.Spacing.cardPadding)
            .flCard()
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
    }
}
