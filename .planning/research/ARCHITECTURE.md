# Architecture Patterns: SwiftUI Design System

**Domain:** iOS design system — retrofitting onto existing SwiftUI MVVM app
**Researched:** 2026-03-20
**Confidence:** HIGH (direct codebase analysis + Apple HIG + Swift documentation)

---

## Recommended Architecture

### Design System Layer Model

A design system sits as a horizontal layer beneath all views. It does not belong to any feature — it belongs to the app. The layer hierarchy from lowest to highest:

```
Tokens          →  Raw values: colors, spacing, radii, font sizes
    ↓
Styles          →  Semantic aliases: .cardBackground, .primaryLabel, FLFont.title
    ↓
Primitives      →  Generic atoms: FLCard, FLBadge, FLProgressBar, FLSectionHeader
    ↓
Compositions    →  Assembled patterns: StatPill, FilterChip, BudgetCategoryRow
    ↓
Screens         →  Feature views: HomeView, PantryView, ExpensesView, ...
```

Each layer only imports from the layer(s) directly below it. Screens never define their own colors, spacing constants, or progress bars from scratch.

---

## Current State Audit

The existing codebase is further along than a typical brownfield app. Key observations from direct code analysis:

**What is already centralized:**
- `AmbientBackground` — per-tab gradient system in `Views/Components/`. The color-per-tab pattern is established and works well. Confidence: HIGH.
- `GlassEffectContainer` — referenced throughout but not yet found in a standalone file; appears to be a wrapper around the Liquid Glass API (`.glassEffect()`). Confidence: HIGH based on usage.
- `.glassEffect()` calls — the glass surface API is used consistently across all views reviewed. All cards use `.glassEffect(.regular.tint(color.opacity(0.1)), in: .rect(cornerRadius: 16))`. This is the de facto "card style" already.

**What is NOT centralized (current inconsistencies):**
- Spacing is hardcoded per-view: `VStack(spacing: 20)`, `VStack(spacing: 24)`, `padding(.horizontal)`, `padding(12)`, `padding()`, `padding(.vertical)` — no shared constants.
- Corner radius is hardcoded: `cornerRadius: 16` appears in most places but `cornerRadius: 12` appears in TripsView map clip, and `cornerRadius: 6` in `PollOptionRow`.
- Capsule badges are defined independently in `GiftsView` (with `.background(.teal.opacity(0.15))`), `DecisionsView` (with `.background(.green.opacity(0.15))`), and `RivalriesView` (`StatusBadge` struct) — three separate implementations of the same pattern.
- `FilterChip` lives in `DecisionsView.swift` instead of Components. It is a general-purpose component.
- `StatPill` lives in `HomeView.swift`. It is general-purpose enough to be used on other dashboards.
- `BudgetCategoryRow` has its own inline progress bar. `RivalryCard` has its own inline progress bar. These should share a `FLProgressBar` primitive.
- Date formatting is created fresh inline in each view (e.g., `GiftsView.EventRow.formattedDate()` allocates a `DateFormatter` per render).
- Color-for-status logic is duplicated: `StatusBadge.statusColor`, `BudgetCategoryRow.progressColor`, `GiftsView.upcomingSection` urgency coloring — all implement independent "green/yellow/red" semantic mappings.
- The `Color(hex:)` extension is defined inline in `ExpensesView.swift`.

---

## Component Hierarchy

### Layer 1: Tokens (new file — `Views/Components/DesignTokens.swift`)

| Token Namespace | Contents | Notes |
|----------------|----------|-------|
| `FLSpacing` | `xs:4, sm:8, md:12, lg:16, xl:20, xxl:24` | Eliminate all raw spacing literals |
| `FLRadius` | `sm:8, md:12, lg:16, pill:999` | Standardize on 16 for cards, 12 for insets |
| `FLFont` | Semantic aliases wrapping system fonts | `title`, `headline`, `body`, `caption`, `badge` |
| `FLColor` | Semantic colors | `primary`, `secondary`, `tertiary`, `success`, `warning`, `danger`, `tabColor(Tab)` |
| `FLOpacity` | Shared opacity values | `tintWeak:0.10`, `tintMedium:0.20`, `tintStrong:0.40` |

All tokens are `enum` namespaces with `static let` or `static func` members. No structs needed — tokens are never instantiated.

### Layer 2: Style Extensions (new file — `Views/Components/FLStyles.swift`)

Three ViewModifier extensions applied uniformly:

- `FLCardStyle` — wraps `.glassEffect(.regular.tint(color.opacity(FLOpacity.tintWeak)), in: .rect(cornerRadius: FLRadius.lg))`. Replaces 40+ inline `.glassEffect` calls.
- `FLBadgeStyle` — replaces the three independent badge implementations. Takes a `color: Color` parameter.
- `FLRowStyle` — standard `.padding(FLSpacing.md).flCardStyle(color: .clear)` for list rows.

Usage:
```swift
// Before (current)
.glassEffect(.regular.tint(.teal.opacity(0.1)), in: .rect(cornerRadius: 16))

// After
.flCard(tint: .teal)
```

### Layer 3: Primitives (one file per primitive in `Views/Components/`)

| Component | Move from | New location |
|-----------|-----------|--------------|
| `GlassEffectContainer` | Implicit / inline | `Views/Components/GlassEffectContainer.swift` |
| `FLCard` | Inline modifier | `Views/Components/FLCard.swift` |
| `FLProgressBar` | Inline in ExpensesView + RivalriesView | `Views/Components/FLProgressBar.swift` |
| `FLBadge` | Three duplicates across views | `Views/Components/FLBadge.swift` |
| `FLSectionHeader` | Inline `Text + font(.headline)` everywhere | `Views/Components/FLSectionHeader.swift` |
| `FLEmptyState` | Inline `ContentUnavailableView` wrappers | `Views/Components/FLEmptyState.swift` |

`FLProgressBar` interface:
```swift
FLProgressBar(progress: Double, color: Color, height: CGFloat = 8)
```

`FLBadge` interface:
```swift
FLBadge(_ label: String, color: Color, style: FLBadge.Style = .tint)
// style: .tint (background tint) | .glass (glassEffect capsule) | .solid
```

`FLSectionHeader` interface:
```swift
FLSectionHeader(_ title: String, icon: String? = nil, iconColor: Color? = nil, action: (() -> Void)? = nil)
```

### Layer 4: Compositions (promote existing, file-local components to shared)

| Component | Move from | Notes |
|-----------|-----------|-------|
| `StatPill` | `HomeView.swift` | Usable on any summary screen |
| `FilterChip` | `DecisionsView.swift` | Usable in Pantry, Cook, Rivalries |
| `AppointmentRow` | `HomeView.swift` | Usable in CalendarView detail lists |
| `StatusBadge` | `RivalriesView.swift` | Generalizable to any status enum |

These move to `Views/Components/` with minor signature changes to remove feature-specific coupling.

---

## Component Boundaries

| Component | Responsibility | Communicates With |
|-----------|---------------|-------------------|
| `DesignTokens.swift` | Define raw values — zero logic | Nothing (leaf dependency) |
| `FLStyles.swift` | ViewModifier extensions using tokens | Imports DesignTokens |
| `FLProgressBar` | Render a filled/track bar at any width | None |
| `FLBadge` | Render a labeled pill with color semantics | None |
| `FLSectionHeader` | Render headline + optional icon + optional action button | None |
| `FLEmptyState` | Render `ContentUnavailableView` with consistent styling | None |
| `GlassEffectContainer` | Group child views under a glass surface | None |
| `AmbientBackground` | Per-tab gradient layer | Reads tab color mapping |
| `FilterChip` | Toggle chip with glass selection state | None |
| Feature Views | Compose primitives + compositions, no inline styling | Import Components/* |

---

## Data Flow

Design system components are stateless rendering primitives. They receive values, render output. No ViewModel contact.

```
ViewModel (state)
    ↓
Feature View (layout)
    ↓ passes values to
Design System Components (render)
    ↑ no upward communication
```

The only exception is interactive primitives (e.g., `FilterChip`), which accept an `action: () -> Void` closure. State remains in the calling view or ViewModel.

---

## Retrofitting Pattern: How to Migrate Existing Views

The safest migration order for a brownfield design system retrofit is inside-out:

**Step 1 — Tokens only (no UI change)**
Create `DesignTokens.swift`. Find-and-replace spacing and radius literals. Compile-check. No visible change.

**Step 2 — Extract primitives one by one**
Start with the most-duplicated: `FLProgressBar` (appears in 2 views), `FLBadge` (appears in 3 views), `FLSectionHeader` (appears in every view). Each extraction is a small, verifiable diff.

**Step 3 — ViewModifier for card style**
Add `.flCard(tint:)` ViewModifier. Do a single pass replacing all `.glassEffect(...)` calls. Every view touched in one commit — but each replacement is mechanical and testable via preview.

**Step 4 — Promote compositions**
Move `FilterChip`, `StatPill`, `AppointmentRow`, `StatusBadge` to Components. Update import sites.

**Step 5 — Apply per-screen (feature polish)**
With design system in place, each screen's polish work is: replace ad-hoc layout with system components, fix spacing to token values, and add missing states (loading, empty, error).

---

## Patterns to Follow

### Pattern 1: Tab-Accent Color
Each tab has a single semantic accent color (`tabColor`) used for:
- `AmbientBackground` tint
- `.glassEffect` card tint
- Section header icon color
- Progress bar fill color (where contextually appropriate)

This pattern already exists implicitly. Formalizing it in `FLColor.tabColor(Tab)` makes it single-source-of-truth.

```swift
enum FLColor {
    static func tabColor(_ tab: AppTab) -> Color {
        switch tab {
        case .home:      .teal
        case .calendar:  .purple
        case .pantry:    .cyan
        case .expenses:  .orange
        case .trips:     .blue
        case .cook:      .orange
        case .rivalries: .red
        case .decisions: .indigo
        case .gifts:     .pink
        }
    }
}
```

### Pattern 2: Consistent Row Layout
All list rows share the same layout skeleton:
```
[icon/avatar]  [primary label + secondary label]  [trailing value/badge]
```
Applied via `FLRowStyle` padding, radius, and glass surface. Views only supply the content.

### Pattern 3: Loading / Empty / Error Triad
Every list section that loads remote data must implement all three states. Use `FLEmptyState` for empty and error states. Use `.overlay { ProgressView() }` (already established) for loading. This pattern is already present in Expenses and Pantry but missing in Trips and Gifts.

### Pattern 4: GlassEffectContainer as Layout Primitive
`GlassEffectContainer` (already used in HomeView) groups multiple child views under a shared glass surface. Use it for stat rows, filter rows, and grid containers — where children belong together visually but are not individually tappable.

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: Inline Color-Status Logic
**What:** Writing `if progress > 0.75 { .yellow } else { .green }` inline in views
**Why bad:** The threshold values (0.75, 1.0) diverge across views; colors lose consistency
**Instead:** Define `FLColor.spendingStatus(_ progress: Double) -> Color` in tokens

### Anti-Pattern 2: Styling in Models
**What:** Putting view-layer concerns (icon names, display colors) on SwiftData `@Model` types
**Why bad:** Models become coupled to presentation; breaks when designs change
**Instead:** Define icon/color mappings as extensions on the model type in a separate `ModelExtensions+UI.swift` file, or in the component that renders it

### Anti-Pattern 3: Anonymous Inline Structures
**What:** Defining `private struct UpcomingItem` inside a View (see `GiftsView`)
**Why bad:** Cannot be reused; makes view files harder to read
**Instead:** Move display-only data structures to the component that renders them, or use a tuple if simple enough

### Anti-Pattern 4: Premature Tokenization
**What:** Extracting every single magic number into a token before using it in more than one place
**Why bad:** Creates token namespace sprawl; adds overhead without benefit
**Instead:** Only extract a value to a token when it appears in 3+ places or carries semantic meaning (e.g., a corner radius that should always match card radius)

---

## Build Order for the Design System Phase

This order minimizes risk of merge conflicts and provides visible progress at each step:

| Order | Task | Risk | Proof of Done |
|-------|------|------|---------------|
| 1 | Create `DesignTokens.swift` with `FLSpacing`, `FLRadius`, `FLColor.tabColor` | Low | Compiles, tokens used in 0 places yet |
| 2 | Create `FLProgressBar` and replace both inline progress bars | Low | 2 views simplified |
| 3 | Create `FLBadge` and replace 3 badge implementations | Low | `StatusBadge`, capsule in GiftsView, capsule in HomeView use `FLBadge` |
| 4 | Create `FLSectionHeader` and add to all feature views | Low | Every section header uniform |
| 5 | Add `.flCard(tint:)` ViewModifier, replace all `.glassEffect(...)` calls | Medium | Single diff touching every view; verify in previews |
| 6 | Move `FilterChip`, `StatPill`, `AppointmentRow` to Components | Low | Feature files shrink |
| 7 | Create `FLEmptyState` and replace `ContentUnavailableView` wrappers | Low | Consistent empty states everywhere |
| 8 | Apply tokens for spacing/radius to all views | Medium | No raw `16`, `12`, `20`, `24` literals in Views/ |

---

## Scalability Considerations

| Concern | Now (2 screens polished) | Full rollout (10 screens) | If app grows significantly |
|---------|--------------------------|---------------------------|---------------------------|
| Token changes | Edit DesignTokens.swift, 0 view changes | Same — that's the point | Add semantic color layer (light/dark themes) |
| New component | Add to Components/, use in one feature | Available to all features immediately | Namespace by category (FLFeedback/, FLNavigation/) |
| New tab | Add case to `AppTab`, add `tabColor` mapping | AmbientBackground and cards automatically adopt | No structural changes needed |
| Dark mode | System `.primary`, `.secondary`, `Color(.systemBackground)` already adaptive | Already correct | Add explicit dark-mode overrides to tokens if needed |

---

## Sources

- Direct analysis of FamilyLife codebase (HIGH confidence — first-party)
- Apple Human Interface Guidelines — iOS design system principles (HIGH confidence)
- SwiftUI `.glassEffect` API usage patterns observed in codebase (HIGH confidence)
- `AmbientBackground.swift` — establishes tab-per-color semantic already (HIGH confidence)
- `.planning/codebase/CONCERNS.md` — performance bottleneck and tech debt inventory (HIGH confidence)
- `.planning/codebase/CONVENTIONS.md` — naming and structural patterns (HIGH confidence)
