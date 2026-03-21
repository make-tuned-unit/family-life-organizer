# Requirements: FamilyLife iOS — v1 Polish

**Defined:** 2026-03-20
**Core Value:** Every screen feels like a polished, native Apple app — consistent design language, smooth interactions, complete functionality

## v1 Requirements

### Design System

- [x] **DS-01**: App has a centralized DesignTokens file defining spacing, corner radius, and color constants used across all views
- [x] **DS-02**: App has a shared `.flCard(tint:)` ViewModifier that replaces all ad-hoc glass effect implementations
- [ ] **DS-03**: App has reusable SectionHeader, BadgeLabel, and StatPill components extracted to Views/Components/
- [ ] **DS-04**: App has shared ButtonStyles (primary, secondary, destructive) used consistently across all forms
- [ ] **DS-05**: All views use design tokens for spacing and colors — no raw magic numbers or `.opacity()` fills

### Performance

- [ ] **PERF-01**: DateFormatters are cached as static properties, not allocated per-row in scroll views
- [ ] **PERF-02**: All scrollable lists with >10 items use LazyVStack instead of VStack
- [ ] **PERF-03**: Force-unwrap operators replaced with safe unwrapping (guard/optional chaining) across all files

### Interaction Polish

- [ ] **INT-01**: Haptic feedback fires on task/grocery completion, destructive actions, and rivalry progress logging
- [ ] **INT-02**: All list mutations (add, complete, delete) animate with withAnimation and appropriate transitions
- [ ] **INT-03**: All add/edit sheets use presentationDetents (.medium or .large) with visible drag indicator
- [ ] **INT-04**: Swipe-to-complete gesture works on task rows and grocery rows
- [ ] **INT-05**: Accessibility labels applied to all icon-only toolbar buttons

### Loading & Error States

- [ ] **STATE-01**: All data-loading views show skeleton/placeholder states instead of bare ProgressView overlay
- [ ] **STATE-02**: All catch blocks surface errors to users via inline error messages — no silent failures
- [ ] **STATE-03**: All empty states use ContentUnavailableView with contextual CTA button

### Home Dashboard

- [ ] **HOME-01**: Home dashboard has proper visual hierarchy with summary cards, stat pills, and section headers using design system
- [ ] **HOME-02**: Feature grid tiles navigate to existing tabs instead of opening duplicate sheet views
- [ ] **HOME-03**: Stat numbers animate with rollup effect on first load

### Calendar

- [ ] **CAL-01**: Calendar view uses consistent glass card styling for appointment cards
- [ ] **CAL-02**: Calendar month grid has proper visual indicators and smooth month transition
- [ ] **CAL-03**: Add/Edit appointment sheets use presentation detents

### Pantry

- [ ] **PANT-01**: Pantry view uses glass card layout consistent with other views (not UIKit-era inset-grouped List)
- [ ] **PANT-02**: Pantry has expiry urgency banner showing items expiring this week
- [ ] **PANT-03**: Pantry filtering and sorting use consistent FilterChip components from design system

### Expenses

- [ ] **EXP-01**: Budget overview uses Charts framework donut chart (SectorMark) for visual budget breakdown
- [ ] **EXP-02**: Receipt list has searchable modifier for filtering receipts
- [ ] **EXP-03**: Expenses view uses consistent glass card styling for receipt and budget cards

### Cook

- [ ] **COOK-01**: Cook search field styled to match app design system (not default .roundedBorder)
- [ ] **COOK-02**: Recipe cards use consistent glass card styling with proper layout
- [ ] **COOK-03**: Cook view has recipe history section showing recently suggested recipes

### Trips

- [ ] **TRIP-01**: Trips view uses glass card styling — "Start a Trip" CTA uses design system button style, not raw gradient fill
- [ ] **TRIP-02**: Trip cards show status with consistent badge styling from design system
- [ ] **TRIP-03**: Active trip detail view is complete with arrival/cancel actions

### Rivalries

- [ ] **RIV-01**: Rivalry progress bars animate from 0 to current value on appear
- [ ] **RIV-02**: Completed rivalries have visual dimming/archived treatment distinct from active ones
- [ ] **RIV-03**: Leaderboard cards use consistent design system components

### Decisions

- [ ] **DEC-01**: Decision cards use glass card styling with vote progress bars
- [ ] **DEC-02**: Voting UI is complete with reaction support and comment threads
- [ ] **DEC-03**: Resolved decisions have distinct visual treatment

### Gifts

- [ ] **GIFT-01**: Gifts view uses glass card styling consistent with rest of app (not plain tertiarySystemFill)
- [ ] **GIFT-02**: Person-organized gift tracking with purchase status indicators
- [ ] **GIFT-03**: Upcoming events section with countdown urgency styling matches design system

## v2 Requirements

### Advanced Polish

- **ADV-01**: Confetti/celebration animation on task completion and rivalry wins
- **ADV-02**: Drag-to-reorder grocery items by store aisle
- **ADV-03**: Trip route polyline on map view
- **ADV-04**: MeshGradient upgrade for AmbientBackground (performance improvement)
- **ADV-05**: Cook suggestion history persisted to SwiftData

### Infrastructure

- **INFRA-01**: Offline support with local SwiftData cache and sync conflict resolution
- **INFRA-02**: Push notification scheduling UI
- **INFRA-03**: JWT/Keychain authentication upgrade
- **INFRA-04**: iPad-optimized layouts

## Out of Scope

| Feature | Reason |
|---------|--------|
| Backend/API modifications | Backend is solid — iOS-only focus for this milestone |
| Third-party dependencies | Apple frameworks only per project constraint |
| Custom tab bar or tab reordering | iOS handles this; 8 fixed tabs is correct |
| Dark/light mode toggle | System setting handles this — respect @Environment(\.colorScheme) |
| Parallax scrolling backgrounds | Battery drain, fights scroll performance |
| Animated tab transitions | Apple's own apps don't animate tab switches |
| Lottie animations | Third-party dep; SF Symbol effects cover icon animation needs |
| Test coverage | Separate effort after v1 visual polish |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| DS-01 | Phase 1 | Complete |
| DS-02 | Phase 1 | Complete |
| DS-03 | Phase 1 | Pending |
| DS-04 | Phase 1 | Pending |
| DS-05 | Phase 1 | Pending |
| PERF-01 | Phase 1 | Pending |
| PERF-02 | Phase 1 | Pending |
| PERF-03 | Phase 1 | Pending |
| INT-01 | Phase 2 | Pending |
| INT-02 | Phase 2 | Pending |
| INT-03 | Phase 2 | Pending |
| INT-04 | Phase 2 | Pending |
| INT-05 | Phase 2 | Pending |
| STATE-01 | Phase 2 | Pending |
| STATE-02 | Phase 2 | Pending |
| STATE-03 | Phase 2 | Pending |
| HOME-01 | Phase 3 | Pending |
| HOME-02 | Phase 3 | Pending |
| HOME-03 | Phase 3 | Pending |
| CAL-01 | Phase 3 | Pending |
| CAL-02 | Phase 3 | Pending |
| CAL-03 | Phase 3 | Pending |
| PANT-01 | Phase 4 | Pending |
| PANT-02 | Phase 4 | Pending |
| PANT-03 | Phase 4 | Pending |
| EXP-01 | Phase 4 | Pending |
| EXP-02 | Phase 4 | Pending |
| EXP-03 | Phase 4 | Pending |
| COOK-01 | Phase 5 | Pending |
| COOK-02 | Phase 5 | Pending |
| COOK-03 | Phase 5 | Pending |
| TRIP-01 | Phase 5 | Pending |
| TRIP-02 | Phase 5 | Pending |
| TRIP-03 | Phase 5 | Pending |
| RIV-01 | Phase 5 | Pending |
| RIV-02 | Phase 5 | Pending |
| RIV-03 | Phase 5 | Pending |
| DEC-01 | Phase 5 | Pending |
| DEC-02 | Phase 5 | Pending |
| DEC-03 | Phase 5 | Pending |
| GIFT-01 | Phase 5 | Pending |
| GIFT-02 | Phase 5 | Pending |
| GIFT-03 | Phase 5 | Pending |

**Coverage:**
- v1 requirements: 39 total
- Mapped to phases: 39
- Unmapped: 0 ✓

---
*Requirements defined: 2026-03-20*
*Last updated: 2026-03-20 — traceability updated to reflect 5-phase roadmap structure*
