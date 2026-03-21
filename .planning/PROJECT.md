# FamilyLife iOS — v1 Polish

## What This Is

A native iOS companion app for the Family Life Organizer web app, built for Jesse and Sophie to manage their household from their iPhones. The app covers calendar, pantry, expenses, cooking, tasks, groceries, trips, rivalries, decisions, and gifts — all synced with an Express/SQLite backend.

## Core Value

Every screen feels like a polished, native Apple app — consistent design language, smooth interactions, and complete functionality so Jesse and Sophie actually want to use it daily.

## Requirements

### Validated

- ✓ MVVM architecture with @Observable ViewModels — existing
- ✓ APIService wrapping 30+ Express REST endpoints — existing
- ✓ 8-tab navigation (Home, Calendar, Pantry, Expenses, Cook, Trips, Rivalries, Decisions, Gifts) — existing
- ✓ Session-based authentication with login flow — existing
- ✓ Calendar with monthly grid and appointment management — existing
- ✓ Pantry inventory browser with expiry tracking — existing
- ✓ Expenses with budget tracking and receipt scanner — existing
- ✓ Home dashboard with summary stats and quick actions — existing
- ✓ Trips, Rivalries, Decisions, Gifts feature scaffolds — existing

### Active

- [ ] Establish a design system (colors, typography, spacing, card styles) that matches Apple's native aesthetic
- [ ] Apply consistent design across all screens — no screen should feel like a different app
- [ ] Polish Home dashboard with proper summary cards and visual hierarchy
- [ ] Refine Calendar view with native-feeling month grid and appointment detail
- [ ] Complete Pantry view with proper filtering, sorting, and expiry indicators
- [ ] Polish Expenses view with budget visualization and receipt list
- [ ] Finish Cook view with proper recipe card layout and ingredient display
- [ ] Complete Trips view with status tracking and trip detail
- [ ] Polish Rivalries with leaderboard cards and progress visualization
- [ ] Complete Decisions view with voting UI and comment threads
- [ ] Finish Gifts view with person-organized gift tracking
- [ ] Extract reusable components (cards, badges, progress indicators, section headers)
- [ ] Fix force-unwrap crashes and silent error swallowing
- [ ] Add proper loading states and empty states for all views
- [ ] Cache DateFormatters and optimize list rendering with LazyVStack

### Out of Scope

- Backend/API changes — backend is solid, iOS-only focus
- Offline support / sync conflict resolution — future milestone
- Push notifications / webhooks — future milestone
- iPad-specific layouts — iPhone first
- Third-party dependencies — Apple frameworks only
- Test coverage — separate effort after v1 visual polish
- Auth improvements (JWT, Keychain) — works for local network use

## Context

The iOS app is brownfield — functional but visually inconsistent. Some screens (Calendar, Home) have more polish than others (Trips, Decisions, Gifts). The app currently has 8 tabs, 10+ models, and a comprehensive APIService. The design goal is to bring everything up to the quality level of Apple's own apps (Reminders, Health, Home) with consistent spacing, typography, and interaction patterns.

The codebase map at `.planning/codebase/` documents the current architecture, conventions, and concerns in detail.

Family members: Jesse, Sophie, Rowan, Jude.

## Constraints

- **Tech stack**: SwiftUI + SwiftData, iOS 18+, Xcode 16+, no third-party deps
- **Design language**: Apple-native aesthetic — SF Symbols, system fonts, standard spacing
- **Bundle ID**: com.atlasatlantic.familylife
- **Backend**: Express/SQLite at configurable URL, 18+ REST endpoints — do not modify
- **Users**: Jesse and Sophie (2-person household with kids)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| iOS-only scope | Backend works well, all effort on client polish | — Pending |
| Apple-native aesthetic | Users want it to feel like a first-party app | — Pending |
| No third-party deps | Reduce complexity, leverage Apple frameworks | — Pending |
| Design system first | Consistency requires shared foundation before per-screen work | — Pending |

---
*Last updated: 2026-03-20 after initialization*
