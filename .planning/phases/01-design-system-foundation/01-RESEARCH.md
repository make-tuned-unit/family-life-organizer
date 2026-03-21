# Phase 1: Design System Foundation - Research

**Researched:** 2026-03-20
**Domain:** SwiftUI design tokens, ViewModifier patterns, iOS 26 Liquid Glass API, DateFormatter caching, SwiftUI performance
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Per-tab ambient colors (teal, blue, orange, green, purple, etc.) are retained — subtle tint, not strong
- Glass cards pick up a hint of the tab's ambient color — like Apple Health section cards
- Dark mode: let iOS Liquid Glass handle automatically — no custom overrides
- Light and airy feel — subtle frosted glass, minimal shadow (Apple iOS 26 widget style)
- Interactive cards (tappable tasks, appointments) use `.interactive()` glass effect for scale/shimmer on press
- Display-only cards (stat summaries, section containers) use standard glass without interactive feedback
- Corner radius: system continuous corners (~16pt) — match iOS system card radius
- Each item gets its own individual glass card — no grouped container lists
- Cards should feel like they float, not like rigid containers
- Spacious layout — generous padding like Apple Health, calm and scannable
- Section headers: bold title + subtle gray caption underneath (Apple Health style)
- System default font weights for each text style (.title is bold, .body is regular)
- Key numbers prominent and large (.title size) in pills/cards — first thing you see
- Vertical spacing: ~24pt between sections, ~12pt between cards within a section
- Horizontal margins: 20pt edge padding
- Text truncation: single line with ellipsis
- SF Symbols appear alongside text labels in cards and rows for scannability
- **StatPills**: Glass capsules with SF Symbol icon + large number + tiny label
- **BadgeLabels**: Tinted capsule badges with semantic color (red=overdue, orange=expiring, green=done) + text label
- **FilterChips**: Glass toggle chips — unselected: subtle outline, selected: filled glass with tab tint color
- **Primary buttons (CTA)**: Filled glass with tab tint color — clearly the primary action
- **SectionHeaders**: Bold title text + smaller gray subtitle underneath
- AmbientBackground pattern with per-tab gradient orbs is the right foundation — formalize it, don't replace it
- No third-party dependencies — Apple frameworks only

### Claude's Discretion
- Exact accent color strategy (tab-contextual vs. global) — pick what Apple's apps do
- Tab color palette refinement — harmonize if the existing colors clash
- Exact spacing token values (as long as they maintain the ~24/12pt rhythm)
- Secondary and destructive button style specifics
- Loading skeleton design specifics
- Error state visual treatment

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| DS-01 | App has a centralized DesignTokens file defining spacing, corner radius, and color constants used across all views | Swift enum/struct namespace pattern; Swift static properties prevent re-allocation |
| DS-02 | App has a shared `.flCard(tint:)` ViewModifier that replaces all ad-hoc glass effect implementations | ViewModifier protocol pattern; existing `.glassEffect(.regular.tint(color.opacity(0.1)), in: .rect(cornerRadius: 16))` is the call to wrap |
| DS-03 | App has reusable SectionHeader, BadgeLabel, and StatPill components extracted to Views/Components/ | StatPill already exists in HomeView.swift; FilterChip in DecisionsView.swift — extract and standardize |
| DS-04 | App has shared ButtonStyles (primary, secondary, destructive) used consistently across all forms | ButtonStyle protocol; existing codebase mixes `.borderedProminent`, `.bordered`, `.plain`, `.glassProminent` — needs unification |
| DS-05 | All views use design tokens for spacing and colors — no raw magic numbers or `.opacity()` fills | Audit: ~25 raw `.opacity()` fills found across views; spacing tokens replace inline `.padding()` literals |
| PERF-01 | DateFormatters are cached as static properties, not allocated per-row in scroll views | 28+ inline `let f = DateFormatter()` allocations found across 12 files — all in computed properties called per-render |
| PERF-02 | All scrollable lists with >10 items use LazyVStack instead of VStack | PantryView uses `List`/`insetGrouped`; RivalriesView, ExpensesView use `VStack` inside `ScrollView` — need LazyVStack audit |
| PERF-03 | Force-unwrap operators replaced with safe unwrapping (guard/optional chaining) across all files | Force-unwraps found: Gift.swift (2), RivalryDetailView.swift (3 in preview), StartRivalryView.swift (3 memberIDs dict subscripts) |
</phase_requirements>

---

## Summary

Phase 1 establishes the design token system and shared components that all subsequent screen polish depends on. The existing codebase already uses iOS 26's `.glassEffect()` API throughout (not `.ultraThinMaterial`), which is the right foundation. However, every view implements glass cards with ad-hoc inline calls — `glassEffect(.regular.tint(color.opacity(0.1)), in: .rect(cornerRadius: 16))` is copy-pasted ~25 times across the codebase. The primary work is extraction: wrapping the existing pattern into a single `.flCard(tint:)` ViewModifier and centralizing spacing/color constants into `DesignTokens.swift`.

The performance issues are concrete and well-scoped. DateFormatter is allocated inline in 28+ locations across 12 files — many inside computed properties called per-row during scroll. This is a known iOS performance anti-pattern that can cause scroll jank on long lists. The fix is mechanical: move all instances to static properties in a shared `DateFormatters` namespace. LazyVStack adoption is similarly mechanical — identify scrollable VStacks with >10 potential items and migrate them. Force-unwrap removal is limited to 8 clear instances, mostly in SwiftUI `#Preview` blocks (acceptable) and `StartRivalryView` UUID dictionary lookups (needs safe unwrapping).

The component extraction work surfaces a key discovery: `StatPill` and `FilterChip` already exist, but are defined as private structs embedded in `HomeView.swift` and `DecisionsView.swift` respectively. These need to be moved to `Views/Components/` and made public, then all callers updated. `SectionHeader` and `BadgeLabel` are new components to be created.

**Primary recommendation:** Create `DesignTokens.swift` first (blocks everything else), then `.flCard(tint:)` ViewModifier, then extract/create components, then ButtonStyles, then do the mechanical PERF sweep last.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI | iOS 18+ | All UI | Project constraint — already in use |
| GlassEffect API (`.glassEffect()`) | iOS 26+ | Liquid Glass cards | Already adopted throughout codebase; this is Apple's iOS 26 native card surface |
| Swift `enum` namespace | Swift 5.9+ | DesignTokens | Caseless enums prevent instantiation; standard pattern for Swift namespaces |
| `ViewModifier` protocol | iOS 13+ | `.flCard(tint:)` | Composable, reusable, preview-friendly |
| `ButtonStyle` protocol | iOS 13+ | Shared button styles | Composable; replaces inline `.borderedProminent` scatter |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| SF Symbols | iOS 18+ | All icons | Project constraint — no custom icons |
| `DateFormatter` (static) | Foundation | Date string formatting | Used everywhere; must be static to avoid per-render allocation |
| `LazyVStack` | iOS 14+ | Scrollable lists | Any VStack inside ScrollView with >10 dynamic items |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| caseless `enum` namespace | `struct` with static lets | Both work; enum is more idiomatic in Swift for pure namespaces (cannot be accidentally instantiated) |
| `ViewModifier` protocol | direct extension on `View` | Extension works too; ViewModifier is more composable and testable |
| Static `DateFormatter` | `ISO8601DateFormatter` | ISO8601DateFormatter is faster for ISO strings but this app uses mixed format strings; static DateFormatter covers all cases |

**Installation:** No new packages — Apple frameworks only.

---

## Architecture Patterns

### Recommended Project Structure
```
FamilyLife/
├── App/
├── Models/
├── Services/
├── Views/
│   ├── Components/             # Shared design system components
│   │   ├── AmbientBackground.swift   # Already exists
│   │   ├── DesignTokens.swift        # NEW — spacing, radius, colors
│   │   ├── FLCardModifier.swift      # NEW — .flCard(tint:) ViewModifier
│   │   ├── SectionHeader.swift       # NEW — extracted component
│   │   ├── StatPill.swift            # MOVE from HomeView.swift
│   │   ├── BadgeLabel.swift          # NEW — semantic color badges
│   │   ├── FilterChip.swift          # MOVE from DecisionsView.swift
│   │   └── ButtonStyles.swift        # NEW — primary/secondary/destructive
│   ├── Home/
│   ├── Calendar/
│   └── ...
```

### Pattern 1: Caseless Enum Namespace for Design Tokens

**What:** A caseless `enum` (cannot be instantiated) holding all static design constants.
**When to use:** Any constant shared across views — spacing, corner radius, opacity values, semantic colors.

```swift
// DesignTokens.swift
// Source: Swift language spec — caseless enum as namespace
enum DesignTokens {
    enum Spacing {
        static let sectionGap: CGFloat = 24      // Between sections
        static let cardGap: CGFloat = 12          // Between cards within section
        static let horizontalMargin: CGFloat = 20 // Edge padding (wider than default 16)
        static let cardPadding: CGFloat = 12      // Inside card padding
    }

    enum CornerRadius {
        static let card: CGFloat = 16             // Matches .rect(cornerRadius: 16) existing usage
        static let chip: CGFloat = 999            // Capsule-equivalent for .rect
    }

    enum Opacity {
        static let cardTint: Double = 0.1         // .tint(color.opacity(0.1)) — standard card tint
        static let interactiveTint: Double = 0.15 // Slightly stronger for interactive cards
    }
}

// Tab accent colors — one canonical source for per-tab tint
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
```

### Pattern 2: ViewModifier for Shared Glass Card

**What:** A single ViewModifier wrapping the repeated `.glassEffect()` call.
**When to use:** Any content that should appear as a floating glass card.

```swift
// FLCardModifier.swift
// Source: Apple SwiftUI ViewModifier documentation
struct FLCardModifier: ViewModifier {
    var tint: Color = .clear
    var interactive: Bool = false

    func body(content: Content) -> some View {
        let effect: GlassEffectStyle = interactive
            ? .regular.tint(tint.opacity(DesignTokens.Opacity.interactiveTint)).interactive()
            : .regular.tint(tint.opacity(DesignTokens.Opacity.cardTint))
        content
            .glassEffect(effect, in: .rect(cornerRadius: DesignTokens.CornerRadius.card))
    }
}

extension View {
    func flCard(tint: Color = .clear, interactive: Bool = false) -> some View {
        modifier(FLCardModifier(tint: tint, interactive: interactive))
    }
}
```

### Pattern 3: Static DateFormatter Caching

**What:** Move all `DateFormatter` instantiations from computed properties to static properties.
**When to use:** Any file that formats dates — especially in `body`, `var`, or functions called per-row.

```swift
// Before (per-render allocation — WRONG):
private var expiryText: String {
    let f = DateFormatter()          // Allocates every render!
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: date)
}

// After (static — correct):
// Option A: File-level extension on DateFormatter
extension DateFormatter {
    static let isoDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        return f
    }()

    static let shortTime: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()
}

// Usage:
let text = DateFormatter.isoDate.string(from: date)
```

### Pattern 4: Shared ButtonStyle Protocol

**What:** Custom `ButtonStyle` conformances replacing scattered `.borderedProminent`/`.bordered`/`.plain` usages.
**When to use:** Any CTA button, secondary action, or destructive action.

```swift
// ButtonStyles.swift
// Source: Apple SwiftUI ButtonStyle documentation

struct FLPrimaryButtonStyle: ButtonStyle {
    var tint: Color = .teal

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .glassEffect(
                .regular.tint(tint.opacity(0.6)).interactive(),
                in: .rect(cornerRadius: DesignTokens.CornerRadius.card)
            )
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
    }
}

struct FLSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: DesignTokens.CornerRadius.card))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
    }
}

struct FLDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .glassEffect(.regular.tint(.red.opacity(0.6)).interactive(), in: .rect(cornerRadius: DesignTokens.CornerRadius.card))
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
    }
}

extension ButtonStyle where Self == FLPrimaryButtonStyle {
    static var flPrimary: FLPrimaryButtonStyle { .init() }
    static func flPrimary(tint: Color) -> FLPrimaryButtonStyle { .init(tint: tint) }
}

extension ButtonStyle where Self == FLSecondaryButtonStyle {
    static var flSecondary: FLSecondaryButtonStyle { .init() }
}

extension ButtonStyle where Self == FLDestructiveButtonStyle {
    static var flDestructive: FLDestructiveButtonStyle { .init() }
}
```

### Pattern 5: Extracted Shared Components

**What:** SectionHeader, StatPill, BadgeLabel moved/created in `Views/Components/`.

```swift
// SectionHeader.swift — New component
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

// BadgeLabel.swift — New component
struct BadgeLabel: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
```

### Anti-Patterns to Avoid

- **Inline `.glassEffect()` calls after DS-02 is implemented:** Every card surface must go through `.flCard(tint:)`. If you call `.glassEffect()` directly in a view after this phase, DS-05 is violated.
- **Raw magic numbers for spacing/padding:** After DS-01, all spacing values must come from `DesignTokens.Spacing.*`. No `.padding(12)` or `.padding(.horizontal, 16)` inline.
- **Per-instance DateFormatter:** Never `let f = DateFormatter()` inside a `var body`, computed property, or function called during rendering. Always use `DateFormatter.staticProperty`.
- **VStack inside ScrollView for dynamic lists:** Use `LazyVStack` when the item count is data-driven. Static layout VStacks (≤5 fixed children) are fine.
- **Force-unwrap on dictionary subscript:** `memberIDs[name]!` crashes if the key is missing. Use `guard let` or provide a default.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Date formatting | Custom date string logic | Static `DateFormatter` extension | Thread safety, locale/timezone, DST edge cases |
| Lazy list rendering | Manual view recycling | `LazyVStack` / `List` | SwiftUI handles diffing and recycling |
| Glass card surface | Custom `Material` + shadow + border | `.glassEffect()` API | iOS 26 Liquid Glass handles dark mode, blur, refraction automatically |
| Interactive press scale | Manual `.scaleEffect` with `.onTapGesture` | `.glassEffect(.interactive())` | Provides Apple-standard shimmer + scale; free from the system |

**Key insight:** `.glassEffect()` with `.interactive()` already gives press feedback (scale + shimmer). ButtonStyle `isPressed` scale should be subtle (0.97) or omitted when glassEffect handles it — avoid double-animation.

---

## Common Pitfalls

### Pitfall 1: DateFormatter Thread Safety
**What goes wrong:** `DateFormatter` is not thread-safe. If a static formatter is used from multiple threads concurrently, it can produce garbled dates or crash.
**Why it happens:** Static properties are shared across all callers. SwiftUI async rendering (`.task {}`) can call from background contexts.
**How to avoid:** All date formatting in this app happens in synchronous computed properties within the main actor (SwiftUI view rendering is always on the main thread). Static formatters are safe here. If ever called from `async` context, wrap in `await MainActor.run {}` or use `DateFormatter` per-thread.
**Warning signs:** Garbled date strings intermittently — usually only visible under load.

### Pitfall 2: GlassEffect Requires Background Content
**What goes wrong:** `.glassEffect()` produces a white/grey blobs if the view has no colored content behind it to refract.
**Why it happens:** Liquid Glass works by refracting the content beneath it. A white `systemBackground` with no gradient gives it nothing to tint.
**How to avoid:** Always pair glass cards with `AmbientBackground`. All tab views in this app already use `AmbientBackground` — maintain this pattern.
**Warning signs:** Cards look flat/white in simulator; looks fine with the gradient background applied.

### Pitfall 3: LazyVStack Breaks Intrinsic Height in Some Containers
**What goes wrong:** `LazyVStack` inside a `ScrollView` inside another `ScrollView` (nested scroll) loses its size, causing layout collapse.
**Why it happens:** LazyVStack defers measurement; nested scrolling contexts confuse the geometry.
**How to avoid:** Only use `LazyVStack` as a direct child of the top-level `ScrollView`. Never nest a `LazyVStack` inside another lazy container. For this codebase: `PantryView` uses `List` (already lazy) — do not convert to LazyVStack. Focus LazyVStack migration on `ScrollView > VStack(ForEach(...))` patterns.
**Warning signs:** Views collapse to zero height or content disappears.

### Pitfall 4: ViewModifier Applied in Wrong Order Clips Content
**What goes wrong:** Applying `.flCard()` then `.padding()` clips the card shadow at the padding boundary.
**Why it happens:** The modifier order determines render order. Glass effect applied before padding means the glass boundary is tight against the content, and the outer padding clips the visual blur halo.
**How to avoid:** Always apply padding INSIDE the card content (before `.flCard()`), not after. Standard pattern: content with internal `.padding(DesignTokens.Spacing.cardPadding)` then `.flCard(tint: color)`.
**Warning signs:** Card backgrounds look clipped or blur bleeds into adjacent cards.

### Pitfall 5: Static UUID Force-Unwraps in Preview Blocks
**What goes wrong:** `UUID(uuidString: "...")!` crashes if the string is malformed. Found in `RivalryDetailView.swift` and `StartRivalryView.swift`.
**Why it happens:** Preview code often shortcuts safety checks.
**How to avoid:** For PERF-03, the force-unwraps in `#Preview` blocks are lower priority than those in production code paths. Prioritize: `StartRivalryView`'s `memberIDs[name]!` subscripts (run during user action), then preview block unwraps. Replace with `UUID(uuidString: "...")!` → `UUID(uuidString: "...") ?? UUID()` or `guard let`.
**Warning signs:** Crash on app startup if any preview with bad UUID gets called in release.

---

## Code Examples

Verified patterns from Swift documentation and existing codebase analysis:

### Replacing Inline Glass Card (DS-02 Migration)
```swift
// Before (everywhere in codebase):
.padding(12)
.glassEffect(.regular.tint(.blue.opacity(0.1)), in: .rect(cornerRadius: 16))

// After (DS-02):
.padding(DesignTokens.Spacing.cardPadding)
.flCard(tint: .blue)

// Interactive variant (for tappable rows):
.padding(DesignTokens.Spacing.cardPadding)
.flCard(tint: .blue, interactive: true)
```

### Static DateFormatter Pattern (PERF-01)
```swift
// In DateFormatter+Cached.swift or DesignTokens.swift
extension DateFormatter {
    /// yyyy-MM-dd — used for API date strings and pantry expiry
    static let isoDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// HH:mm — used for appointment time display
    static let shortTime: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    /// Short date for display (locale-aware)
    static let shortDisplay: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        return f
    }()
}
```

### LazyVStack Migration (PERF-02)
```swift
// Before:
ScrollView {
    VStack(spacing: DesignTokens.Spacing.cardGap) {
        ForEach(items) { item in
            ItemCard(item: item)
        }
    }
    .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
}

// After:
ScrollView {
    LazyVStack(spacing: DesignTokens.Spacing.cardGap) {
        ForEach(items) { item in
            ItemCard(item: item)
        }
    }
    .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
}
// Note: List is already lazy — do NOT convert PantryView's List to LazyVStack
```

### Safe Unwrapping (PERF-03)
```swift
// Before (StartRivalryView.swift):
initiatorID: memberIDs[currentUser]!,
opponentID: memberIDs[opponentName]!,

// After:
guard let initiatorID = memberIDs[currentUser],
      let opponentID = memberIDs[opponentName] else {
    // show error state
    return
}
// use initiatorID, opponentID
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `.ultraThinMaterial` + `.background()` | `.glassEffect()` modifier | iOS 26 (WWDC 2025) | Liquid Glass handles refraction, dark mode, interactive states automatically |
| `@ObservableObject` + `@StateObject` | `@Observable` macro + `@State` | iOS 17 (adopted in this codebase) | Already adopted — no action needed |
| Static `NavigationView` | `NavigationStack` | iOS 16 (adopted in this codebase) | Already adopted — no action needed |

**Deprecated/outdated:**
- `.ultraThinMaterial` as card background: Replaced by `.glassEffect()` in iOS 26. This codebase has already adopted the new API — do not reintroduce `.material` patterns.
- `GlassEffectContainer`: Used in `HomeView.swift` as a grouping wrapper. This is an internal component (not Apple API) — after `.flCard()` is established, evaluate whether `GlassEffectContainer` should be kept, replaced, or made part of the design system. Its current role (wrapping an HStack of StatPills with shared glass) may differ from individual item cards.

---

## Open Questions

1. **GlassEffectContainer vs individual `.flCard()` cards**
   - What we know: `GlassEffectContainer` is used in `HomeView.swift` as a container that wraps multiple child views (stat pills, feature tiles) under one shared glass surface. The CONTEXT.md says "Each item gets its own individual glass card."
   - What's unclear: Should `GlassEffectContainer` be removed in favor of each child having its own `.flCard()`, or does it serve a different layout role?
   - Recommendation: For Phase 1, keep `GlassEffectContainer` as-is (it's in `HomeView.swift` scope for Phase 3 polish). The `.flCard()` modifier targets individual item cards. Revisit in Phase 3.

2. **`DateFormatter` vs `.formatted()` style API**
   - What we know: Swift's `.formatted()` method (iOS 15+) can replace `DateFormatter` for display strings without needing static instances.
   - What's unclear: Some usages format for API round-trips (e.g., `"yyyy-MM-dd"` for server submission) which `.formatted()` cannot do reliably.
   - Recommendation: Use `DateFormatter` static properties for API format strings (PERF-01). Use `.formatted()` style API for display-only dates where locale awareness matters. Do not mandate one or the other globally.

---

## Sources

### Primary (HIGH confidence)
- Direct codebase analysis — all Swift files in `FamilyLife/` scanned for patterns, anti-patterns, and existing implementations
- Apple SwiftUI documentation (ViewModifier, ButtonStyle, LazyVStack protocols — stable APIs since iOS 14+)
- `.glassEffect()` API — confirmed present in codebase; iOS 26 Liquid Glass API adopted throughout

### Secondary (MEDIUM confidence)
- DateFormatter thread safety: Apple docs state DateFormatter is not thread-safe; main-thread-only SwiftUI rendering mitigates risk in this app
- LazyVStack nesting pitfall: Well-documented SwiftUI limitation; nested scroll views with lazy containers have known sizing issues

### Tertiary (LOW confidence)
- GlassEffectContainer origin: Not a standard Apple API name — likely a custom wrapper created in an earlier development session. Verify its definition before Phase 3 planning.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all components are well-understood Apple APIs already present in the codebase
- Architecture: HIGH — patterns derived from direct codebase analysis, not assumptions
- Pitfalls: HIGH for DateFormatter/LazyVStack (well-documented); MEDIUM for GlassEffect background requirement (observed from API behavior)

**Research date:** 2026-03-20
**Valid until:** 2026-04-20 (stable Apple APIs; iOS 26 GlassEffect API is new but already in-use)
