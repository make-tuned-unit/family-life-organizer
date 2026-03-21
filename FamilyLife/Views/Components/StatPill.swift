import SwiftUI

// MARK: - StatPill
// Glass capsule pill showing an icon, a large number, and a small label.
// Apple Health ring summary style.
// Usage: StatPill(title: "Tasks", value: "4", icon: "checkmark.circle", color: .teal)
//
// NOTE: Uses .flCard(tint:) — do NOT call .glassEffect() directly here.

struct StatPill: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(.primary)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(minWidth: 72)
        .padding(DesignTokens.Spacing.cardPadding)
        .flCard(tint: color)
    }
}

// MARK: - Preview

#Preview("StatPill Row") {
    ZStack {
        AmbientBackground(style: .home)

        HStack(spacing: DesignTokens.Spacing.cardGap) {
            StatPill(title: "Tasks", value: "4", icon: "checkmark.circle", color: .teal)
            StatPill(title: "Events", value: "2", icon: "calendar", color: .purple)
            StatPill(title: "Pantry", value: "18", icon: "cart.fill", color: .cyan)
        }
        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
    }
}
