import SwiftUI

// MARK: - Design Tokens
// Single source of truth for the Kinrows design system (Direction 2.0:
// evergreen / sage / oat / clay / river / sun on warm Liquid-Glass surfaces).
// Brand colours live in KinrowsBrand below; semantic roles resolve onto them.

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

// MARK: - Typography
// Semantic type scale on Dynamic Type styles — never hardcode point sizes in
// views. Each token names a ROLE; the underlying style scales with the user's
// text size setting (test at AX sizes: rows must grow, not truncate).
//
//   flScreenTitle   28  bold        screen headers ("More", "Budget")
//   flTitle         22  bold        card hero titles, stat values
//   flHeadline      17  semibold    card titles, row titles
//   flBody          17  regular     primary content
//   flSubheadline   15  regular     row subtitles, secondary content
//   flFootnote      13  regular     metadata, timestamps
//   flCaption       12  regular     dense annotations
//   flOverline      11  semibold    UPPERCASE section eyebrows (pair with .tracking(0.4))
//   flHero          44  bold rounded  the one big dashboard number per screen
//   flDisplay*      Fraunces (brand serif) — onboarding/auth/empty-state headings only

extension Font {
    static let flScreenTitle: Font = .system(.title, weight: .bold)
    static let flTitle: Font = .system(.title2, weight: .bold)
    static let flHeadline: Font = .system(.headline)
    static let flBody: Font = .system(.body)
    static let flSubheadline: Font = .system(.subheadline)
    static let flFootnote: Font = .system(.footnote)
    static let flCaption: Font = .system(.caption)
    static let flOverline: Font = .system(.caption2, weight: .semibold)
    /// Smallest legible text (timestamps, dense badges) — 11pt regular,
    /// scales. Use flOverline for the semibold/uppercase variant.
    static let flCaption2: Font = .system(.caption2)
    static let flHero: Font = .system(size: 44, weight: .bold, design: .rounded)
    /// Fraunces display roles (brand voice) — onboarding titles, the auth
    /// lockup, large empty-state headings, celebration moments. Scales with
    /// Dynamic Type via relativeTo. Keep nav/forms/lists on the SF roles.
    static let flDisplay: Font = .custom(KinrowsBrand.Typeface.displaySemiBold, size: 28, relativeTo: .title)
    static let flDisplayLarge: Font = .custom(KinrowsBrand.Typeface.displaySemiBold, size: 36, relativeTo: .largeTitle)
    static let flDisplaySmall: Font = .custom(KinrowsBrand.Typeface.displayRegular, size: 22, relativeTo: .title2)
    static let flDisplayItalic: Font = .custom(KinrowsBrand.Typeface.displayItalic, size: 22, relativeTo: .title2)
    /// Secondary big number (detail-screen totals) — rounded numerals are the
    /// friendly-but-adult signature for money/stats; scales with Dynamic Type.
    static let flStat: Font = .system(.largeTitle, design: .rounded, weight: .bold)
}

// MARK: - Kinrows Brand (Direction 2.0 — "Kin that rows together")
// Source of truth: brand/tokens/kinrows-brand-tokens.json. These eight hexes
// are the ONLY brand colours; everything below is a tint/shade of one of
// them so the product never grows a second palette. Never sample colours
// from screenshots — import from here.

enum KinrowsBrand {
    // The eight kit tokens.
    static let evergreen = Color(hex: "#0F3D37")   // primary: nav, high-emphasis text/actions
    static let sage      = Color(hex: "#8FAE8F")   // secondary: supportive states, leaf/crew accents
    static let oat       = Color(hex: "#F7F3E9")   // main warm background
    static let clay      = Color(hex: "#C76F4F")   // warm accent: moments, attention
    static let river     = Color(hex: "#6B8FB0")   // links, travel, water, informational UI
    static let sun       = Color(hex: "#F2C94C")   // celebration / highlight ONLY
    static let ink       = Color(hex: "#1F2A24")   // body text
    static let mist      = Color(hex: "#E8EEE9")   // secondary surfaces + dividers

    // Accessible shades (same hue, darker) for glyphs/text on Oat — Sage and
    // Sun themselves fall below 3:1 on cream, so they stay fills/highlights.
    static let sageDeep  = Color(hex: "#5E8262")
    static let sunDeep   = Color(hex: "#B9891A")
    static let clayDeep  = Color(hex: "#A5563A")
    static let riverDeep = Color(hex: "#4E7091")

    // Oat tints for layered surfaces and ambient gradients.
    static let oatLight  = Color(hex: "#FBF9F3")   // cards sit lighter than the page
    static let oat2      = Color(hex: "#EFEADB")
    static let oat3      = Color(hex: "#E4DECB")

    enum Radius {       // kit radii — product surfaces keep DesignTokens.CornerRadius
        static let sm: CGFloat = 10
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let pill: CGFloat = 999
    }

    enum Motion {       // kit motion durations (seconds)
        static let micro: Double = 0.18
        static let standard: Double = 0.28
        static let celebration: Double = 0.42
        /// cubic-bezier(0.22, 1, 0.36, 1) — a soft, settled ease-out.
        static var standardCurve: Animation { .timingCurve(0.22, 1, 0.36, 1, duration: standard) }
        static var microCurve: Animation { .timingCurve(0.22, 1, 0.36, 1, duration: micro) }
        static var celebrationCurve: Animation { .timingCurve(0.22, 1, 0.36, 1, duration: celebration) }
    }

    enum Typeface {
        /// Fraunces static instances bundled in Resources/Fonts (OFL). Display
        /// roles only — onboarding titles, brand moments, large empty-state
        /// headings. Navigation, forms, lists and controls stay on SF (the
        /// platform-native stand-in for the kit's Inter).
        static let displaySemiBold = "Fraunces72pt-SemiBold"
        static let displayRegular = "Fraunces72pt-Regular"
        static let displayItalic = "Fraunces72pt-Italic"
    }
}

// MARK: - Person Palette
// Deterministic per-person identity color, hashed from the FULL name (a
// single-initial hash collides constantly in a family: "Jesse"/"Jack").
// Use everywhere a person appears — avatar fills, assignee dots, calendar
// tags, leaderboard accents — so each family member reads as one color
// across every feature. Always pair with a non-color cue (initial/name).
// Eight slots: the five brand hues plus three muted companions (taupe, teal,
// plum) chosen to sit quietly beside them — a household needs more distinct
// identities than the kit has hues.

enum PersonPalette {
    static let pairs: [(Color, Color)] = [
        (KinrowsBrand.clay,  KinrowsBrand.clayDeep),       // clay
        (Color(hex: "#D9A72B"), KinrowsBrand.sunDeep),     // sun
        (KinrowsBrand.sage,  KinrowsBrand.sageDeep),       // sage
        (KinrowsBrand.river, KinrowsBrand.riverDeep),      // river
        (Color(hex: "#2E6158"), KinrowsBrand.evergreen),   // evergreen
        (Color(hex: "#9C8878"), Color(hex: "#6B5A4D")),    // taupe
        (Color(hex: "#5F9A8C"), Color(hex: "#3B6E62")),    // teal
        (Color(hex: "#9A7A9C"), Color(hex: "#6A4E6C")),    // plum
    ]

    static func index(for name: String) -> Int {
        let normalized = name.lowercased().trimmingCharacters(in: .whitespaces)
        let hash = normalized.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }
        return abs(hash) % pairs.count
    }

    /// Flat identity color (dots, tags, bars).
    static func color(for name: String) -> Color {
        pairs[index(for: name)].0
    }

    /// Avatar-fill gradient (matches FamilyAvatar).
    static func gradient(for name: String) -> LinearGradient {
        let pair = pairs[index(for: name)]
        return LinearGradient(colors: [pair.0, pair.1], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Warm Palette
// Semantic surface + text roles, now resolved onto the Kinrows tokens. The
// names are historical (cream/peach/sunset date from the terracotta era) and
// stay so 1,000+ call sites don't churn; the VALUES are Oat/Ink/Sun/Clay.

enum WarmPalette {
    static let cream1 = KinrowsBrand.oat            // page background
    static let cream2 = KinrowsBrand.oat2           // deeper oat (ambient gradients)
    static let cream3 = KinrowsBrand.oat3
    static let mist   = KinrowsBrand.mist           // dividers, secondary surfaces
    static let peach  = Color(hex: "#F3DFA0")       // sun @ ~50% over oat (ambient warmth)
    static let sunset = Color(hex: "#DDA089")       // clay @ ~60% over oat
    static let rose   = KinrowsBrand.clay
    static let mauve  = KinrowsBrand.riverDeep

    /// Opaque card surface — no alpha compositing needed. Sits a step lighter than Oat.
    static let cardSurface = KinrowsBrand.oatLight

    static let ink1 = KinrowsBrand.ink
    static let ink2 = Color(hex: "#3E4A43")
    static let ink3 = Color(hex: "#6B756F")
    static let ink4 = Color(hex: "#A9B1AC")

    static let good = KinrowsBrand.sageDeep
    static let warn = KinrowsBrand.sunDeep
    static let bad  = KinrowsBrand.clayDeep
}

// MARK: - Accent Colors
// Case names are persisted (person colour choices) so they keep their
// historical rawValues; each now resolves to a Kinrows hue:
//   terracotta → Clay · saffron → Sun (deep for glyphs) · rose → Evergreen
//   sage → Sage (deep for glyphs) · mauve → River (deep) · ocean → River

enum AccentTheme: String, CaseIterable, Identifiable {
    case terracotta, saffron, rose, sage, mauve, ocean

    var id: String { rawValue }

    /// Glyph/text-safe colour (≥3:1 on Oat).
    var color: Color {
        switch self {
        case .terracotta: KinrowsBrand.clay
        case .saffron:    KinrowsBrand.sunDeep
        case .rose:       KinrowsBrand.evergreen
        case .sage:       KinrowsBrand.sageDeep
        case .mauve:      KinrowsBrand.riverDeep
        case .ocean:      KinrowsBrand.river
        }
    }

    /// Fill/highlight variant (chips, tints, celebration).
    var soft: Color {
        switch self {
        case .terracotta: Color(hex: "#E7BBAA")
        case .saffron:    KinrowsBrand.sun
        case .rose:       KinrowsBrand.sage
        case .sage:       KinrowsBrand.sage
        case .mauve:      Color(hex: "#A9BFD3")
        case .ocean:      Color(hex: "#A9BFD3")
        }
    }
}

// MARK: - Tab Accent Colors

enum TabAccent {
    case home, calendar, pantry, expenses, trips, cook, rivalries, decisions, gifts, care, routines

    var color: Color {
        switch self {
        case .home:       AccentTheme.sage.color
        case .calendar:   KinrowsBrand.evergreen
        case .pantry:     AccentTheme.ocean.color
        case .expenses:   AccentTheme.terracotta.color
        case .trips:      AccentTheme.ocean.color
        case .cook:       AccentTheme.terracotta.color
        case .rivalries:  AccentTheme.rose.color
        case .decisions:  AccentTheme.mauve.color
        case .gifts:      AccentTheme.saffron.color
        case .care:       AccentTheme.sage.color
        case .routines:   KinrowsBrand.riverDeep
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
        case .routines:   "routines"
        }
    }
}

extension TabAccent: Hashable {}
