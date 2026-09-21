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

Production configuration inspection printed key names only: no `APPLE_SIGNIN_*` revocation signing credentials are configured. Apple revocation remains blocked on provisioning the correct Sign in with Apple key and implementing/verifying the code exchange. APNs credentials are not assumed interchangeable.

Other unresolved gates: user blocking/content filtering; complete retention/erasure and backup policy; real StoreKit/Apple/APNs/device acceptance; App Store Connect metadata/products/privacy/signing/reviewer access. See the original release DAG for the full requirements.
