import SwiftUI

// MARK: - BadgeSemantic
// Semantic states for BadgeLabel. Maps each state to a canonical color.
// Use semantic cases for standard states; .custom(Color) for one-off tints.

enum BadgeSemantic {
    case overdue        // .red
    case expiringSoon   // .orange
    case done           // .green
    case info           // .blue
    case custom(Color)

    var color: Color {
        switch self {
        case .overdue:          .red
        case .expiringSoon:     .orange
        case .done:             .green
        case .info:             .blue
        case .custom(let c):    c
        }
    }
}

// MARK: - BadgeLabel
// Tinted capsule badge with semantic color.
// Usage: BadgeLabel("Overdue", semantic: .overdue)
//        BadgeLabel("Expiring", semantic: .expiringSoon)

struct BadgeLabel: View {
    let text: String
    let semantic: BadgeSemantic

    init(_ text: String, semantic: BadgeSemantic) {
        self.text = text
        self.semantic = semantic
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, DesignTokens.Spacing.chipPadding)
            .padding(.vertical, DesignTokens.Spacing.chipVerticalPadding)
            .background(semantic.color.opacity(DesignTokens.Opacity.badgeFill))
            .foregroundStyle(semantic.color)
            .clipShape(Capsule())
    }
}

// MARK: - Preview

#Preview("BadgeLabel Semantics") {
    ZStack {
        AmbientBackground(style: .home)

        HStack(spacing: 8) {
            BadgeLabel("Overdue", semantic: .overdue)
            BadgeLabel("Expiring", semantic: .expiringSoon)
            BadgeLabel("Done", semantic: .done)
            BadgeLabel("Info", semantic: .info)
            BadgeLabel("Custom", semantic: .custom(.purple))
        }
        .padding(DesignTokens.Spacing.horizontalMargin)
    }
}
