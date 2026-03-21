import SwiftUI

// MARK: - FilterChip
// Glass toggle chip for filtering/sorting.
// Unselected: outline border only, muted foreground.
// Selected: filled glass with tint color via .flCard(tint:), white foreground.
//
// Usage: FilterChip("All", isSelected: filter == .all, tint: .teal) { filter = .all }

struct FilterChip: View {
    let label: String
    var icon: String? = nil
    let isSelected: Bool
    var tint: Color = .teal
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption2)
                }
                Text(label)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, DesignTokens.Spacing.chipPadding * 2)
            .padding(.vertical, DesignTokens.Spacing.chipVerticalPadding * 2)
            .foregroundStyle(isSelected ? .white : .secondary)
        }
        .if(isSelected) { view in
            view.flCard(tint: tint)
        }
        .if(!isSelected) { view in
            view
                .background(.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.chip)
                        .stroke(.secondary.opacity(0.4), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.chip))
        }
    }
}

// MARK: - Conditional modifier helper (private to this file)

private extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) }
        else { self }
    }
}

// MARK: - Preview

#Preview("FilterChip States") {
    ZStack {
        AmbientBackground(style: .decisions)

        HStack(spacing: DesignTokens.Spacing.cardGap) {
            FilterChip(label: "All", isSelected: true, tint: .indigo) {}
            FilterChip(label: "Open", isSelected: false, tint: .indigo) {}
            FilterChip(label: "Resolved", isSelected: false, tint: .indigo) {}
        }
        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
    }
}
