# Technology Stack

**Project:** FamilyLife iOS — v1 Design Polish
**Researched:** 2026-03-20
**Milestone Scope:** Design system establishment and visual consistency across 8 tabs

---

## Context: What Already Exists

The app is brownfield iOS 26 (IPHONEOS_DEPLOYMENT_TARGET = 26.0). Key design infrastructure already in the codebase:

- `AmbientBackground` — per-tab mesh of blurred color orbs over system background
- `.glassEffect(.regular.tint(...), in: .rect(cornerRadius:))` used in HomeView and LeaderboardCard
- `GlassEffectContainer` grouping used in HomeView stats row and filter chips
- `StatPill`, `FeatureTile`, `FilterChip`, `TaskRow`, `AppointmentRow` — ad-hoc components defined inline in view files, not in Components/
- No `DesignSystem.swift` or shared token file exists
- No custom `ButtonStyle`, `ViewModifier`, or theme enum

**The gap:** Patterns exist but aren't centralized. Each screen reinvents spacing, corner radius, typography weights, and color tinting independently.

---

## Recommended Design System Stack

### Foundation Layer: Theme Tokens

**Pattern:** A single `DesignSystem` enum (or struct namespace) with static constants.

**Why:** SwiftUI has no built-in design token system. The standard iOS 26 approach is a static Swift namespace. This lets you change `DesignSystem.cornerRadius.card` in one place and have it propagate everywhere — the same approach Apple uses internally and recommends in WWDC 2025 "Build a SwiftUI app with the new design."

```swift
// FamilyLife/Resources/DesignSystem.swift
enum DesignSystem {
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
    }
    enum CornerRadius {
        static let sm: CGFloat = 10
        static let md: CGFloat = 14
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
    }
    enum Tint {
        static func glass(_ color: Color) -> Color { color.opacity(0.1) }
        static func badge(_ color: Color) -> Color { color.opacity(0.2) }
    }
}
```

**Confidence:** HIGH — this is standard Swift practice verified in Apple's own sample code and WWDC 2025 sessions.

---

### Visual Material Layer: Liquid Glass (iOS 26)

**Pattern:** `.glassEffect()` + `GlassEffectContainer` for cards, pills, and interactive surfaces.

**API (iOS 26, confirmed WWDC 2025):**

```swift
// Card surface
.glassEffect(.regular.tint(color.opacity(0.1)), in: .rect(cornerRadius: 16))

// Interactive variant (adds scale/bounce/shimmer on iOS)
.glassEffect(.regular.tint(color.opacity(0.1)).interactive(), in: .rect(cornerRadius: 16))

// Group related glass elements for consistent sampling
GlassEffectContainer(spacing: 8) {
    HStack { /* glass sibling views */ }
}

// Button styles
.buttonStyle(.glass)              // standard glass
.buttonStyle(.glassProminent)     // prominent/accent variant

// Morphing transition between glass elements
.glassEffectID("id", in: namespace)  // pairs with matchedGeometryEffect
```

**Why:** The app targets iOS 26 exclusively. Liquid Glass IS the iOS 26 design language — it's what Apple uses in all system apps on this OS. Using it consistently is what makes the app feel "native" rather than custom-skinned. `AmbientBackground` already gives backgrounds that glass can refract, which is the intended usage pattern.

**What NOT to use:** `.background(.ultraThinMaterial)` — this was the iOS 15–17 approach (UIKit-era vibrancy). It still works but renders as flat frosted glass without the Liquid Glass refraction that iOS 26 users expect. Use `.glassEffect()` instead.

**Confidence:** HIGH — verified from WWDC 2025 sessions 323 and 256, Apple developer documentation for iOS 26.

---

### Background Layer: AmbientBackground (Already Exists)

**Pattern:** Keep and extend the existing `AmbientBackground` component. It correctly provides the colorful gradient substrate that Liquid Glass refracts.

**What to add:** The `MeshGradient` type (iOS 18+, confirmed in training data) gives more organic, fluid backgrounds than layered circles with blur. For tabs where the ambient feel matters most (Home, Calendar), consider upgrading from circle-orbs to a proper MeshGradient.

```swift
// iOS 18+ MeshGradient — more organic than blurred circles
MeshGradient(
    width: 3, height: 3,
    points: [
        .init(0, 0), .init(0.5, 0), .init(1, 0),
        .init(0, 0.5), .init(0.6, 0.4), .init(1, 0.5),
        .init(0, 1), .init(0.5, 1), .init(1, 1)
    ],
    colors: [.teal.opacity(0.15), .purple.opacity(0.1), .blue.opacity(0.08), ...]
)
```

**Why:** MeshGradient animates smoothly and compiles to Metal shaders rather than multiple blurred CALayer circles, which is more performant on scroll-heavy views. Apple used it prominently in WWDC 2024 sample apps.

**Confidence:** MEDIUM — MeshGradient iOS 18 availability is confirmed in training data. iOS 26 support inferred from backward compatibility. The performance improvement over blurred circles is from Apple's documentation but not directly benchmarked for this app.

---

### Component Pattern: Custom ViewModifiers

**Pattern:** Extract repeated decoration into named `ViewModifier` extensions on `View`.

**Why:** The codebase currently duplicates `.padding(12).glassEffect(...).font(...)` chains in HomeView, LeaderboardCard, DecisionsView, and others. ViewModifiers let you do `.cardStyle(tint: .blue)` instead of 4 chained modifiers repeated 20+ times.

```swift
// FamilyLife/Resources/ViewModifiers.swift
struct CardStyle: ViewModifier {
    let tint: Color
    var cornerRadius: CGFloat = DesignSystem.CornerRadius.lg

    func body(content: Content) -> some View {
        content
            .padding(DesignSystem.Spacing.md)
            .glassEffect(.regular.tint(DesignSystem.Tint.glass(tint)), in: .rect(cornerRadius: cornerRadius))
    }
}

extension View {
    func cardStyle(tint: Color, cornerRadius: CGFloat = DesignSystem.CornerRadius.lg) -> some View {
        modifier(CardStyle(tint: tint, cornerRadius: cornerRadius))
    }
}
```

**Usage sites:** Every existing ad-hoc `.glassEffect()` call gets replaced with `.cardStyle(tint: .blue)`.

**Confidence:** HIGH — standard SwiftUI pattern, no version constraint.

---

### Component Pattern: Custom ButtonStyle

**Pattern:** Define `PrimaryButtonStyle` and `SecondaryButtonStyle` conforming to `ButtonStyle`.

**Why:** The app has buttons styled with `.buttonStyle(.borderedProminent).tint(.teal)` (DecisionsView), hardcoded `.background(.teal.gradient)` (TripsView "Start a Trip"), and `.buttonStyle(.plain)` scattered throughout. This inconsistency is the most visible design gap. A single `PrimaryButtonStyle` gives all primary CTAs the same shape, weight, and Liquid Glass treatment.

```swift
struct PrimaryButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(DesignSystem.Spacing.lg)
            .glassEffect(
                .regular.tint(tint.opacity(0.2)).interactive(),
                in: .rect(cornerRadius: DesignSystem.CornerRadius.lg)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static func primary(tint: Color) -> PrimaryButtonStyle {
        PrimaryButtonStyle(tint: tint)
    }
}
```

**Confidence:** HIGH — standard SwiftUI ButtonStyle protocol, iOS 26 `.interactive()` glass modifier confirmed in WWDC 2025 session 323.

---

### Typography: System Fonts with Semantic Aliases

**Pattern:** Use system fonts exclusively, but define semantic aliases for reuse.

**Why:** San Francisco (the system font) has built-in dynamic type, bold weights, and monospaced digit variants that match Apple's own apps. No custom font is needed. The semantic alias pattern avoids hardcoding `.font(.subheadline.weight(.medium))` in 30 places.

```swift
extension Font {
    static let flCardTitle = Font.subheadline.weight(.semibold)
    static let flCardBody = Font.subheadline
    static let flCaption = Font.caption
    static let flSectionHeader = Font.headline
    static let flStat = Font.title3.bold().monospacedDigit()
}
```

**What NOT to use:** Custom `.ttf` fonts. They break dynamic type, accessibility, and require SPM or bundle management. The constraint "no third-party deps" applies here too.

**Confidence:** HIGH — this is the standard pattern for design systems in Apple-first SwiftUI apps without a custom brand font.

---

### Color System: Semantic Roles + Per-Tab Accent

**Pattern:** Two-tier color system — semantic roles (`.primary`, `.secondary`, `.destructive`) from the system, plus per-feature accent colors as Swift constants.

**Why:** The system provides adaptive `.primary`/`.secondary` for text and backgrounds. The app adds per-tab color identity (purple=Calendar, teal=Pantry, orange=Expenses). Centralizing this in one enum prevents colors from drifting and makes dark mode adaptation automatic since system colors are already adaptive.

```swift
// FamilyLife/Resources/DesignSystem.swift (extend existing)
enum DesignSystem {
    // ... spacing, cornerRadius above

    enum Color {
        // Feature accent colors (used for glass tint and icon foreground)
        static let home = SwiftUI.Color.teal
        static let calendar = SwiftUI.Color.purple
        static let pantry = SwiftUI.Color.cyan
        static let expenses = SwiftUI.Color.orange
        static let cook = SwiftUI.Color.orange
        static let trips = SwiftUI.Color.blue
        static let rivalries = SwiftUI.Color.red
        static let decisions = SwiftUI.Color.indigo
        static let gifts = SwiftUI.Color.pink
    }
}
```

**Note:** The per-tab color mapping already exists in `AmbientBackground.swift` but is duplicated there. Centralizing it removes the duplication.

**Confidence:** HIGH — pattern derived from existing code, no API dependency.

---

### Section Headers: SectionHeader Component

**Pattern:** Extract a shared `SectionHeader` view used by all feature views.

**Why:** The app currently has 8+ variations of a section header (icon + text, just text, text + count badge, text + Add button). Standardizing to one component with optional parameters eliminates the most visible inconsistency across tabs.

```swift
struct SectionHeader: View {
    let title: String
    var icon: String? = nil
    var tint: Color = .primary
    var count: Int? = nil
    var action: (() -> Void)? = nil
    var actionLabel: String = "Add"
}
```

**Confidence:** HIGH — directly observed need from codebase audit.

---

### Scroll Performance: LazyVStack + Cached DateFormatters

**Pattern:** Replace `VStack` with `LazyVStack` for all list-style sections. Cache `DateFormatter` as static properties.

**Why:**
- HomeView renders full task and grocery lists in `VStack` (confirmed in CONCERNS.md — 519 lines, no virtualization). On a household with 40+ active tasks this causes measurable jank.
- `DateFormatter` instances are created fresh in every render call (confirmed in CONCERNS.md). `DateFormatter` is expensive to allocate — one allocation per row per frame is not acceptable.

```swift
// Correct: static, allocated once
private static let dateFormatter: DateFormatter = {
    let df = DateFormatter()
    df.dateStyle = .medium
    return df
}()
```

**Confidence:** HIGH — confirmed from CONCERNS.md performance section and WWDC performance best practices.

---

### Scroll Transitions: scrollTransition (iOS 17+)

**Pattern:** Apply `.scrollTransition` to cards in scrollable lists for entrance/exit animation.

**Why:** iOS 17 introduced `.scrollTransition` as the approved way to add physics-based entrance animations as items scroll into the viewport. It replaces manual `onAppear` + `withAnimation` hacks. Apple uses it in all their iOS 17+ sample apps. It gives the "cards feel alive" effect that distinguishes polished apps.

```swift
ForEach(items) { item in
    ItemCard(item: item)
        .scrollTransition { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0.7)
                .scaleEffect(phase.isIdentity ? 1 : 0.95)
        }
}
```

**Confidence:** HIGH — iOS 17 API, verified in training data. App targets iOS 26 which is a superset.

---

### Empty States: ContentUnavailableView (iOS 17+)

**Pattern:** Use the system `ContentUnavailableView` for all empty states.

**Why:** `ContentUnavailableView` is the iOS 17+ system standard for empty states. The app already uses it in TripsView and DecisionsView (confirmed in code review). It needs to be applied consistently to every list view that currently shows nothing or an off-brand custom empty state.

**Confidence:** HIGH — iOS 17 API, already in use in the app.

---

### Loading States: `redacted(reason: .placeholder)` + Skeleton Content

**Pattern:** Use `.redacted(reason: .placeholder)` on skeleton views while loading, rather than `ProgressView()` overlays.

**Why:** The current pattern shows `ProgressView()` as a full-screen overlay (HomeView: `if viewModel.isLoading && viewModel.summary == nil { ProgressView() }`). This blocks interaction and looks janky on navigation. The Apple-native pattern is skeleton content (placeholder shapes with the same layout as real content) using `.redacted`. This appears in Apple's own apps (App Store, Mail).

```swift
if isLoading {
    CardPlaceholder()
        .redacted(reason: .placeholder)
} else {
    RealCard(data: data)
}
```

**Confidence:** HIGH — iOS 15+ API, standard Apple HIG pattern for loading states.

---

### Tab Bar: Standard TabView (No Changes)

**Pattern:** Keep the existing `TabView` with system tab bar.

**Why:** iOS 26 gives the tab bar a Liquid Glass floating appearance automatically with no code change needed. The WWDC 2025 session explicitly says existing `TabView` code gets the new floating tab bar for free. Do not add custom tab bar styling — it would override the automatic Liquid Glass treatment.

**What NOT to do:** Don't recreate a custom tab bar in SwiftUI. Every WWDC session emphasizes "use system components to get Liquid Glass automatically."

**Confidence:** HIGH — confirmed WWDC 2025 session 323 and 256.

---

### Toolbar: ToolbarSpacer (iOS 26)

**Pattern:** Use `ToolbarSpacer` to group toolbar items where visual separation is needed.

**Why:** iOS 26 introduced `ToolbarSpacer` for flexible/fixed spacing between toolbar items inside the Liquid Glass toolbar. This replaces the pattern of putting `Spacer()` items in `ToolbarItem` groups.

**Confidence:** HIGH — confirmed WWDC 2025 session 323.

---

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Cards/surfaces | `.glassEffect()` | `.background(.ultraThinMaterial)` | iOS 15 pattern, no Liquid Glass refraction on iOS 26 |
| Loading states | `.redacted(reason: .placeholder)` | `ProgressView()` overlay | Blocks interaction, looks dated |
| Button primary CTA | Custom `PrimaryButtonStyle` with `.glassEffect(.interactive())` | `.buttonStyle(.borderedProminent)` | Loses Liquid Glass treatment, doesn't adapt to tab accent color |
| Background | `AmbientBackground` (keep, optionally upgrade to MeshGradient) | `Color(.systemBackground)` | Flat backgrounds don't give Liquid Glass surfaces anything to refract |
| Design tokens | Static Swift enum `DesignSystem` | Environment value tokens | Environment tokens add indirection — overkill for a 2-person app with no theming requirement |
| Custom fonts | Not used | Third-party typeface | Breaks Dynamic Type, accessibility, contradicts "no third-party deps" constraint |
| Tab bar | System `TabView` | Custom tab bar | Overrides automatic iOS 26 Liquid Glass floating tab bar |

---

## File Organization

```
FamilyLife/Resources/
├── Assets.xcassets/         (existing)
├── DesignSystem.swift       NEW — spacing, cornerRadius, tint helpers, feature accent colors
├── ViewModifiers.swift      NEW — cardStyle, badgeStyle, sectionStyle modifiers
├── ButtonStyles.swift       NEW — PrimaryButtonStyle, DestructiveButtonStyle
└── FontExtensions.swift     NEW — semantic Font aliases (flCardTitle, flStat, etc.)

FamilyLife/Views/Components/
├── AmbientBackground.swift  (existing — extend with MeshGradient option)
├── SectionHeader.swift      NEW — standardized section header with icon/count/action
├── StatPill.swift           NEW — extracted from HomeView (currently inline)
├── FeatureTile.swift        NEW — extracted from HomeView feature grid (currently inline)
├── FilterChip.swift         NEW — extracted from DecisionsView/PantryView (repeated pattern)
├── EmptyStateView.swift     NEW — wrapper around ContentUnavailableView for common cases
└── LoadingCard.swift        NEW — redacted placeholder for any card type
```

---

## What NOT to Use

| Technology | Reason |
|------------|--------|
| Third-party UI libraries (Introspect, etc.) | Project constraint + unnecessary on iOS 26 |
| Custom fonts | Breaks Dynamic Type and accessibility |
| UIViewRepresentable for basic UI | SwiftUI has native equivalents for everything needed |
| `withAnimation` + `onAppear` for scroll effects | Use `.scrollTransition` instead |
| `ProgressView()` overlays | Use `.redacted` skeleton content |
| `.background(.ultraThinMaterial)` for cards | Use `.glassEffect()` on iOS 26 |
| Hardcoded `Color(hex:)` | Use system semantic colors + named swatches |

---

## Sources

- WWDC 2025 "Build a SwiftUI app with the new design" (session 323) — Liquid Glass APIs, `ToolbarSpacer`, interactive glass, `GlassEffectContainer` — HIGH confidence
- WWDC 2025 "What's new in SwiftUI" (session 256) — `@Animatable` macro, `scrollEdgeEffectStyle`, iOS 26 APIs — HIGH confidence
- Existing codebase analysis: `AmbientBackground.swift`, `HomeView.swift`, `LeaderboardCard.swift`, `.planning/codebase/CONCERNS.md` — HIGH confidence (direct observation)
- MeshGradient (iOS 18) — training data, no direct docs verification — MEDIUM confidence
- `scrollTransition` (iOS 17) — training data, standard community pattern — HIGH confidence
- `ContentUnavailableView` (iOS 17) — confirmed in codebase (TripsView, DecisionsView already use it) — HIGH confidence
