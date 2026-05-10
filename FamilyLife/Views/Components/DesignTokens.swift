import SwiftUI

// MARK: - Design Tokens
// Single source of truth for the Liquid Glass warm design system.
// Palette inspired by terracotta, cream, and natural tones.

enum DesignTokens {
    enum Spacing {
        static let sectionGap: CGFloat = 24
        static let cardGap: CGFloat = 12
        static let horizontalMargin: CGFloat = 18
        static let cardPadding: CGFloat = 14
        static let chipPadding: CGFloat = 12
        static let chipVerticalPadding: CGFloat = 6
        static let tinyLabel: CGFloat = 3
        static let inset: CGFloat = 10
        static let large: CGFloat = 40
        static let sectionTop: CGFloat = 8
        static let rowVertical: CGFloat = 8
        static let bottomBuffer: CGFloat = 130
        static let rowHorizontal: CGFloat = 16
        static let chipVerticalTight: CGFloat = 2
        static let chipVerticalMed: CGFloat = 6
    }

    enum CornerRadius {
        static let card: CGFloat = 22
        static let cardLarge: CGFloat = 28
        static let chip: CGFloat = 999
        static let tile: CGFloat = 18
        static let small: CGFloat = 12
    }

    enum Opacity {
        static let cardTint: Double = 0.1
        static let interactiveTint: Double = 0.15
        static let primaryButtonTint: Double = 0.6
        static let badgeFill: Double = 0.15
    }
}

// MARK: - Warm Palette

enum WarmPalette {
    static let cream1 = Color(hex: "#fbf3e8")
    static let cream2 = Color(hex: "#f5e6d0")
    static let cream3 = Color(hex: "#efd4b4")
    static let peach = Color(hex: "#f7c89a")
    static let sunset = Color(hex: "#e89a76")
    static let rose = Color(hex: "#d97a7a")
    static let mauve = Color(hex: "#8a6585")

    static let ink1 = Color(hex: "#2a1f1a")
    static let ink2 = Color(hex: "#5a463a")
    static let ink3 = Color(hex: "#8a7468")
    static let ink4 = Color(hex: "#b8a394")

    static let good = Color(hex: "#7ba05b")
    static let warn = Color(hex: "#d99a3c")
    static let bad = Color(hex: "#c25a5a")
}

// MARK: - Accent Colors

enum AccentTheme: String, CaseIterable, Identifiable {
    case terracotta, saffron, rose, sage, mauve, ocean

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .terracotta: Color(hex: "#c46a4a")
        case .saffron:    Color(hex: "#d99a3c")
        case .rose:       Color(hex: "#c25a7a")
        case .sage:       Color(hex: "#7ba05b")
        case .mauve:      Color(hex: "#8a6585")
        case .ocean:      Color(hex: "#5a87a0")
        }
    }

    var soft: Color {
        switch self {
        case .terracotta: Color(hex: "#e89a7a")
        case .saffron:    Color(hex: "#f0c178")
        case .rose:       Color(hex: "#e89ab0")
        case .sage:       Color(hex: "#a8c489")
        case .mauve:      Color(hex: "#b89cb4")
        case .ocean:      Color(hex: "#8eaec4")
        }
    }
}

// MARK: - Tab Accent Colors

enum TabAccent {
    case home, calendar, pantry, expenses, trips, cook, rivalries, decisions, gifts, care

    var color: Color {
        switch self {
        case .home:       AccentTheme.sage.color
        case .calendar:   Color(hex: "#b97090")
        case .pantry:     AccentTheme.ocean.color
        case .expenses:   AccentTheme.terracotta.color
        case .trips:      AccentTheme.ocean.color
        case .cook:       AccentTheme.terracotta.color
        case .rivalries:  AccentTheme.rose.color
        case .decisions:  AccentTheme.mauve.color
        case .gifts:      AccentTheme.saffron.color
        case .care:       AccentTheme.sage.color
        }
    }
}

// MARK: - Family Member

enum FamilyMember: String, CaseIterable, Identifiable {
    case jesse = "J"
    case sophie = "S"
    case rowan = "R"
    case jude = "Ju"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .jesse:  "Jesse"
        case .sophie: "Sophie"
        case .rowan:  "Rowan"
        case .jude:   "Jude"
        }
    }

    var gradient: LinearGradient {
        switch self {
        case .jesse:  LinearGradient(colors: [Color(hex: "#c46a4a"), Color(hex: "#8a3e2a")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .sophie: LinearGradient(colors: [Color(hex: "#d99a3c"), Color(hex: "#a86a1c")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .rowan:  LinearGradient(colors: [Color(hex: "#7ba05b"), Color(hex: "#4a6a35")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .jude:   LinearGradient(colors: [Color(hex: "#6b8aa0"), Color(hex: "#3a5870")], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
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
        case .care:       "care"
        }
    }
}

extension TabAccent: Hashable {}
