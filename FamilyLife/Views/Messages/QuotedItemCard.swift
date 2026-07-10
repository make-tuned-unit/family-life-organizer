import SwiftUI

struct QuotedItem {
    let type: String      // post | task | decision | gift
    let id: Int
    let title: String
}

struct QuotedItemCard: View {
    let type: String
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(accentColor)
                .frame(width: 3)

            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(accentColor)

            Text(title)
                .font(.flFootnote)
                .foregroundStyle(WarmPalette.ink2)
                .lineLimit(2)
        }
        .padding(8)
        .background(WarmPalette.ink1.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    private var icon: String {
        switch type {
        case "decision": "bubble.left.and.bubble.right.fill"
        case "task": "checkmark.circle.fill"
        case "gift": "gift.fill"
        case "post": "text.bubble.fill"
        default: "link"
        }
    }

    private var accentColor: Color {
        switch type {
        case "decision": TabAccent.decisions.color
        case "task": TabAccent.home.color
        case "gift": AccentTheme.rose.color
        case "post": AccentTheme.ocean.color
        default: WarmPalette.ink3
        }
    }
}
