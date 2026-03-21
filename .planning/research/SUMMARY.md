# Project Research Summary

**Project:** FamilyLife iOS — v1 Design Polish
**Domain:** SwiftUI design system retrofit — brownfield iOS 26 app, 8 tabs
**Researched:** 2026-03-20
**Confidence:** HIGH

## Executive Summary

This milestone is a design polish pass on an already-functional iOS 26 SwiftUI app, not a feature build. The app has solid bones: modern `@Observable` + async/await architecture, Liquid Glass (`.glassEffect()`) already adopted across most views, per-tab `AmbientBackground` gradients, and `ContentUnavailableView` empty states throughout. The core problem is that patterns exist but are not centralized — spacing, corner radii, badge implementations, progress bars, and color-status logic are all duplicated or divergent across the 8 feature tabs. The work is a consolidation and consistency pass, not new feature development.

The recommended approach is a strict inside-out migration: lock design tokens first (colors, spacing, radii), extract shared primitives second (`FLProgressBar`, `FLBadge`, `FLSectionHeader`), then apply `.flCard(tint:)` ViewModifier across all 40+ glass surface call sites in one pass, and finally polish individual screens in user-flow order using only the token/component system. This order prevents visual drift between screens and makes each step independently verifiable via SwiftUI previews.

The key risk is scope creep from premature component extraction. Components extracted before auditing all 8 tabs end up over-parameterized or unused. The second risk is drift: polishing screens in non-sequential order without a locked token set produces an app that looks "close enough" per screen but inconsistent when tabbed through rapidly. Both risks are mitigated by the inside-out migration order and the explicit rule: no component extracted until 3+ identical usages are confirmed across the codebase.

---

## Key Findings

### Recommended Stack

The app is already correctly stacked for iOS 26. No new frameworks or dependencies are needed. The design system is implemented entirely through Swift namespaces, SwiftUI `ViewModifier`/`ButtonStyle` protocols, and iOS 26-native APIs (`GlassEffectContainer`, `.glassEffect(.interactive())`). The one optional upgrade is replacing `AmbientBackground`'s circle-orb blur layers with `MeshGradient` (iOS 18+) for more performant, organic backgrounds — but this is a low-priority enhancement, not a prerequisite.

**Core technologies:**
- `DesignSystem.swift` (static Swift enum namespace): single source of truth for spacing, corner radii, opacity values, feature accent colors — standard Apple-recommended pattern
- `.glassEffect()` + `GlassEffectContainer`: iOS 26 Liquid Glass API for all card surfaces and interactive elements — mandatory for native iOS 26 feel; replaces UIKit-era `.background(.ultraThinMaterial)`
- Custom `ViewModifier` (`.flCard(tint:)`): replaces 40+ inline `.glassEffect(...)` chains with a one-liner — standard SwiftUI pattern, no version constraint
- Custom `ButtonStyle` (`PrimaryButtonStyle`): unifies the current three incompatible CTA styles (`borderedProminent`, `.background(.teal.gradient)`, `.plain`) — uses `.glassEffect(.interactive())` confirmed iOS 26
- `SensoryFeedback` modifier (iOS 17+): adds haptic feedback to all completion and destructive actions — currently absent from the entire codebase
- `LazyVStack` + static `DateFormatter`: performance fixes for scroll-heavy views — `DateFormatter` allocation per render is confirmed in CONCERNS.md as an active issue
- `scrollTransition` (iOS 17+): physics-based card entrance animations in scroll views — replaces manual `onAppear + withAnimation` patterns
- `.redacted(reason: .placeholder)`: skeleton loading states — replaces full-screen `ProgressView()` overlays

### Expected Features

**Must have (table stakes):**
- Haptic feedback on task/grocery complete, destructive actions — every Apple-native app (Reminders, Health) does this; absence is immediately noticeable
- Sheet presentation detents (`.medium` / `.large` with drag indicator) — all add/edit sheets currently open full-screen; feels heavy for simple forms
- Skeleton loading states — bare `ProgressView()` overlay on empty content looks unfinished on first launch
- Consistent glass card surface — `GiftsView` uses `Color(.tertiarySystemFill)`, `TripsView` CTA uses `.background(.teal.gradient)`; these break the visual system established elsewhere
- `withAnimation` on list mutations — items appearing/disappearing without transitions feels broken
- Inline error surfacing — all `catch {}` blocks are silent; users cannot distinguish a bug from an empty state
- Swipe-to-complete on task and grocery rows — expected interaction model for any task list on iOS
- `LazyVStack` + cached `DateFormatter` — confirmed performance issues in CONCERNS.md; table stakes for scrolling smoothness

**Should have (differentiators):**
- Pantry glass card grid view — current `List { .insetGrouped }` is the only tab using UIKit-era list styling; a `LazyVGrid` matches the visual system and improves scannability
- Pantry expiry urgency banner — surfaces the most actionable data (items expiring this week) above the list
- Expense donut chart (`SectorMark` via Charts framework) — more visual and Apple-like than stacked progress bars; Charts is Apple-native (iOS 16+)
- Rivalry live progress animation — progress bars that animate from 0 on appear (`.spring` animation on bar width)
- HomeView navigation model fix — feature grid tiles currently open sheet duplicates of tabs, creating competing navigation paths; should switch to tab bar navigation
- Cook view search field restyled — currently `.roundedBorder` textFieldStyle, inconsistent with glass system

**Defer to later milestones:**
- Trip route polylines (MapKit routing — complex, out of scope for polish pass)
- Drag-to-reorder groceries (nice-to-have interaction, not visual polish)
- Confetti celebration on task completion (delightful but not a polish blocker)
- Notification scheduling UI (`NotificationService` exists but no scheduling UI; explicitly deferred in PROJECT.md)

### Architecture Approach

The design system sits as a horizontal dependency layer beneath all feature views. It is stateless — components receive values and render output with no ViewModel contact. The component hierarchy runs from raw tokens (`DesignTokens.swift`) through style extensions (`FLStyles.swift`) through shared primitives (`FLProgressBar`, `FLBadge`, `FLSectionHeader`, `FLEmptyState`) through promoted compositions (`StatPill`, `FilterChip`, `AppointmentRow`) to feature screens. Each layer imports only from the layer directly below. ViewModels remain owned at feature roots throughout — component extraction must not shift ViewModel ownership.

**Major components:**
1. `DesignTokens.swift` — all raw values: `FLSpacing`, `FLRadius`, `FLColor.tabColor()`, `FLOpacity`; zero logic, leaf dependency
2. `FLStyles.swift` — ViewModifier extensions (`.flCard(tint:)`, `.flBadge(color:)`, `.flRow()`) using tokens; replaces 40+ inline `.glassEffect()` chains
3. `FLProgressBar`, `FLBadge`, `FLSectionHeader`, `FLEmptyState` — primitives extracted from their current inline/duplicate implementations across views
4. Promoted compositions (`StatPill`, `FilterChip`, `AppointmentRow`) — moved from feature files to `Views/Components/`
5. `PrimaryButtonStyle` / `DestructiveButtonStyle` — unifies the three competing CTA button patterns

### Critical Pitfalls

1. **Extracting components before auditing all 8 tabs** — creates over-parameterized components (8+ optional properties) that are harder to use than inline code. Prevention: complete the full codebase audit before writing any component; only extract when 3+ identical usages are confirmed.

2. **Hardcoding colors and spacing without locking tokens first** — screens polished in isolation drift 2–4pt apart on spacing and opacity by the end of the pass. Prevention: `DesignTokens.swift` must exist and be populated before touching any screen; raw literals forbidden in `Views/`.

3. **ViewModel ownership shifted during component extraction** — extracting a subview and passing the whole ViewModel causes re-initialization on navigation, losing state and firing redundant network requests. Prevention: keep `@State private var viewModel` at feature root; pass only data and closures to child views.

4. **Polishing screens in non-sequential order** — micro-drift accumulates across 8 tabs if each is polished independently without a side-by-side comparison cadence. Prevention: work in user-flow order (Home → Calendar → Pantry → Expenses → Cook → Trips → Rivalries → Decisions); compare every 2–3 screens side by side before continuing.

5. **Silent action regressions after component extraction** — closures and bindings not threaded through extracted subviews cause taps to silently do nothing. Prevention: manually test every action (add, complete, delete, edit) after polishing each screen.

---

## Implications for Roadmap

Based on combined research, the natural phase structure follows the inside-out migration order established in ARCHITECTURE.md and confirmed by FEATURES.md priorities. Design system must precede all screen work to prevent the drift pitfalls.

### Phase 1: Design System Foundation
**Rationale:** All screen polish work depends on a locked token system. Building without it guarantees Pitfall 2 (hardcoded drift) and Pitfall 1 (premature extraction). This phase has zero user-visible changes but enables all subsequent phases to be executed without rework.
**Delivers:** `DesignTokens.swift`, `FLStyles.swift`, `FLProgressBar`, `FLBadge`, `FLSectionHeader`, `FLEmptyState`, `DateFormatters.swift`; `.flCard(tint:)` ViewModifier applied across all views; `PrimaryButtonStyle` replacing three CTA variants
**Addresses:** DateFormatter caching (table stakes, FEATURES.md), inconsistent card surfaces (table stakes), `LazyVStack` for list performance
**Avoids:** Pitfall 1 (audit all 8 tabs before writing first component), Pitfall 2 (tokens locked before screen work), Pitfall 7 (DateFormatter fixed at system level)

### Phase 2: Interaction Layer
**Rationale:** Haptics, animations, and sheet detents apply uniformly across all tabs — they are not screen-specific. Applying them after the design system is locked but before per-screen polish ensures they're tested in their final visual context.
**Delivers:** `SensoryFeedback` on all completion/destructive actions; `.presentationDetents([.large])` with drag indicator on all add/edit sheets; `withAnimation` + `.transition()` on all list mutations; `scrollTransition` on cards; skeleton loading via `.redacted(reason: .placeholder)`
**Addresses:** Haptics (table stakes), sheet detents (table stakes), list animations (table stakes), skeleton loading (table stakes)
**Avoids:** Pitfall 4 (loading/empty states designed alongside layout, not as afterthought)

### Phase 3: Per-Screen Polish — Home and Calendar
**Rationale:** Home is the primary screen and sets the gold-standard visual language for all subsequent screens. Calendar is the second-most-used tab. These two screens establish the reference point used for side-by-side comparison during later tabs.
**Delivers:** HomeView navigation model fixed (feature grid navigates to tabs, not sheets); HomeView stat number animation; CalendarView toolbar-integrated view toggle; both screens at full design system compliance
**Addresses:** Competing navigation paths (Pitfall 8), HomeView as gold-standard reference (Pitfall 3)
**Avoids:** Pitfall 5 (ViewModel ownership not changed during HomeView navigation refactor), Pitfall 9 (all tap actions verified after extraction)

### Phase 4: Per-Screen Polish — Pantry and Expenses
**Rationale:** These are the two tabs with the most significant visual debt (Pantry uses UIKit-era `List`; Expenses lacks charts). They also have the most complex interactive layouts (LazyVGrid, donut chart), making them higher-risk. Completing them before the simpler tabs validates the design system under stress.
**Delivers:** Pantry switched from `List { .insetGrouped }` to glass card `LazyVGrid` with expiry urgency banner; Expenses upgraded with `SectorMark` donut chart from Charts framework; both screens with inline error states
**Addresses:** Pantry glass grid (differentiator), expiry banner (differentiator), donut chart (differentiator), inline error surfacing (table stakes)
**Avoids:** Pitfall 6 (GeometryReader nesting — use `.containerRelativeFrame()` for responsive sizing in progress bars and charts)

### Phase 5: Per-Screen Polish — Cook, Trips, Rivalries, Decisions, Gifts
**Rationale:** These screens have less structural debt and will largely be brought into compliance by applying Phase 1 design system components. The main work is search field styling (Cook), rivalry progress animation, and confirming all empty/error states are in place.
**Delivers:** Cook search field restyled; rivalry progress bar animation; all 5 screens at full design system compliance; 3-variant previews (data/empty/loading) for every screen
**Addresses:** Cook inconsistency, rivalry animation (differentiator), comprehensive preview coverage (Pitfall 11)
**Avoids:** Pitfall 12 (accent color not overloaded — one purpose per screen), Pitfall 10 (SF Symbol weight standardized via tokens)

### Phase Ordering Rationale

- Phases 1 and 2 are strict prerequisites for Phases 3–5. Attempting per-screen polish without locked tokens and a unified component system produces drift that requires a complete rework pass.
- Home is first in per-screen work because it is the most complex (navigation model change + most components) and because it becomes the visual reference for all subsequent tabs.
- Pantry and Expenses are Phase 4 rather than last because their structural changes (List to LazyVGrid, bar chart to donut) are the highest-risk diffs and benefit from being done while the token system is fresh.
- The 5 remaining tabs in Phase 5 are grouped because they require only application of Phase 1 components, not structural changes.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 4 (Pantry LazyVGrid):** `LazyVGrid` inside `ScrollView` with glass cards — layout sizing behavior (height inference) needs verification; recommend a quick prototype before committing to the grid approach.
- **Phase 3 (HomeView navigation model):** The decision between removing Home shortcut sheets entirely vs. converting them to tab-switch calls has UX implications worth a brief planning discussion before coding starts.

Phases with standard patterns (skip research-phase):
- **Phase 1:** `DesignTokens.swift`, `ViewModifier`, `ButtonStyle` — all are standard Swift/SwiftUI patterns with WWDC 2025 confirmation and existing usage in codebase.
- **Phase 2:** `SensoryFeedback`, `.presentationDetents`, `withAnimation`, `.redacted` — all iOS 17+ APIs with well-documented usage patterns.
- **Phase 5:** Mechanical application of Phase 1 components — no novel patterns.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All recommended APIs are iOS 17–26 native with WWDC 2025 confirmation; no third-party dependencies; existing codebase already uses the core APIs |
| Features | HIGH | Based on direct codebase audit of all `.swift` files — gaps are observed, not inferred |
| Architecture | HIGH | Inside-out migration pattern is directly derived from CONCERNS.md + CONVENTIONS.md + first-party codebase analysis |
| Pitfalls | HIGH | All 5 critical pitfalls are grounded in concrete evidence from the actual codebase, not generic SwiftUI advice |

**Overall confidence:** HIGH

### Gaps to Address

- **MeshGradient iOS 26 availability:** Confirmed for iOS 18 in training data; iOS 26 availability inferred from backward compatibility. Validate at build time before adopting. If unavailable, retain circle-orb `AmbientBackground` unchanged.
- **HomeView sheet removal vs. tab-switch:** The correct resolution (remove sheets, or convert to `tabSelection` binding calls) depends on whether Jesse and Sophie use the Home shortcuts as a quick-access pattern distinct from the tab bar. Confirm intent before Phase 3.
- **Pantry grid vs. list:** The current `List { .insetGrouped }` is actually performant. The switch to `LazyVGrid` glass cards is a visual consistency fix, not a functional improvement. Confirm this is the desired direction before Phase 4 since it is the largest single-screen structural change.

---

## Sources

### Primary (HIGH confidence)
- WWDC 2025 session 323 "Build a SwiftUI app with the new design" — Liquid Glass APIs, `GlassEffectContainer`, `ToolbarSpacer`, `.interactive()` glass modifier
- WWDC 2025 session 256 "What's new in SwiftUI" — iOS 26 tab bar, `@Animatable` macro, `scrollEdgeEffectStyle`
- Direct codebase analysis: all `FamilyLife/Views/**/*.swift`, `.planning/codebase/CONCERNS.md`, `.planning/codebase/CONVENTIONS.md`, `.planning/codebase/STRUCTURE.md`
- Apple Human Interface Guidelines (iOS 18): sheet detents, `ContentUnavailableView`, `SensoryFeedback`, Liquid Glass guidelines

### Secondary (MEDIUM confidence)
- `MeshGradient` (iOS 18) — training data, no direct iOS 26 docs verification; backward compatibility assumed

### Tertiary (LOW confidence)
- None — all research findings are grounded in first-party Apple documentation or direct code observation

---
*Research completed: 2026-03-20*
*Ready for roadmap: yes*
