import SwiftUI

// MARK: - Design Tokens
// Single source of truth for spacing, corner radius, and opacity constants.
// Use DesignTokens.Spacing.*, DesignTokens.CornerRadius.*, DesignTokens.Opacity.*
// Do NOT use raw magic numbers for layout values in any view file.

enum DesignTokens {
    enum Spacing {
        static let sectionGap: CGFloat = 24      // Between major sections
        static let cardGap: CGFloat = 12          // Between cards within a section
        static let horizontalMargin: CGFloat = 20 // Screen edge padding (premium feel)
        static let cardPadding: CGFloat = 14      // Inside card content padding
        static let chipPadding: CGFloat = 8       // Inside badge/chip horizontal padding
        static let chipVerticalPadding: CGFloat = 4 // Inside badge/chip vertical padding
    }

    enum CornerRadius {
        static let card: CGFloat = 16             // Matches existing .rect(cornerRadius: 16) usage
        static let chip: CGFloat = 999            // Capsule equivalent for .rect
    }

    enum Opacity {
        static let cardTint: Double = 0.1         // Standard card tint
        static let interactiveTint: Double = 0.15 // Tappable card tint (slightly stronger)
        static let primaryButtonTint: Double = 0.6 // Filled primary button tint
        static let badgeFill: Double = 0.15       // Semantic badge background
    }
}

// MARK: - Tab Accent Colors
// One canonical source for per-tab tint colors.
// Used by AmbientBackground, .flCard(tint:), and FLPrimaryButtonStyle.
enum TabAccent {
    case home, calendar, pantry, expenses, trips, cook, rivalries, decisions, gifts

    var color: Color {
        switch self {
        case .home:       .teal
        case .calendar:   .purple
        case .pantry:     .cyan
        case .expenses:   .orange
        case .trips:      .blue
        case .cook:       .orange
        case .rivalries:  .red
        case .decisions:  .indigo
        case .gifts:      .pink
        }
    }
}

// MARK: - Preview

#Preview("Design Tokens Swatch") {
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            Text("Spacing")
                .font(.headline)

            Group {
                swatchRow("sectionGap", width: DesignTokens.Spacing.sectionGap, color: .teal)
                swatchRow("cardGap", width: DesignTokens.Spacing.cardGap, color: .teal)
                swatchRow("horizontalMargin", width: DesignTokens.Spacing.horizontalMargin, color: .teal)
                swatchRow("cardPadding", width: DesignTokens.Spacing.cardPadding, color: .teal)
                swatchRow("chipPadding", width: DesignTokens.Spacing.chipPadding, color: .teal)
                swatchRow("chipVerticalPadding", width: DesignTokens.Spacing.chipVerticalPadding, color: .teal)
            }

            Divider()

            Text("Corner Radius")
                .font(.headline)

            HStack(spacing: 16) {
                RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                    .fill(Color.purple.opacity(0.3))
                    .frame(width: 60, height: 40)
                    .overlay(Text("card").font(.caption2))

                Capsule()
                    .fill(Color.purple.opacity(0.3))
                    .frame(width: 60, height: 24)
                    .overlay(Text("chip").font(.caption2))
            }

            Divider()

            Text("Tab Accents")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 8) {
                ForEach([TabAccent.home, .calendar, .pantry, .expenses, .trips, .cook, .rivalries, .decisions, .gifts], id: \.self) { tab in
                    tab.color
                        .frame(height: 32)
                        .cornerRadius(8)
                        .overlay(
                            Text("\(tab)")
                                .font(.caption2)
                                .foregroundStyle(.white)
                        )
                }
            }
        }
        .padding(DesignTokens.Spacing.horizontalMargin)
    }
}

private func swatchRow(_ label: String, width: CGFloat, color: Color) -> some View {
    HStack {
        Text(label)
            .font(.caption)
            .frame(width: 160, alignment: .leading)
        Rectangle()
            .fill(color.opacity(0.5))
            .frame(width: width, height: 8)
        Text("\(Int(width))pt")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}

extension TabAccent: CustomStringConvertible {
    var description: String {
        switch self {
        case .home:       "home"
        case .calendar:   "calendar"
        case .pantry:     "pantry"
        case .expenses:   "expenses"
        case .trips:      "trips"
        case .cook:       "cook"
        case .rivalries:  "rivalries"
        case .decisions:  "decisions"
        case .gifts:      "gifts"
        }
    }
}

extension TabAccent: Hashable {}
