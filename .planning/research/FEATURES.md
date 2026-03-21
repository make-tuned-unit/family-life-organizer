# Feature Landscape

**Domain:** iOS family organizer app — visual polish / v1 native feel
**Researched:** 2026-03-20
**Confidence:** HIGH — based on direct codebase audit + Apple HIG / iOS 18 SwiftUI patterns

---

## Codebase State Assessment

Before cataloguing features, a clear-eyed read of the current code:

**Already done well:**
- `AmbientBackground` — per-tab gradient orbs give glass something to refract; pattern is solid
- `glassEffect` (Liquid Glass) used consistently across cards, chips, pills — iOS 26 API adopted
- `ContentUnavailableView` in every list — Apple-native empty states throughout
- `#Preview` blocks on every view — development loop is fast
- `@Observable` + `async/await` — modern Swift patterns throughout
- Pull-to-refresh on all data views
- Tab badge counts (overdue tasks, active trips)
- Home dashboard — greeting, stat pills, feature grid, live data (steps, active trip)
- RecipeCard — expandable steps, ingredient availability, "add missing to groceries"
- Rivalry cards — dual progress bars, competitor scores, status badges
- Decision cards — poll vote bars, reaction counts, resolved state
- Gift view — upcoming events, countdown urgency, person-organized

**Gaps identified from code audit:**
- No `SensoryFeedback` / haptic feedback anywhere in the codebase
- `HomeView` sheets open features as modals rather than using the TabView navigation — redundant `showingCalendar`, `showingPantry` etc. alongside dedicated tabs
- `GiftsView` upcoming section uses `Color(.tertiarySystemFill)` (plain fill) — not consistent with glass system used everywhere else
- `PantryView` uses `List { .listStyle(.insetGrouped) }` — plain UIKit-era look, inconsistent with glass card system used in other views
- `CookView` search field uses `.roundedBorder` textFieldStyle — not styled to match the app
- DateFormatters allocated inline in `formatDuration`, `ExpiryBadge`, `EventRow` — performance issue at scroll time
- `TripsView` "Start a Trip" button uses `.background(.teal.gradient)` — raw fill instead of glass system
- `RivalriesView` completed section has no visual dimming or "archived" treatment — completed rivalries look identical to active ones except for the badge
- `HomeView` feature grid fires sheets instead of navigating to existing tabs — confusing mental model
- No `withAnimation` / `transition` on list changes (items appearing/disappearing)
- No skeleton loading states — initial load shows a bare `ProgressView()` overlay
- No `presentationDetents` on add/edit sheets — they all full-screen
- `MemberStatsSheet` uses plain `List` — inconsistent with the rest of the app
- No swipe-to-complete on task rows (only swipe-to-delete exists in Pantry)
- `CalendarView` month/week toggle is a `Picker(.segmented)` — works but Apple apps use toolbar-integrated controls
- Error states not surfaced — all catch blocks are silent `catch {}`

---

## Table Stakes

Features users expect. Missing = app feels unfinished or unpolished.

| Feature | Why Expected | Complexity | Current State | Notes |
|---------|--------------|------------|---------------|-------|
| Haptic feedback on actions | Every Apple app (Reminders, Health) uses haptics for completion/toggle/destructive actions | Low | Missing entirely | `SensoryFeedback` modifier, iOS 17+; `.impact(.light)` on task/grocery complete, `.success` on trip arrive |
| Sheet presentation detents | Sheets that full-screen for simple forms feel heavy; Apple uses `.medium` / custom detents | Low | Missing | All add/edit sheets open full-screen; most should be `.medium` or `.large` with drag indicator |
| Skeleton / shimmer loading states | Bare `ProgressView()` overlaid on empty content looks unfinished | Medium | Missing | Replace initial-load overlay with per-card skeleton rows matching the final layout |
| Consistent card surface system | Mixing `glassEffect` cards with plain `tertiarySystemFill` fills in GiftsView / TripsView CTA looks incoherent | Low | Partial | Audit every fill — either glass or a named semantic fill, never raw `.opacity()` fills |
| `withAnimation` on list mutations | Items popping in/out without transition feels broken | Low | Missing | `.transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))` |
| Inline error states | Silent catch blocks mean failures are invisible; users don't know why data didn't load | Low | Missing | `@State var errorMessage: String?` + inline `.alert` or banner per view; never swallow errors |
| Swipe actions on task rows | Reminders, Things 3, Apple's own apps — swipe to complete is expected for any task list | Low | Missing | `swipeActions(edge: .leading)` on `TaskRow` and `GroceryRow` with complete action |
| Consistent navigation model | HomeView feature grid opening sheet duplicates of tabs confuses back-navigation | Medium | Inconsistent | Feature grid tiles should navigate within the tab system, not open sheets |
| Searchable on list views | Pantry and Receipts both have enough data that search-as-you-type is expected | Low | Pantry has custom search bar; Expenses missing | `.searchable()` modifier on Expenses for receipts; Pantry's custom bar is acceptable but `.searchable()` is more native |
| DateFormatter caching | Allocating DateFormatter per-row in scroll views causes visible jank | Low | Not done | Static or cached formatters; already an active requirement in PROJECT.md |
| `LazyVStack` for long lists | `VStack` forces all rows to render eagerly | Low | Not done | Replace `VStack { ForEach }` with `LazyVStack { ForEach }` in Home sections, Rivalries, Decisions |
| Proper empty state actions | `ContentUnavailableView` used well in most places but some (Expenses receipts) have generic text | Low | Mostly done | All empty states should have a contextual CTA button per the Apple template |
| Accessibility labels on icon-only buttons | `Image(systemName:)` buttons without labels fail VoiceOver | Low | Missing | `.accessibilityLabel()` on all toolbar icon buttons |

---

## Differentiators

Features that set this app apart. Not expected, but valued when present.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Confetti / celebration on task completion | Delightful moment for completing tasks or rivalries — Apple does this in Fitness | Medium | `TimelineView` + `Canvas` particle system, or a simple `confettiCannon` approach using standard API; trigger on task complete, rivalry win |
| Pantry glass card grid view | Grid of pantry items (2-col) with expiry color urgency is more scannable than a plain inset-grouped list | Medium | Alternative to current `List` — `LazyVGrid` with `PantryCardCell`; toggle between list/grid in toolbar |
| Rivalry live progress animation | Progress bars that animate from 0 to current value on appear | Low | `withAnimation(.spring(response:0.6))` on bar width; already have the geometry reader structure |
| Animated stat number rollup | Home stat pills counting up from 0 on first load | Low | `AnimatableModifier` or `withAnimation` on the Int value — small but very Apple-like |
| Trip map with route polyline | Current `Map {}` in TripsView shows two markers only; adding a route line (MapKit routing) would look like Apple Maps | High | Out of scope for v1 polish unless routing API is trivial; flag for later |
| Drag-to-reorder groceries | Grocery lists feel more useful when you can reorder by store aisle | Medium | `.onMove` + `EditButton`, or drag gesture; nice-to-have |
| Expense donut chart | Budget overview as a donut chart (like Apple's Wallet) is more visual than stacked progress bars | Medium | `Charts` framework (`SectorMark`); replace or supplement the current `BudgetCategoryRow` list |
| Pantry expiry urgency banner | "3 items expiring this week" banner at top of PantryView pulls the most urgent info forward | Low | Computed from existing `ExpiryBadge` logic; single `HStack` card with urgency count |
| Cook suggestion history | "Recipes you've made" section below the search field for quick access | Low | `@AppStorage` or SwiftData; store last 5 made recipe names |

---

## Anti-Features

Features to explicitly NOT build for this milestone.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Custom transition library (3rd-party) | Project constraint: no third-party deps; also `.matchedTransitionSource` + `.navigationTransition` in iOS 18 covers the need | Use built-in `matchedGeometryEffect` / `navigationTransition` |
| Parallax scrolling backgrounds | Looks impressive in demos, drains battery, fights with scroll performance on large lists | Keep `AmbientBackground` static; it's already the right call |
| Tab bar customization (reorderable tabs) | iOS 18 has this but it adds user configuration overhead; 8-tab app with fixed semantics doesn't benefit | Leave tabs fixed; the current structure is correct |
| Offline-first sync / conflict resolution | PROJECT.md explicitly defers this; adding it now would dominate the milestone | Keep the current simple fetch-on-appear pattern |
| Notification scheduling UI | PROJECT.md defers this; `NotificationService` exists but scheduling UI adds scope | Leave `NotificationService` dormant until a dedicated milestone |
| Animated page transitions between tabs | SwiftUI tab transitions look bad when overdone; Apple's apps don't animate tab switches | Let TabView use its default cross-fade |
| Lottie animations | Third-party dep; also fights with the Liquid Glass aesthetic | SF Symbols animations (`.symbolEffect`) cover all icon animation needs |
| Dark/light mode toggle in-app | System setting handles this; an in-app toggle adds complexity and confuses users | Respect `@Environment(\.colorScheme)` only |
| Per-screen custom color themes | AmbientBackground already provides per-tab color identity; adding more theming creates incoherence | Stay with the current per-style orb system |

---

## Feature Dependencies

```
Haptics → nothing (additive, can layer on any tap action)
Sheet detents → existing sheet infrastructure (trivial change: add .presentationDetents([.medium]))
Skeleton loading → requires knowing the final layout shape (build after card shapes are finalized)
withAnimation list mutations → ViewModel must publish array changes atomically (already does via @Published/Observable)
Expense donut chart → requires Charts framework (no new dep — Charts is Apple-native)
Pantry grid view → requires a new PantryCardCell component
Swipe-to-complete tasks → TaskRow must call ViewModel method (already exists: completeTask)
Inline errors → ViewModel must expose errorMessage: String? (not currently exposed)
Cook history → requires a SwiftData model or @AppStorage (small new model)
Confetti celebration → isolated; no deps
```

---

## MVP Recommendation

For visual polish v1, prioritize in this order:

**Phase 1 — Foundation (everything else depends on this being right):**
1. Extract and harden design system: `GlassCard`, `SectionHeader`, `BadgeLabel` components; audit all raw fills; fix `GiftsView` inconsistency
2. `DateFormatter` caching — performance prerequisite for smooth scrolling
3. `LazyVStack` everywhere lists are currently `VStack { ForEach }`

**Phase 2 — Interaction feel (makes the app feel alive):**
4. Haptic feedback — `SensoryFeedback` on every complete / destructive action (1–2 hours of work, massive feel improvement)
5. `withAnimation` on all list mutations + `.transition()` on insertions/removals
6. Sheet presentation detents — add `.presentationDetents([.large])` with `.presentationDragIndicator(.visible)` to all add/edit sheets; use `.medium` for quick-add flows

**Phase 3 — Polish the weak screens:**
7. Pantry — switch `List` to glass card `LazyVStack` matching other views; add expiry urgency banner
8. Expenses — add `Charts` donut, clean up receipt list
9. Cook — restyle search field to match app; add recipe history
10. Fix HomeView navigation model — feature grid tiles navigate to tabs instead of opening sheets

**Defer for later milestones:**
- Trip route polylines (complex, MapKit routing)
- Drag-to-reorder groceries
- Confetti animation (delightful but not blocking)
- Inline error surfacing on every view (important but doesn't affect visual polish demo)

---

## Phase-Specific Notes

| Phase Topic | Key Features | Watch Out For |
|-------------|-------------|---------------|
| Design system extraction | `GlassCard`, `SectionHeader`, `BadgeLabel` reusable components | Don't over-abstract — 3 components max; keep them thin wrappers |
| Haptics | `SensoryFeedback` on toggle/complete/error | Don't add haptics to navigation — only mutation confirmations |
| List performance | `LazyVStack`, cached formatters | `LazyVStack` inside `ScrollView` requires explicit frame sizing to avoid layout jank |
| Pantry redesign | Glass cards, expiry urgency | The current inset-grouped `List` is actually fast — only switch to LazyVStack if the visual mismatch with other views is being addressed |
| Sheet detents | `.presentationDetents` | `.medium` detent should only be used on forms with 3–5 fields; longer forms need `.large` |
| Charts (Expenses) | `SectorMark` donut | `Charts` is iOS 16+ — already covered by the iOS 18+ deployment target |

---

## Sources

- Direct codebase audit (all `.swift` files in `FamilyLife/Views/`) — HIGH confidence
- Apple HIG for iOS 18: sheet detents, `ContentUnavailableView`, `SensoryFeedback`, Liquid Glass guidelines — HIGH confidence (knowledge cutoff Aug 2025, iOS 18 released Sep 2024)
- SwiftUI `Charts` framework (`SectorMark`) — HIGH confidence (available since iOS 16)
- `SensoryFeedback` modifier — HIGH confidence (available since iOS 17)
- `matchedGeometryEffect` / `navigationTransition` — HIGH confidence (iOS 18 navigation transitions)
