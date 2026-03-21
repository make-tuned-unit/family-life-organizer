# Domain Pitfalls: SwiftUI Design System Retrofits

**Domain:** iOS app design polish — brownfield SwiftUI with 8 tabs, mixed visual quality
**Researched:** 2026-03-20
**Confidence:** HIGH (based on direct codebase analysis + established SwiftUI patterns)

---

## Critical Pitfalls

Mistakes that cause rewrites, visual regressions, or derail the milestone entirely.

---

### Pitfall 1: Extracting Components Before Auditing Usage Patterns

**What goes wrong:** You create a `SectionHeader`, `CardContainer`, or `BadgeView` component early in Phase 1, then discover each tab uses it slightly differently — one needs a subtitle, another needs an action button, a third needs an icon. You add parameters until the component has 8 optional properties and a body full of `if let` branches, or you abandon it and inline the pattern anyway.

**Why it happens:** Components are extracted based on visual similarity, not behavioral similarity. Two things that look alike often have different data needs.

**Consequences:** The "shared" component becomes harder to use than inline code. You either over-parameterize it or fork it. Either way you've wasted a phase.

**Prevention:**
- Audit all 8 tabs before writing a single component. Catalog every section header, card, badge, and row variant across the whole app.
- Only extract when you have 3+ concrete usages that are identical or differ only in data (not layout or behavior).
- Use the Components/ folder for pure visual primitives (spacing, color tokens, typography scales) first, not composite widgets.

**Detection warning signs:**
- A component's initializer has more than 4 parameters in its first version.
- You add `var showSubtitle: Bool = false` within a week of creating the component.
- Only 1–2 views actually use the component.

**Phase:** Address in Phase 1 (Design System) — specifically, do the audit before writing components, not after.

---

### Pitfall 2: Hardcoding Colors and Spacing Without a Token Layer

**What goes wrong:** You polish HomeView with `.padding(16)` and `.background(.teal.opacity(0.1))`, then apply `.padding(20)` and `.background(.teal.opacity(0.12))` in CalendarView because 16 "felt tight" in context. By the time you finish all 8 tabs, spacing and color intensities are inconsistent even though everything looks "close enough" individually.

**Why it happens:** Each screen is polished in isolation. Small judgment calls drift over time. SwiftUI's semantic colors (`Color(.systemBackground)`, `.secondary`) mask the problem until you put screens side by side.

**Consequences:** The app looks consistent until you open two tabs in a row. Fixing it requires a grep-and-replace pass across all files, which risks regressions.

**Prevention:**
- Create a `DesignSystem.swift` or `Theme.swift` file in Phase 1 with named spacing constants (`Spacing.card = 16`, `Spacing.section = 24`) and named semantic colors (`AppColor.cardBackground`, `AppColor.subtleAccent`) before touching any screen.
- Use only named tokens in all screen work — never raw values like `.padding(16)`.
- The existing `AmbientBackground` per-tab color system is good, but surface-level card colors and padding must be tokenized separately.

**Detection warning signs:**
- Two card views in different files with `.cornerRadius` values that differ by 2–4pt.
- Color literals like `.teal.opacity(0.1)` appear in more than one file without a shared definition.
- You find yourself eyeballing whether padding "feels right" instead of applying a constant.

**Phase:** Phase 1 (Design System) — non-negotiable prerequisite for all subsequent screen work.

---

### Pitfall 3: Polishing Screens in a Different Order Than Navigation Flow

**What goes wrong:** You polish Home, then skip to Gifts (because it's simpler), then Calendar, then Pantry. The first three screens you polish establish one visual language; by screen 5 your eye has shifted and you apply slightly different shadow depths, corner radii, or font weights. The user launches the app and tabs through screens that feel like different design eras.

**Why it happens:** Natural tendency is to tackle high-visibility or high-complexity screens first, or to parallelize work across tabs. Without a locked design token set, each session introduces micro-drift.

**Consequences:** The polish milestone is "done" but the app still doesn't feel like one product. You need a final consistency pass you didn't budget for.

**Prevention:**
- Lock the design token file (Pitfall 2) and one reference screen to "gold standard" before touching any other screen.
- Work through tabs in user-flow order: Home → Calendar → Pantry → Expenses → Cook → Trips → Rivalries → Decisions → Gifts.
- After every 2–3 screens, open them side by side in Simulator and do a comparison pass before proceeding.

**Detection warning signs:**
- You can't state from memory what the corner radius for a content card is — it means it isn't a constant yet.
- You open two tabs and one looks "warmer" or "denser" without an intentional reason.

**Phase:** Phase 2+ (per-screen polish) — establish the comparison habit from the first screen.

---

### Pitfall 4: Empty States Added as Afterthought, Breaking Layout

**What goes wrong:** You add loading states and empty states at the end of each screen's polish pass. Because the empty state was not accounted for in the layout, it either causes a jarring layout collapse (a ScrollView suddenly with one tiny centered view), or the `ContentUnavailableView` drops in but looks mismatched with the screen's visual style.

**Why it happens:** Loading/empty state handling is not "design" in the traditional sense, so it gets deferred until the happy path looks good. In SwiftUI, empty state layout is part of the view hierarchy from the start.

**Consequences:** The app crashes or looks broken on first launch (no data yet), which is the first impression for any new device. Silent failure + empty screen is indistinguishable from a bug.

**Prevention:**
- Design each screen's empty state and loading state as a first-class layout concern, not a conditional overlay.
- `ContentUnavailableView` is appropriate for Trips and Gifts (already used in TripsView). For data-rich screens like Home and Pantry, use skeleton shimmer placeholders that match the card dimensions.
- Empty states must be included in `#Preview` macros so they are visible during development.

**Detection warning signs:**
- A screen's `#Preview` uses hardcoded mock data that's never empty — the empty state has never been visually verified.
- `isLoading` and `error` properties exist on the ViewModel but nothing checks them in the View body.
- The existing CONCERNS.md documents this: `loadTasks()` and `loadTodayAppointments()` catch errors but don't surface them to users.

**Phase:** Each screen's polish phase — not a separate phase, integrated per-screen.

---

### Pitfall 5: `@Observable` ViewModel Instantiated in Wrong Place, Causing State Loss on Navigation

**What goes wrong:** You move a ViewModel instantiation from `@State private var viewModel = TripsViewModel()` in the View to being passed as a parameter, or you create the ViewModel in a parent view and pass it as `@Bindable`. On iOS 17+/18+ with `@Observable`, doing this incorrectly causes the ViewModel to re-initialize on every navigation push, losing in-flight data, resetting filters, and triggering redundant network requests.

**Why it happens:** During a polish pass, you might refactor view hierarchy to extract subviews, and the ViewModel ownership point shifts unexpectedly.

**Consequences:** Data flickers or disappears on back-navigation. Pagination state resets. Network calls fire twice.

**Prevention:**
- Keep `@State private var viewModel = FeatureViewModel()` at the root feature view. Never create a ViewModel in a subview or computed property.
- When extracting child views during component extraction (Pitfall 1), pass only the data they need as let constants or `Binding<T>`, never the whole ViewModel.
- The current codebase pattern (`@State private var viewModel = HomeViewModel()` in each feature root) is correct — do not change the ownership point during refactoring.

**Detection warning signs:**
- A ViewModel is passed as a parameter into a subview initializer.
- Data disappears when navigating back and re-entering a tab.
- `loadAll()` fires every time the view is tapped, not just on first appear.

**Phase:** Phase 1 (component extraction) — the risk is highest when refactoring view hierarchy.

---

## Moderate Pitfalls

---

### Pitfall 6: AmbientBackground GeometryReader Causing Layout Cycles

**What goes wrong:** The existing `AmbientBackground` uses a `GeometryReader` with relative sizing for gradient orbs. During polish, if additional `GeometryReader` instances are added inside the content layer (e.g., for progress bars, chart sizing), nested GeometryReaders in SwiftUI can cause infinite layout cycles or jitter on scroll.

**Why it happens:** GeometryReader is greedy — it takes all available space and returns measurements. Nesting them or using them inside ScrollViews can produce unstable geometry proposals in SwiftUI.

**Prevention:**
- Use fixed sizes for progress bars and charts rather than GeometryReader-relative sizing.
- If responsive sizing is needed, use `.containerRelativeFrame()` (iOS 17+) instead of GeometryReader.
- AmbientBackground is used as `.background { }` which keeps it in the background layer — do not move it into the foreground content hierarchy.

**Detection warning signs:**
- UI jitters or "pops" on first appear when GeometryReader is present.
- Simulator shows layout warnings in the console.
- An element's size changes slightly between first render and steady state.

**Phase:** Per-screen polish work, especially Expenses (budget progress bars) and Rivalries (leaderboard progress).

---

### Pitfall 7: DateFormatter Instances Created During Polish Pass

**What goes wrong:** The CONCERNS.md documents this existing problem: DateFormatter instances are created fresh in every view render. During polish, new formatted date displays are added to cards, headers, and rows, each creating new DateFormatter instances. Performance degrades noticeably on list-heavy screens (Pantry, Expenses) because DateFormatter initialization is expensive (~100ms).

**Why it happens:** The path of least resistance when adding a formatted date to a card is to write `DateFormatter().string(from: date)` inline. No linter catches it.

**Prevention:**
- In Phase 1, add a `DateFormatters.swift` file with `static let` cached instances for every format pattern used in the app (`shortDate`, `monthYear`, `dayMonth`, `iso8601`).
- Add a code review rule: no `DateFormatter()` calls outside of `DateFormatters.swift`.
- The existing CONCERNS.md identifies the problematic files: `ExpensesViewModel`, `HomeViewModel`, and others.

**Detection warning signs:**
- Scrolling through a long list causes frame drops.
- `DateFormatter()` appears as a call expression (not a static property) in a view or computed property.

**Phase:** Phase 1 (Design System utilities) — fix the existing instances and prevent new ones.

---

### Pitfall 8: Tab Bar Feeling Inconsistent Due to Mixed Navigation Patterns

**What goes wrong:** The current app uses tabs for all 8 features, but HomeView presents other features as sheets (`showingCalendar`, `showingPantry`, etc.), creating two competing navigation paths to the same content. After polish, Calendar in the tab bar looks different from Calendar presented as a sheet from Home (different toolbar, different back button label, potentially different navigation title behavior).

**Why it happens:** The sheet-from-Home approach predates the full tab bar and wasn't cleaned up. During polish, each version is polished independently.

**Consequences:** Tapping Calendar from Home feels different from tapping the Calendar tab. The user is confused about where they are in the app.

**Prevention:**
- Decide in Phase 1: are the Home dashboard shortcuts redundant with the tab bar, or do they serve a different navigation intent (e.g., quick-access modal vs. full navigation)?
- If they're redundant, remove the sheets from HomeView and let the tab bar be the only navigation path.
- If they're intentional, ensure the modal presentation variants have consistent `.navigationTitle`, toolbar items, and dismiss buttons.

**Detection warning signs:**
- HomeView has `@State private var showingCalendar`, `showingPantry`, `showingExpenses`, etc. — this exists today.
- Two screenshots of CalendarView look different depending on how you reached them.

**Phase:** Phase 1 (audit) + Phase 2 (Home dashboard polish).

---

### Pitfall 9: Polish Pass Introduces Silent Regressions in Working Features

**What goes wrong:** During a view refactor for visual polish, you split a large View into sub-Views (e.g., extracting a `TaskRowView`). You pass data correctly but miss a callback or mutation path, so tapping "Complete" on a task silently fails — the ViewModel method is no longer called.

**Why it happens:** SwiftUI's environment and binding propagation is non-obvious. When extracting a subview, if a closure or `Binding` isn't threaded through, the action silently disappears because SwiftUI doesn't warn you.

**Consequences:** A feature that was working before the polish milestone is broken after it, which undermines trust in the whole effort.

**Prevention:**
- After polishing each screen, manually test every action: add, complete, delete, edit, navigate. Not just the visual appearance.
- When extracting components, prefer passing explicit closures over deep binding chains: `onComplete: () -> Void` rather than `@Binding var tasks: [Task]`.
- Keep the mutation path visible: the action should be traceable from the button tap to the ViewModel method in 2 hops maximum.

**Detection warning signs:**
- A tappable element has no `action:` closure or no binding connected to a ViewModel mutation.
- A list row component takes only display data but the original view had action buttons on that row.

**Phase:** Applies to every per-screen polish phase.

---

## Minor Pitfalls

---

### Pitfall 10: SF Symbol Weight Mismatch

**What goes wrong:** Different screens use SF Symbols at different font weights (`.body`, `.title2`, `.headline`) without aligning the symbol rendering weight. Cards look heavier on one screen than another not because of layout, but because the icons carry different visual weight.

**Prevention:** Define a standard symbol size and weight in the design token file. Use `.font(.system(size: 20, weight: .medium))` consistently rather than relying on `Image(systemName:)` defaults.

**Phase:** Phase 1 (design token definition).

---

### Pitfall 11: `#Preview` Using Hardcoded Non-Empty Data Only

**What goes wrong:** Every `#Preview` shows the happy path with 3+ items. You never visually test the loading, empty, and error states during development, so they're broken or misaligned when encountered on device.

**Prevention:** Each feature view should have at minimum 3 preview variants: normal data, empty state, loading state. Add them during the polish pass for each screen.

**Phase:** Per-screen polish phases.

---

### Pitfall 12: Accent Color Overloaded as the Only Color Signal

**What goes wrong:** The app uses `.teal.gradient`, `.orange.gradient`, `.red.gradient` etc. for per-feature identity. During polish, every interactive element (buttons, toggles, progress fills) also picks up the tab's accent color. The result is visually noisy — everything competes for attention.

**Prevention:** Reserve the per-tab accent color for one purpose per screen: either section identity (backgrounds, headers) or action identity (primary buttons). Not both. Secondary actions use `.secondary` label color only.

**Phase:** Per-screen polish phases — enforce this as a design rule when writing tokens.

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| Design system / token creation | Hardcoded values sneak in immediately after — Pitfall 2 | Lock tokens in Phase 1, code review rule enforced from day 1 |
| Component extraction | Over-parameterized early components — Pitfall 1 | Audit all 8 tabs before writing first component |
| Home dashboard polish | Competing navigation paths from HomeView sheets — Pitfall 8 | Decide sheet vs tab navigation intent explicitly |
| Home dashboard polish | DateFormatter instances in new cards — Pitfall 7 | Fix in Phase 1 before adding new date displays |
| Calendar / Pantry / Expenses screens | GeometryReader nesting for responsive layouts — Pitfall 6 | Use `.containerRelativeFrame()` instead |
| Any screen with list rows | State loss from ViewModel refactoring — Pitfall 5 | Keep ViewModel ownership at feature root |
| Any screen with actions | Silent action regression after component extraction — Pitfall 9 | Manual action test after every polish pass |
| Empty/loading states | States designed as afterthought, layout breaks — Pitfall 4 | Include in #Preview from the start |

---

## Sources

- Direct analysis of codebase: `.planning/codebase/CONCERNS.md`, `ARCHITECTURE.md`, `CONVENTIONS.md`, `STRUCTURE.md`
- Direct analysis of: `FamilyLife/Views/Components/AmbientBackground.swift`, `HomeView.swift`, `TripsView.swift`, `GiftsView.swift`
- Confidence level: HIGH — pitfalls derived from concrete evidence in the actual codebase, not generic advice
