# Production follow-up — 2026-09-21

App Store release status remains **HOLD**. This is a staged remediation log, not approval to submit.

## Deployment 1

Commit `6db9747`, Railway deployment `b4b1389e-4732-447e-b820-969af43d288a`: SUCCESS. GitHub CI passed; `https://kinrows.com/healthz` returned 200 and the revised public marketing copy is served. Backend and website are deployed; Swift changes require a new signed iOS distribution build.

## Concierge and billing expansion

Implemented the 40 operations missing from the original audit: 163 handlers, 28 model-facing tools. Native permission/camera/HealthKit/location handoffs remain unverified and continue to fail the release gate. Added HTTP readback, cross-household denial, private-routine ownership, membership-removal, and concurrent hosting-approval tests. The original 40-name gap is closed structurally; this does not certify every field, live interpretation, or native workflow.

Other fixes:

- Stripe account deletion now uses the documented DELETE subscription endpoint, verifies cancellation, and preserves the account on failure. Previously it used an invalid POST endpoint and ignored all failures. Already-canceled subscriptions are safe to retry.
- Hosting responses share one service between HTTP and Concierge; a dedicated SQLite transaction prevents duplicate calendar events and partial approvals. No transaction runs on the process-wide shared connection.
- Budget history and routine calendar occurrences share the native HTTP algorithms.
- Memory reads now return IDs required for selective forgetting; list and routine-entry reads expose IDs needed for edits.
- A rivalry with no opponent now asks for another participant instead of failing a database constraint.
- Native detail views refresh after Concierge changes, including decisions, rivalries, itinerary stays/expenses, stats, messages and group feed.
- Website developer/LLM tool counts updated to match the expanded registry.

Verification: 450 backend tests pass; 14 isolated tool → SQLite → native HTTP scenarios pass; five official MCP conformance scenarios pass; SEO check passes. Unsigned Release app/widget compilation also passes. Live routing evidence is detailed below.

Initial live routing: **65/74 first-tool matches** with fictional prompts only. No real household actions were executed. Failures included one list/Home pin misroute, valid People/contacts preflight lookups, and standalone pronoun prompts missing conversation history. List pin guidance was corrected; a targeted retest chose the correct lists domain but first read list_all. This evaluator is strict first-call classification, not full-turn completion evidence. The live gate remains open.

Production configuration inspection printed key names only: no `APPLE_SIGNIN_*` revocation signing credentials are configured. Apple revocation remains blocked on provisioning the correct Sign in with Apple key and real-device verification. The implemented code exchange is now isolated in draft PR #15, described below. APNs credentials are not assumed interchangeable.

Other unresolved gates at that stage included user blocking/content filtering (subsequently addressed in the safety batch below); complete retention/erasure and backup policy; real StoreKit/Apple/APNs/device acceptance; App Store Connect metadata/products/privacy/signing/reviewer access. See the original release DAG for the full requirements.

## Safety and erasure batch

The Concierge/billing expansion deployed successfully as commit `23dbf81`, Railway `d8a4941c-2767-49fa-81e4-0ee938a9e63a`; GitHub CI passed and public health remained 200.

The next batch adds mutual user blocking, enforced in DMs, images, conversation lists, unread counts, feed reads, comments/reactions, Home activity, Concierge history/tools and notification delivery. Native Chat now provides block confirmation and a reversible blocked-members list. A conservative local text check rejects explicit threats and prohibited sexual-content phrases before storage. This is **not comprehensive image/text moderation**; the report-monitoring and image-review gates remain open.

Account deletion now removes authored feed content/photos, related reactions/comments/reports, and queued notification previews addressed to or authored by the departing account. Completed delivery jobs discard payload text. Shared planning records, legacy name-only authorship and backup handling still need the policy/acceptance work described in the baseline.

A newly found attachment leak is fixed: legacy private-note attachments cannot reveal their title/body to another household member. Read-time authorization applies even if the attachment was created before this fix.

Evidence: 457 full-suite tests pass, including 17 isolated wiring/safety/privacy scenarios. Five MCP smoke scenarios pass. Unsigned Release app/widget and Debug simulator builds pass. In the isolated simulator, block → conversation unavailable → blocked-member list → unblock was exercised; raw test DB confirmed the block. Small follow-up UI fixes label the block-management control and clear stale unavailable state after unblocking. No real users/messages/pushes were involved.

Live end-to-end follow-up: **5/5** synthetic scenarios pass using the real provider, real Concierge loop and handlers, isolated SQLite, and authenticated native HTTP readback: save address, pin an existing list after lookup, create a private routine, post to feed, remember then selectively forget. Each mutation emitted native refresh actions. `scripts/concierge-live-wiring.js` reproduces these checks with an explicitly supplied provider key and no production account data. These scenarios resolve the list-pin first-call ambiguity but do not certify all natural-language workflows. Final safety Release build passes after the UI follow-ups.


## Deployment 3 and Apple prerequisite

Safety/erasure commit `ed55a22` deployed successfully in Railway `86791418-9005-4a50-a3a2-9a08ba6105e3`. GitHub CI passed and public health returned 200. Blocking notification coverage includes direct messages and group fan-out with an identified author; other notification types still require an actor-coverage audit.

[Draft PR #15](https://github.com/make-tuned-unit/family-life-organizer/pull/15) implements Sign in with Apple code exchange and token revocation before account erasure. Its isolated branch passes 461 tests and unsigned Release compilation. It is deliberately **not deployed**: Railway lacks the required Sign in with Apple signing credentials, and Apple-linked deletion must ship with the compatible native client. The APNs key is not assumed to have the Sign in with Apple capability. Setup and acceptance instructions are on that branch in `docs/qa/APPLE_REVOCATION_SETUP.md`.

## Native Concierge entry points and complete note reads

Added explicit `get_workflow_handoff` for receipt capture, Cook, calendar, trips, health/rivalries, groups, messaging, notes, routines and conversation history. Supported native clients receive a tappable next step; older clients receive instructions without a misleading saved-changes action. Handoffs never request permissions or mutate user records by themselves, never publish a data-change notification, and action-limit fallback text distinguishes pending user action from saved work. Existing screens retain their permission and confirmation steps.

Added full-note retrieval with owner/shared-membership authorization. Behavioral tests cover complete bodies beyond previews, cross-household denial, member access to shared notes, and immediate retraction when made private.

The registry now has 168 handlers and 29 model-facing tools. Real-provider synthetic checks pass 3/3 for receipt, health and group handoff routing. These prove chat/API action delivery, **not** completion of native permission flows. The nine native acceptance categories remain open in the fail-closed DAG; a route to a screen is not full workflow parity.

Verification for this batch: 462 backend tests pass, including 19 isolated wiring scenarios; five MCP conformance scenarios pass; SEO validates 40 pages and five hubs; unsigned Release app/widget compilation passes. Native handoff button interaction and completion remain unverified.
