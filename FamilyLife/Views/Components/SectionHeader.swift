import SwiftUI

// MARK: - SectionHeader
// Apple Health-style section header: bold title + optional smaller gray subtitle.
// Usage: SectionHeader(title: "Tasks", subtitle: "4 remaining", icon: "checkmark.circle")

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                Text(title)
                    .font(.title3.bold())
            }
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Preview

#Preview("SectionHeader Variants") {
    ZStack {
        AmbientBackground(style: .home)

        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sectionGap) {
            // Title only
            SectionHeader(title: "Today's Tasks")

            // Title + subtitle
            SectionHeader(title: "Pantry", subtitle: "3 items expiring soon")

            // Title + icon + subtitle
            SectionHeader(title: "Calendar", subtitle: "2 events this week", icon: "calendar")
        }
        .padding(DesignTokens.Spacing.horizontalMargin)
    }
}
