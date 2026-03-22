---
phase: 01-design-system-foundation
plan: 05
subsystem: ui
tags: [swiftui, design-tokens, spacing, opacity, gap-closure]

# Dependency graph
requires:
  - phase: 01-design-system-foundation
    provides: DesignTokens.Spacing/Opacity/CornerRadius constants, BadgeSemantic, TabAccent
provides:
  - Zero raw numeric padding literals in all view files
  - Zero raw color.opacity() fills in all view files
  - 9 new DesignTokens.Spacing constants covering all spacing values in the app
affects:
  - All future phases (Phase 2+) — design token coverage is now complete

# Tech tracking
tech-stack:
  added: []
  patterns:
    - All numeric padding values map to DesignTokens.Spacing.* named constants
    - All semantic badge/status opacity fills use BadgeSemantic.*.color.opacity(DesignTokens.Opacity.*) or TabAccent.*.color.opacity(DesignTokens.Opacity.*)

key-files:
  created: []
  modified:
    - FamilyLife/Views/Components/DesignTokens.swift
    - FamilyLife/Views/Home/HomeView.swift
    - FamilyLife/Views/Home/FoodKitchenView.swift
    - FamilyLife/Views/Pantry/PantryView.swift
    - FamilyLife/Views/Calendar/CalendarView.swift
    - FamilyLife/Views/Calendar/WeekView.swift
    - FamilyLife/Views/Expenses/ExpensesView.swift
    - FamilyLife/Views/Expenses/ReceiptScannerView.swift
    - FamilyLife/Views/Decisions/DecisionsView.swift
    - FamilyLife/Views/Decisions/DecisionDetailView.swift
    - FamilyLife/Views/Gifts/GiftsView.swift
    - FamilyLife/Views/Rivalries/RivalriesView.swift
    - FamilyLife/Views/Rivalries/RivalryDetailView.swift
    - FamilyLife/Views/Rivalries/LeaderboardCard.swift
    - FamilyLife/Views/Cook/CookView.swift

key-decisions:
  - "tinyLabel (3pt) is used for badge vertical padding matching chipVerticalPadding/chipVerticalTight — covers .padding(.vertical, 3) on status labels"
  - "inset (10pt) covers both .padding(10) on detail card rows and search bar inset — semantically 'small card inset'"
  - "large (40pt) covers all empty-state top padding and loading state offsets — semantically 'spacious offset'"
  - "rowHorizontal (16pt) covers filter pill horizontal padding in PantryView location picker"
  - "chipVerticalTight (2pt) covers the most compact chips (Resolved badge in DecisionsView)"
  - "chipVerticalMed (6pt) covers reaction button vertical padding in DecisionDetailView"
  - "statusColor.opacity(DesignTokens.Opacity.badgeFill) used for StatusBadge in RivalriesView — keeps dynamic computed color while tokenizing opacity"
  - "TabAccent.calendar.color (purple) used for CalendarDayCell selected fill instead of .teal — aligns with tab accent system"
  - "BadgeSemantic.info.color used for ReceiptScannerView category chip — .teal was functionally 'info' context"

patterns-established:
  - "Badge padding pattern: .padding(.horizontal, DesignTokens.Spacing.chipPadding) + .padding(.vertical, DesignTokens.Spacing.tinyLabel)"
  - "Opacity fill pattern: semantic.color.opacity(DesignTokens.Opacity.badgeFill) or TabAccent.X.color.opacity(DesignTokens.Opacity.badgeFill)"
  - "Empty-state top offset: .padding(.top, DesignTokens.Spacing.large)"

requirements-completed: [DS-05]

# Metrics
duration: ~10min
completed: 2026-03-22
---

# Phase 1 Plan 05: DS-05 Gap Closure Summary

**9 new DesignTokens.Spacing constants added; 48 raw padding literals and 10 raw opacity fills replaced across 15 view files — Phase 1 design system lock complete**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-03-22T00:49:00Z
- **Completed:** 2026-03-22T00:59:26Z
- **Tasks:** 2 (executed as one atomic pass)
- **Files modified:** 15

## Accomplishments

- Added 9 new constants to DesignTokens.Spacing covering every spacing value used in the app (tinyLabel, inset, large, sectionTop, rowVertical, bottomBuffer, rowHorizontal, chipVerticalTight, chipVerticalMed)
- Replaced all 48 raw numeric `.padding()` calls across 15 view files with named DesignTokens.Spacing constants
- Replaced all 10 raw `.color.opacity(N)` background/fill calls with BadgeSemantic/TabAccent + DesignTokens.Opacity patterns
- Both grep verification commands return zero violations; build compiles cleanly

## Task Commits

1. **Tasks 1 & 2: Add spacing tokens, replace all raw padding literals and opacity fills** - `d620905` (feat)

**Plan metadata:** (pending final docs commit)

## Files Created/Modified

- `FamilyLife/Views/Components/DesignTokens.swift` - Added 9 new Spacing constants
- `FamilyLife/Views/Home/HomeView.swift` - 3 padding replacements (bottomBuffer, sectionTop, chipPadding+tinyLabel x2)
- `FamilyLife/Views/Home/FoodKitchenView.swift` - 2 padding replacements (sectionTop, large)
- `FamilyLife/Views/Pantry/PantryView.swift` - 5 padding + 1 opacity replacement
- `FamilyLife/Views/Calendar/CalendarView.swift` - 4 padding + 1 opacity replacement
- `FamilyLife/Views/Calendar/WeekView.swift` - 2 padding replacements
- `FamilyLife/Views/Expenses/ExpensesView.swift` - 1 padding replacement
- `FamilyLife/Views/Expenses/ReceiptScannerView.swift` - 3 padding + 2 opacity replacements
- `FamilyLife/Views/Decisions/DecisionsView.swift` - 2 padding + 2 opacity replacements
- `FamilyLife/Views/Decisions/DecisionDetailView.swift` - 3 padding + 2 opacity replacements
- `FamilyLife/Views/Gifts/GiftsView.swift` - 3 padding + 1 opacity replacement
- `FamilyLife/Views/Rivalries/RivalriesView.swift` - 3 padding + 1 opacity replacement
- `FamilyLife/Views/Rivalries/RivalryDetailView.swift` - 3 padding replacements
- `FamilyLife/Views/Rivalries/LeaderboardCard.swift` - 2 padding replacements
- `FamilyLife/Views/Cook/CookView.swift` - 1 padding replacement

## Decisions Made

- `statusColor.opacity(DesignTokens.Opacity.badgeFill)` kept for StatusBadge (RivalriesView) since the color is dynamically computed per-status — only the opacity is tokenized
- `TabAccent.calendar.color` (purple) used for CalendarDayCell selection fill instead of `.teal` — aligns with tab accent system, `.teal` in that context was inconsistent
- `BadgeSemantic.info.color` (blue) used in ReceiptScannerView for the category chip — `.teal` was semantically "info" color in that context
- `TabAccent.decisions.color` used for poll progress bars in both DecisionsView and DecisionDetailView — keeps consistent with tab accent system
- New token `chipVerticalTight = 2` added for compact status chips (Resolved badge) rather than mapping to an arithmetic expression

## Deviations from Plan

None — plan executed exactly as written. All opacity replacements were handled inline during the padding pass since both tasks modified the same lines in several files.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 1 design system is fully locked: zero raw magic numbers remain in any view file
- DS-05 requirement: SATISFIED
- Phase 1 verification score: 8/8 truths verified
- Phase 2 screen work can start from a clean, consistent design token baseline
