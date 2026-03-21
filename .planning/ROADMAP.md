# Roadmap: FamilyLife iOS — v1 Polish

## Overview

This milestone is a design polish pass on a functional 8-tab iOS app. The work follows an inside-out migration: lock the design system first, apply interaction polish second, then bring each screen up to a consistent Apple-native standard. Every phase delivers a coherent, verifiable improvement — nothing is half-done at a phase boundary.

## Phases

- [ ] **Phase 1: Design System Foundation** - Establish shared tokens, styles, and components that all screen work depends on
- [ ] **Phase 2: Interaction Layer** - Apply haptics, animations, sheet detents, skeleton loading, and error surfacing across all tabs
- [ ] **Phase 3: Home and Calendar Polish** - Bring the two primary screens to full design system compliance and fix navigation model
- [ ] **Phase 4: Pantry and Expenses Polish** - Address the two tabs with the most structural visual debt
- [ ] **Phase 5: Cook, Trips, Rivalries, Decisions, Gifts Polish** - Bring remaining five tabs to full design system compliance

## Phase Details

### Phase 1: Design System Foundation
**Goal**: A locked design token system and shared component library exists so all subsequent screen work uses consistent values without duplication
**Depends on**: Nothing (first phase)
**Requirements**: DS-01, DS-02, DS-03, DS-04, DS-05, PERF-01, PERF-02, PERF-03
**Success Criteria** (what must be TRUE):
  1. A single `DesignTokens.swift` file exists with all spacing, corner radius, and color constants — no raw magic numbers appear in any view file
  2. All glass card surfaces across the app use the `.flCard(tint:)` ViewModifier — no inline `.glassEffect()` chains remain in view files
  3. `SectionHeader`, `BadgeLabel`, and `StatPill` components exist in `Views/Components/` and are used by at least one view each
  4. All add/edit forms use a shared button style from `ButtonStyles.swift` — three distinct CTA variants no longer coexist
  5. All scrollable lists use `LazyVStack` and `DateFormatter` instances are cached as static properties, not allocated per row
**Plans**: 4 plans

Plans:
- [ ] 01-01-PLAN.md — Create DesignTokens.swift and FLCardModifier.swift (foundational contracts)
- [ ] 01-02-PLAN.md — Create shared components: SectionHeader, BadgeLabel, StatPill, FilterChip, ButtonStyles
- [ ] 01-03-PLAN.md — Performance fixes: static DateFormatters, LazyVStack migration, force-unwrap removal
- [ ] 01-04-PLAN.md — Migrate all view files to use design system tokens and components

### Phase 2: Interaction Layer
**Goal**: The app feels alive — taps confirm with haptics, lists animate, sheets feel native, loading states are informative, and errors are always surfaced to the user
**Depends on**: Phase 1
**Requirements**: INT-01, INT-02, INT-03, INT-04, INT-05, STATE-01, STATE-02, STATE-03
**Success Criteria** (what must be TRUE):
  1. Completing a task or grocery item produces a haptic pulse; destructive actions (delete) produce a warning haptic
  2. Adding or removing any list item animates smoothly — items do not appear or disappear instantaneously
  3. Every add/edit sheet opens with a visible drag indicator at `.medium` or `.large` detent — no full-screen sheets for simple forms
  4. Swiping left on a task row or grocery row reveals a complete action without navigating away
  5. All loading states show skeleton placeholder cards instead of a bare spinner, and all network errors display an inline message with a retry option
**Plans**: TBD

### Phase 3: Home and Calendar Polish
**Goal**: The two most-used screens are at full design system compliance and establish the visual reference standard for all remaining screens
**Depends on**: Phase 2
**Requirements**: HOME-01, HOME-02, HOME-03, CAL-01, CAL-02, CAL-03
**Success Criteria** (what must be TRUE):
  1. The Home dashboard shows summary cards and stat pills using design system components — visual hierarchy is immediately clear on first glance
  2. Tapping a feature shortcut on the Home dashboard navigates to the corresponding tab — no competing sheet duplicates open
  3. Stat numbers on the Home dashboard count up from zero on first load with a rollup animation
  4. Appointment cards in the Calendar view use consistent glass card styling matching the rest of the app
  5. The calendar month grid transitions smoothly between months and appointment sheets use presentation detents
**Plans**: TBD

### Phase 4: Pantry and Expenses Polish
**Goal**: The two tabs with the most structural visual debt are brought to design system compliance — Pantry migrated off UIKit-era list styling, Expenses upgraded with a visual budget chart
**Depends on**: Phase 3
**Requirements**: PANT-01, PANT-02, PANT-03, EXP-01, EXP-02, EXP-03
**Success Criteria** (what must be TRUE):
  1. The Pantry view displays items as glass cards in a grid layout — no UIKit-era inset-grouped list rows remain
  2. A banner at the top of Pantry highlights items expiring within 7 days with urgency styling
  3. Pantry filtering and sorting use `FilterChip` components from the design system — controls look consistent with the rest of the app
  4. The Expenses budget overview shows a donut chart (SectorMark) breaking down spending by category
  5. Receipt list has a search field for filtering, and all receipt and budget cards use glass card styling
**Plans**: TBD

### Phase 5: Cook, Trips, Rivalries, Decisions, Gifts Polish
**Goal**: All remaining five tabs reach full design system compliance — each screen uses shared components, has correct loading/empty/error states, and ships with a three-variant SwiftUI preview
**Depends on**: Phase 4
**Requirements**: COOK-01, COOK-02, COOK-03, TRIP-01, TRIP-02, TRIP-03, RIV-01, RIV-02, RIV-03, DEC-01, DEC-02, DEC-03, GIFT-01, GIFT-02, GIFT-03
**Success Criteria** (what must be TRUE):
  1. Cook search field uses the app design system styling (not `.roundedBorder`) and recipe cards use glass card layout with a visible recipe history section
  2. Trip cards show status badges from the design system, the "Start a Trip" CTA uses the primary button style, and the active trip detail view has working arrival and cancel actions
  3. Rivalry progress bars animate from 0 to current value on screen appear, completed rivalries have distinct dimmed visual treatment, and leaderboard cards use design system components
  4. Decision cards show vote progress bars with glass card styling, voting and comment UI is complete, and resolved decisions have distinct visual treatment
  5. Gift cards use glass card styling, gifts are organized by person with purchase status indicators, and the upcoming events section shows countdown urgency using design system styling
**Plans**: TBD

## Progress

**Execution Order:** 1 → 2 → 3 → 4 → 5

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Design System Foundation | 0/4 | Planned | - |
| 2. Interaction Layer | 0/? | Not started | - |
| 3. Home and Calendar Polish | 0/? | Not started | - |
| 4. Pantry and Expenses Polish | 0/? | Not started | - |
| 5. Cook, Trips, Rivalries, Decisions, Gifts Polish | 0/? | Not started | - |

---
*Roadmap created: 2026-03-20*
*Phase 1 planned: 2026-03-20 — 4 plans, 3 waves*
