# FamilyLife iOS Production Readiness

Last updated: 2026-04-07

This file is the maintained list of work required before the app should be treated as production-ready.

## Completed In This Pass

- [x] Reduced the root iPhone tab structure from 8 tabs to 5 primary destinations.
- [x] Added a dedicated `More` hub for secondary modules.
- [x] Stopped requesting notification permission at app launch.
- [x] Added visible error alerts for the main network-backed experiences: home, calendar, pantry, expenses, and trips.
- [x] Removed always-on `Done` buttons from root destinations and kept them only for sheet presentations.
- [x] Moved notification prompting closer to the action by adding reminder/expiry toggles in creation flows.
- [x] Added explicit failure feedback in key add/edit sheets instead of silently failing.
- [x] Made reminder and expiry-alert requests best-effort so denied notification permission does not block core saves.

## Blockers Before Production

- [x] Added backend APIs and app-side API integration for `Decisions`, `Rivalries`, and `Gifts` so they no longer depend on local-only SwiftData for primary usage.
- [ ] Remove dead local-only SwiftData paths and complete migration cleanup for `Decisions`, `Rivalries`, and `Gifts`.
- [ ] Add auth rules, migration/backfill handling, and data validation hardening for the new shared family feature endpoints.
- [ ] Replace plaintext-style local credential persistence with a production auth/session approach.
- [ ] Define a real environment strategy for `localhost`, local network, staging, and production server URLs.
- [ ] Add end-to-end error handling and retry UX for all network-backed flows.
- [ ] Add offline and degraded-state behavior instead of showing empty states when requests fail.
- [ ] Add analytics and structured logging so production issues can be diagnosed.
- [ ] Add data export, backup, and migration plans for SwiftData and backend records.

## Product Gaps To Ship

- [ ] Weekly meal planner with grocery generation and pantry-aware planning.
- [ ] Family automations and scheduled digests.
- [ ] Apple Calendar integration with EventKit import/export and busy overlays.
- [ ] Memory / knowledge capture UI for warranties, preferences, sizes, allergies, and service history.
- [ ] Native capture flows from outside the app: Share Extension and App Intents.
- [ ] Widgets for agenda, groceries, and pantry status.
- [ ] Live Activity for active trips.
- [ ] Spotlight indexing for household records.
- [ ] App Shortcuts for high-frequency actions like add grocery, add task, start trip, and scan receipt.

## UX And Design

- [ ] Convert remaining duplicated navigation paths into a single coherent hierarchy.
- [ ] Audit all screens for consistent information density, spacing, and toolbar behavior.
- [ ] Add richer search patterns: recent searches, scoped filters, and suggestions where the data set is large enough.
- [ ] Audit reminder copy, timing defaults, and reschedule/cancel behavior across create and edit flows.
- [ ] Review all motion and presentation transitions to ensure they explain state instead of decorate it.
- [ ] Audit Dynamic Type, VoiceOver, contrast, hit targets, and Reduce Motion behavior.
- [ ] Validate iPad layouts instead of relying on iPhone-first scaling.

## Reliability And Quality

- [ ] Add unit tests for view models and services.
- [ ] Add integration tests for critical API flows.
- [ ] Add UI tests for login, tasks, calendar, pantry, expenses, and trip tracking.
- [ ] Add contract checks for backend JSON payloads used by Swift models.
- [ ] Add failure-path coverage for auth expiry, invalid server URL, scanner errors, and empty network responses.
- [ ] Add crash reporting and release monitoring.

## Security And Privacy

- [ ] Review photo, health, location, and notification permission copy for App Store quality.
- [ ] Add purpose-string audit for all protected Apple APIs.
- [ ] Define data retention rules for photos, receipts, comments, and family history.
- [ ] Add privacy policy, support URL, and account deletion flow.
- [ ] Confirm secure transport, session handling, and server-side auth protections.

## App Store And Operations

- [ ] Create production app icons, launch assets, screenshots, and metadata.
- [ ] Prepare TestFlight rollout plan with staged feedback.
- [ ] Define release notes, semantic versioning, and rollback process.
- [ ] Set up staging and production deployment pipelines for the backend.
- [ ] Document restore, incident response, and support procedures.

## Nice To Have After Production

- [ ] Shared expense splitting and settlement tracking.
- [ ] Household insights and proactive recommendations.
- [ ] Calendar conflict detection and schedule suggestions.
- [ ] Location-aware reminders and routines.
- [ ] Family document vault and household reference center.
