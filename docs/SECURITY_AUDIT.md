# Security & Architecture Audit — Remediation Log

Date: 2026-06-25. Scope: full-codebase review (auth, authz/isolation, AI/concierge,
payments, email, DB, deploy, iOS) followed by remediation of P0/P1 findings.

**Live source of truth for launch checkboxes:** [PRODUCTION_CHECKLIST.md](PRODUCTION_CHECKLIST.md).
`docs/PROD_READINESS.md` is a 2026-04 snapshot (SwiftData / Render era) and is **not**
current. This log is append-only; later addenda supersede earlier claims when they
conflict (notably 2FA on/off and git-history purge — see 2026-08-26 below).

## 2026-08-26 — Pre-launch security audit

Full-stack specialist pass (threat-model first, then every Express route, Concierge
`GROUPS` handler, iOS `APIService` / entitlements, and unauthenticated path).
**P0/P1 fixed in the same pass.** Live production was checked **read-only**
(TLS, headers, public pages, `/healthz`, catalog). No authenticated probing, waitlist
POSTs, analytics floods, or webhook replays against Railway.

Standards used as checklists: OWASP ASVS L2 + API Top 10, MASVS, OWASP LLM Top 10,
App Store 5.1.x.

### Threat model (frozen)

- **Assets:** household PII (kids’ sleep/chores/milestones, DMs, receipts, GPS,
  EventKit titles, Concierge memory), session cookies + refresh tokens, developer
  API keys, StoreKit/Stripe entitlements, invite/coverage URLs, SQLite + unencrypted
  `VACUUM INTO` backups.
- **Primary attackers:** a logged-in member of household B (IDOR / clan leakage —
  historically #1), a stranger with a stolen cookie/token/key, a BYO-agent with a
  `kr_live_` key, webhook forgers (Apple/Stripe), prompt injection via stored
  notes/titles, same-origin XSS on `kinrows.com` (API + marketing share one Express origin).

### Findings fixed in this pass (P0 / P1)

| Sev | Finding | Fix |
|---|---|---|
| P0 | SIWA accounts had a random unusable `password_hash`; `POST /api/account/delete` required `current_password` — App Store **5.1.1(v)** blocker | Accept Apple `identity_token` + `nonce` (JWKS verify, `sub` must match `users.apple_user_id`) **or** password |
| P0 | `deleteUserAccount` ran `PRAGMA foreign_keys = OFF` and could orphan `api_keys` (billing/agent keys outliving the user) | Explicit `DELETE FROM api_keys`; best-effort Stripe cancel for sole-owner households |
| P0 | `PUT /api/notes/:id` spread `req.body`, so `group_id` could retarget a note at another household | Allowlisted fields only; `group_id` set solely via `resolveNoteShare` when `shared_scope` is present |
| P0 | `POST /api/location` had no server opt-in; a modified client could always post GPS and `GET /api/household/presence` returned coords | `users.share_presence` (default 0); POST location 403 unless on; opt-out clears lat/lng; presence query nulls coords for opted-out members |
| P1 | Coverage `/c/:token` (128-bit, no expiry, PII in HTML); JSON GET did not hex-validate | Token must be 32 hex chars; lookup requires not cancelled **and** `created_at` within 30 days; `robots.txt` `Disallow: /c/`; coverage HTML sets `PAGE_CSP` |
| P1 | Analytics collect was unauthenticated with no rate limit; drain used `!==` | 120/min/IP; prune events older than 90 days / beyond newest 100k rows; drain uses `timingSafeEqualString` |
| P1 | Privacy policy promised in-app export that did not exist | `GET /api/account/export` (JSON dump, no hashes/tokens/blobs) + Settings export |
| P1 | DMs stayed readable after leaving a shared group | `GET /api/messages` filters to `usersShareGroup`; partner thread 403 otherwise |
| P1 | Dormant `getHealthMetrics` interpolated `days` into SQL | Parameterized `'-' \|\| ? \|\| ' days'`, clamped 1–3650. Still not HTTP-routed |
| P1 | Helmet CSP off; marketing CSP not applied to blog/static or coverage HTML | `WEBSITE_CSP` via `setHeaders` on `website/` HTML/txt; `PAGE_CSP` on `/c/:token` |
| P1 | `public/sw.js` was cache-first for `/` and `/login` | Unregister + drop caches on activate |
| P1 | Admin diagnostic dumped all users | Counts only (`user_count`, group-type counts). Fail-closed if `ADMIN_USER_IDS` unset |
| P1 | iOS logout left presence / calendar-share / HealthKit watermarks; developer keys copied to general clipboard | Logout clears those keys; pasteboard `localOnly` (+ 60s expiry on API keys) |
| P2 | `website/privacy.html` / App Privacy label stale (Render, no analytics, no SIWA/Resend/BYO) | Policy last-updated 2026-08-26; label host is Railway; Stripe + SIWA listed |

Tests: `test/prelaunch-security.test.js` + SIWA delete case in `test/apple-signin.test.js`.
`npm test` — 156 passing.

### Wave 2 — remaining surfaces (verified, no extra P0/P1)

Household CRUD (receipts, budget, pantry, trips, gifts, projects, recurring, cook,
feed, lists, itineraries, coverage, people, routines, milestones) still 403s on
`!groupId` and uses `requireHouseholdRow` / `requireGroupRow` / `requireListAccess` /
`requireContactOwner` / `usersShareGroup` as appropriate. Clan vs household:
`requireGroupManage` + rivalry `getUserIdByName(..., group_id)`. Invite codes reject
unknowns. `COMP_PREMIUM_ALL` is env-only and defaults off. Email 2FA /
`AUTH_2FA_ECHO_CODE` fail-fast in production. Push payload minimization remains
deferred (not P0). `/v1` read-scope is handler-name prefix `get_|list_|analyze_`;
write actions (`log_chore`, `add`, `log_expense`, …) do not sneak under it.
`STRIPE_ALLOW_TEST` / `STOREKIT_ALLOW_SANDBOX` have **no code default on** — only
the env flag or `NODE_ENV !== 'production'`.

### Read-only production checks (2026-08-26, this agent)

Against `https://kinrows.com` and `https://family-life-organizer-production.up.railway.app`:

- TLS 1.3 (`TLS_AES_256_GCM_SHA384`), valid Let’s Encrypt chains, verify OK.
- HSTS `max-age=31536000; includeSubDomains` on both hosts.
- `/healthz` → `{"ok":true}` only (no DB leak). `/c/` without a token → 404.
- Public `GET /api/subscription/catalog` returns product ids / prices only; Stripe is live (`"stripe":true`).
- Marketing `/`, `/privacy`, `/developers`, `/subscribe` already send `WEBSITE_CSP`.
  **Live blog HTML and `/c/:token` do not yet** — that lands when this branch deploys
  (`setHeaders` + `PAGE_CSP`). Live `robots.txt` does not yet `Disallow: /c/` (same).
- `llms.txt` / `llms-full.txt` do not publish admin ids or env internals.

**Not done (by design):** login, waitlist POST, analytics POST, Stripe/Apple webhook replay, coverage-token enumeration.

### Prior-doc contradictions (resolved here)

Earlier sections of this file and [PRODUCTION_CHECKLIST.md](PRODUCTION_CHECKLIST.md)
disagreed. **This addendum is authoritative:**

| Topic | Old claim A | Old claim B | 2026-08-26 |
|---|---|---|---|
| Email 2FA in prod | “already `AUTH_2FA_ENABLED=1` on Railway” | “still OFF / unset” | **OFF.** Railway CLI 2026-08-26: `AUTH_2FA_ENABLED` is present but empty; `AUTH_2FA_ECHO_CODE` unset. |
| Git-history purge | “NOT done” (2026-07-11 addendum below) | Checklist: purged 2026-07-11 via `git filter-repo` | **Treat purge as done** per checklist evidence. **`SESSION_SECRET` rotated 2026-08-26 via Railway CLI.** Reset legacy jesse/sophie passwords if those accounts still exist. |
| Privacy copy | “contradicts GPS / receipts” | Checklist: GPS copy reconciled | **Reconciled in this pass** (GPS opt-in, first-party pageviews, SIWA, Resend, Railway, BYO-agent, in-app export). |
| Host | Render in privacy label / old human-actions | Railway | **Railway.** Render config was removed 2026-07-11. |

### Residuals (P2 / P3 — documented, not built)

- No TLS pinning (acceptable for Railway + ATS).
- Token-login bypasses email 2FA **by design** (device already enrolled).
- In-memory rate limiter (multi-replica bypass). Redis is out of “no new deps”; a SQLite-backed limiter is a follow-up if a second replica appears.
- Unencrypted same-disk `VACUUM INTO` backups (14-day). Optional `age`/libsodium is P2.
- Developer keys: no expiry / IP allow-list; `/v1/snapshot` is a full household dump to any valid key.
- Indirect prompt injection via stored titles/notes — mitigation is prompt text + sanitizers + `remember` caps + `minimizedFacts` + `cloudAIEnabled` chokepoint. Not solvable as a filter.
- No in-app lock / screenshot protection (product decision).
- `NSHealthUpdateUsageDescription` remains in the Xcode project because the HealthKit **capability** is on for reads; Apple still expects the update string. App does not write HealthKit.
- APNs payloads still carry message/coverage/child-name text (Notification Service Extension deferred).
- `npm audit` 2026-08-26: highs/critical are **build-only** under `sqlite3 → node-gyp` (`tar`, `ip-address`, `socks-proxy-agent`, `brace-expansion`). Not imported by `dashboard.js`. Do not `npm audit fix --force` (it wants sqlite3@6). CI continues `|| true` with that comment.

### Human-owned (Railway CLI applied 2026-08-26)

Done from this agent (project **Kinrows**, service **family-life-organizer**):

1. **`SESSION_SECRET` rotated** (new 128-char hex). Live sessions/cookies are invalid — users sign in again.
2. **`COMP_PREMIUM_ALL` deleted** (was `1`). Boot will no longer grant premium to every household. Existing `comp:` rows in SQLite may still entitle households until revoked via `POST /api/admin/comp`.
3. **`FAMILY_DB_DIR=/opt/render/project/src/vault/family-life`** (same path as the attached 5 GB volume).
4. **`AUTH_2FA_ECHO_CODE` unset.** `STOREKIT_ALLOW_SANDBOX` unset. Leftover **Gmail IMAP** env vars deleted.
5. **`AUTH_2FA_ENABLED` is off** (key present, empty). `ADMIN_USER_IDS` is a single real id. `NODE_ENV=production`. `APNS_ENV=production`.

Still human:

1. Reset legacy jesse/sophie **passwords** if those accounts still exist.
2. Enable `AUTH_2FA_ENABLED=1` only after every TestFlight user has the 2FA UI.
3. Optionally revoke leftover comp entitlements and set a Railway `healthcheckPath` of `/healthz` (currently unset on the service).
4. Compile touched Swift in Xcode before submit (`swiftc` was not on the audit machine).
5. First live web Checkout purchase (Lite + Premium) after this cutover — confirm entitlement + Customer Portal.
6. Enable **Associated Domains** on App ID `com.kinrows.app` (team `Z58XSBM78S`) so Universal Links for `/open/*` sign; the `kinrows://` custom scheme works without it. Walk the app-first path once: Subscribe in the iPhone app → Safari Checkout + Apple Pay → auto-return → Concierge unlocked.

### Stripe live cutover (2026-08-26, later the same day)

Production is **live Stripe**, not test:

- Live catalog on account `acct_1U8kNvAFD5YfBJgE`: Lite `prod_V98PyRIxlZ3v19`, Premium `prod_V98QNWgRBTE8mx`, four USD prices with StoreKit lookup keys (`price_1U8q9X…` / `price_1U8q9k…`).
- Live webhook `we_1U8q9tAFD5YfBJgEICI8fCaV` → `https://kinrows.com/api/subscription/stripe` (checkout completed, subscription updated/deleted, invoice paid / payment_failed).
- Railway: `sk_live_` / `pk_live_`, live `STRIPE_WEBHOOK_SECRET`, live `STRIPE_PRICE_*`. **`STRIPE_ALLOW_TEST` deleted.**
- Deploy `50fbf719` SUCCESS. Read-only probes: `/healthz` `{"ok":true}`; `GET /api/subscription/catalog` `"stripe":true` + four plans; unauth checkout 401; unsigned webhook 400; logs `Stripe billing: ENABLED`.

## 2026-08-26 — Stripe web subscriptions (Concierge)

Web Checkout for the four Concierge plans (Lite/Premium × monthly/yearly). Entitlement
is still per-household in `subscriptions`; Stripe rows are keyed `stripe:<sub id>` so
they cannot collide with StoreKit original transaction ids.

- Checkout and Customer Portal require a session (`requireAuth`) and a household.
  Metadata on the Checkout Session + Subscription is the only bind (`kinrows_group_id` /
  `kinrows_user_id` / `kinrows_product_id`) — the webhook never trusts a client-supplied
  household id.
- Webhook (`POST /api/subscription/stripe`) verifies Stripe's `v1` HMAC (5-minute
  tolerance) against the **raw** body before parsing JSON. Unsigned events are 400.
- Test-mode events are refused in production unless `STRIPE_ALLOW_TEST=1` (same idea as
  `STOREKIT_ALLOW_SANDBOX`).
- Secret and restricted keys live in env only (`.env` gitignored). Prefer a restricted
  key with Checkout / Billing / Webhooks / Customers once this is proven on test keys.
- Tests: `test/stripe-billing.test.js`, `test/billing-email.test.js`, `test/rate-limit.test.js`.
- **Funnel (2026-08-27):** hosted Checkout with promo codes, auto locale, household copy, `{CHECKOUT_SESSION_ID}` success URL that the subscribe page confirms before celebrating. Customer Portal is created with plan-switch + cancel-at-period-end. Kinrows emails (via Resend) fire on checkout completed, payment failed, and cancellation — Stripe still sends receipts. Lite = **10** chats/day, Premium = **40**, enforced after the premium gate so unpaid callers get 402 not a burned quota; 429 names the tier and suggests upgrade on Lite. Duplicate Stripe events are logged and not re-emailed. **Local currency:** CAD/USD/EUR stickers via Price `currency_options` (same numbers); Adaptive Pricing for everywhere else. **Apple Pay / Google Pay:** Checkout `billing_address_collection=required`; live payment-method domains `kinrows.com` + `www.kinrows.com` (`apple_pay=active`); association file at `/.well-known/apple-developer-merchantid-domain-association`.
- **Permagent sale funnel (2026-08-27):** conversion events land in `permagent_analytics_events` (same drain as pageviews). Server writes `sale_checkout_start` / `_complete` / `_blocked`, `sale_invoice_paid`, `sale_payment_failed`, `sale_subscription_updated` / `_canceled`, `sale_portal_open`, `sale_return_success` / `_canceled`, `sale_storekit_verified`. The subscribe page adds intent events (`sale_plan_click`, `sale_signin_*`, `sale_checkout_redirect`). No user id / email / Stripe customer id. iPhone app still has no analytics SDK.
- **App-first purchase (2026-08-27):** iPhone paywall Subscribe calls `POST /api/subscription/checkout` with `source=app` using the app session (Safari never sees the password). Success/cancel URLs are public `/open/subscribed` and `/open/subscribe-canceled`, which bounce into `kinrows://` (and Universal Links via `/.well-known/apple-app-site-association`, appID `Z58XSBM78S.com.kinrows.app`, paths `/open/*`). The app confirms `GET /api/subscription/checkout/session` and refreshes household status on foreground if the user switches back without tapping Open Kinrows. Return pages are unauthenticated on purpose — they must not call billing APIs from Safari. Enable **Associated Domains** on App ID `com.kinrows.app` so Universal Links sign; the custom scheme works without it.

## 2026-08-26 — Pre-signup onboarding + Sign in with Apple

- Unauthenticated first launch now shows the product tour **before** login/signup.
- `POST /api/auth/apple` verifies a native Sign in with Apple identity token (RS256 + Apple JWKS, `aud` = `com.kinrows.app`, nonce hashed SHA-256). Apple-already-2FA: no email OTP on this path.
- `users.apple_user_id` unique; SIWA accounts get a discarded random `password_hash` so password login cannot succeed. Matching **verified** email links to an existing password account instead of minting a second household.
- `POST /api/auth/register` with an unknown `invite_code` now returns 400 (previously silently created a second household).
- Tests: `test/apple-signin.test.js` (injected JWKS). Enable Sign in with Apple on App ID `com.kinrows.app` in the developer portal — that cannot be done in code.

## 2026-08-24 — Developer API (bring-your-own-agent)

New bearer-key surface (`/v1/*`, `services/developerApi.js`, full reference in `docs/DEVELOPER_API.md`):

- Keys: `kr_live_` + 256-bit random; SHA-256 at rest (`api_keys.key_hash`), plaintext shown once; `ON DELETE CASCADE` with the user. 10 active per user.
- Minting (`POST /api/developer/keys`) is `requireAuth + requirePremium`; revoke is session-auth only (lapsed subscribers can still clean up).
- `requireApiKey` re-checks the household subscription on **every** `/v1` request (402 on lapse, 401 on revoke) — no entitlement caching on this path.
- Every tool call is built with the key owner's `userId`/`groupId` and goes through `conciergeTools.run`, so the existing per-handler household guards apply unchanged. Cross-household test in `test/developer-api.test.js`.
- `read` scope enforced server-side via `conciergeTools.isReadOnly` (handler-name allowlist `get_/list_/analyze_`; unknown ⇒ write ⇒ refused).
- `/v1` never reads the cookie session; account/password/email/delete routes are unreachable with a key.
- Rate limit 120/min keyed on a hash of the bearer (bad keys can't pollute a real key's bucket).
- Residual: keys have no expiry and no IP allow-list (documented as "treat like a password"); consider optional expiry if abuse appears.

## 2026-07-20 — stability & isolation sweep

A second multi-surface review (backend, concierge tools, iOS) with remediation:

- **Cross-household isolation (P0).** ~14 household-scoped read/write endpoints
  (receipts, budget, pantry, trips, addresses, gifts, projects, recurring
  payments, cook) treated a `null` groupId as "no filter", so a household-less
  caller (`POST /api/groups/:id/leave`) could read/write every household's data.
  All now guard `if (!groupId)`. The legacy `/app` SSR grocery list was
  scoped to the caller (was global).
- **Boot-time membership rewrite (P0).** The hardcoded jesse/sophie household
  seed ran on every boot, force-rewriting `group_members` (evicting invited
  members, absorbing any stranger named `sophie`). Now gated one-time behind an
  `app_meta` flag; the NULL-only backfill remains idempotent.
- **Coverage IDOR (P0).** Coverage recipients / push targets were resolved by a
  forgeable display-name match. Now additionally require a shared-group link to
  the contact's owner, so renaming yourself can't harvest another family's
  requests, invite tokens, or approvals. Rivalry name→user push resolution is
  likewise group-scoped.
- **Subscriptions (P1).** Each StoreKit transaction is now bound to its
  first-claiming household (blocks JWS replay / entitlement ping-pong), and
  Sandbox transactions are rejected in production (`STOREKIT_ALLOW_SANDBOX=1`
  to allow in dev/TestFlight).
- **Rivalries (P1).** Callers must belong to a name-derived rivalry group;
  entry `member_name` is validated against the roster.
- **Concierge/injection (P1/P2).** Display name sanitized in the brief system
  prompt; `add_gift_idea` now `assertHousehold`s its `person_id`; mid-stream
  API errors surface instead of a false "Done"; `get_coverage` lists your own
  requests so cancel works.
- **Correctness/DoS (P2).** `?limit` clamped (`limit=-1` was unbounded);
  monthly/yearly recurrence anchored to origin day; money routed through
  `parseMoney` on recurring payments/projects/expenses; waitlist notify email
  HTML-escaped.
- **iOS (P1/P2).** Fixed a logout race that could resurrect a revoked session,
  bounded silent-relogin recursion, stopped rivalry HealthKit sync from spamming
  opponents with pushes, and fixed a DM watermark key mismatch that re-notified
  already-delivered messages.

## Email 2FA rollout (go-live sequence — do in order)

Email two-factor login is **deployed but OFF** (`AUTH_2FA_ENABLED` unset) so it
can't lock out the current app build. To turn it on:

1. Upload the new TestFlight build (has the 2FA + Security UI) and have **every**
   active user install it. (Required 2FA + an old build = lockout.)
2. Set **`RESEND_API_KEY`** on Railway (same key as the marketing site) so codes
   can actually send. Without it, no one can complete login.
3. Set **`AUTH_2FA_ENABLED=1`** on Railway. 2FA is now required for everyone.
4. First login per user: enter password → enter email → enter the 6-digit code →
   done (email is captured + verified in that one flow).

To roll back instantly: remove `AUTH_2FA_ENABLED`. Never set `AUTH_2FA_ECHO_CODE`
in production (test-only — it echoes the code in the response).

## ⚠️ Required human actions (cannot be done in code)

These secrets were committed to git history and **must be rotated/retired** — the
code no longer uses them, but the exposed values are still in past commits.

1. **Gmail account `redacted@example.com`** — the email-receipt ingestion
   feature (and its `imap-simple` dependency) has been **removed from the
   codebase**. Delete the Google account (or at minimum revoke its App Password
   `REDACTED-GMAIL-APP-PASSWORD`). No rotation needed.
2. **Set Render dashboard env vars** (now `sync: false` in `render.yaml`):
   `SESSION_SECRET` (generate: `openssl rand -hex 64`) and `ANTHROPIC_API_KEY`.
3. **Reset the jesse / sophie passwords** — their old plaintext values
   (`REDACTED-PASSWORD`, `REDACTED-PASSWORD`) were in source history.
4. **Purge secrets from git history** (`git filter-repo` / BFG on `render.yaml`
   + `dashboard.js`) and force-push, then treat the old values as compromised.

## Fixed in code

### Auth & session (dashboard.js)
- Session secret now from `SESSION_SECRET` env; **fail-fast in production** if unset.
- Persistent **SQLite session store** (was in-memory `MemoryStore`).
- Cookie flags: `secure` (prod), `httpOnly`, `sameSite=lax`, 30-day `maxAge`; `trust proxy`.
- **Session regenerated on login/register** (anti session-fixation).
- Removed `LEGACY_USERS` plaintext accounts and the plaintext login fallback.
- **Rate limiting** on `/api/auth/login`, `/login` (10/min/IP) and `/api/auth/register` (5/hr/IP).
- Anti-enumeration: constant-time dummy bcrypt compare when the user is absent.
- Password policy (≥8 chars, ≠ username); bcrypt cost 10 → 12.

### Web hardening
- `helmet` (HSTS, nosniff, frame-guard). `SameSite=lax` is the CSRF control for the cookie+JSON API.
- **Centralized error handling**: 160+ `res.status(500).json({error: err.message})`
  replaced with an opaque `sendServerError` (logs server-side); HTML error leak fixed;
  `/api` 404 handler + final Express error middleware.
- Global body limit 10mb → 1mb, with an 8mb allowance only on image-upload paths.
- `/healthz` liveness probe (wired to `render.yaml` `healthCheckPath`).

### Authorization / isolation
- `get_itinerary_stays` concierge tool now `assertHousehold`-gated (was a cross-household read).
- `POST /api/itineraries` validates caller-supplied `group_id` via `resolveCreateGroupId`.
- `reorderListItems` scoped to the owning list (`AND list_id = ?`).
- DM `POST /api/messages` requires sender+recipient to share a group.
- `updateItinerary` no longer allows `group_id` reassignment (isolation escape).
- Decision reactions/comments attribute to the session user (no client `member_name` spoofing).

### Database integrity (database.js)
- `PRAGMA foreign_keys = ON` (cascade clauses now actually fire).
- Mass-assignment denylist → shared `PROTECTED_UPDATE_COLUMNS` covering all
  ownership/identity columns (8 dynamic `update*` helpers).
- `approveCoverage` wrapped in a real `BEGIN/COMMIT/ROLLBACK` transaction.
- Migration invite code uses `crypto.randomBytes` (was `Math.random`).

### AI / payments / email
- Prompt-injection hardening: `userName` + stored memories sanitized; explicit
  "data is not instructions" guardrail in the system prompt.
- `remember` tool caps stored facts (500 chars, control-char stripped).
- Daily cost ceiling (200 msgs/user/day) on the concierge chat endpoint.
- `appleVerify` now checks each cert's validity window (validFrom/validTo).
- Comp entitlements: added `revokeCompForGroup` + admin `POST /api/admin/comp`.
- email-receipts: **feature removed** (`email-receipts.js` + `imap-simple`
  deleted) — the Gmail account it polled is being retired, so the IMAP ingestion
  path and its credentials/dependency vulns are gone entirely.

### AI privacy / data minimization
- **Brief generates on-device when possible** (Apple FoundationModels, iOS 26+):
  the client requests `?skipAI=1`, so the server makes **no Anthropic call** and
  household data never leaves for the daily brief. Older devices fall back to the
  cloud summary.
- **Minimized cloud fallback** (`conciergeBrief.minimizedFacts`): the server-AI
  brief sends titles + counts only — strips assignees, creator names, locations,
  and exact dollar amounts (percentages only). Full specifics still render in the
  local deterministic cards (which never touch the cloud).
- **"Use cloud AI" privacy toggle** (Settings → Privacy, default on) gates **every**
  Anthropic-backed route via a single chokepoint in `APIService` (each AI method
  checks `cloudAIEnabled`). Off ⇒ the brief stays fully on-device/deterministic and
  the **concierge chat, recipe suggestions (Cook), and receipt-scan (vision)** are
  all disabled — so **no** household data goes to Anthropic. The conversational chat
  inherently needs to send data (tool-calling over live data); the toggle is its
  off-switch. (Note: Anthropic's API does not train on this data.)

### iOS
- Keychain password now `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
  (not iCloud-synced / not in backups); keychain service + `AppConfig.bundleID`
  corrected to match the bundle ID, now `com.kinrows.app`. Note the keychain is
  team-scoped: the move to team `Z58XSBM78S` makes items written under the old
  team unreachable, so every install signs in again once.

### Tests & CI
- `test/auth-isolation.test.js` — end-to-end auth + cross-household IDOR tests
  (boots the server against a throwaway DB). `npm test`.
- `.github/workflows/ci.yml` — runs tests + `npm audit` on push/PR.
- `npm test`, `FAMILY_DB_DIR` env hook for DB isolation in tests.

## Residual / deferred (documented, lower risk)

- **Dependency advisories** (`npm audit`): remaining highs are **not server-reachable** —
  all in the `sqlite3 → node-gyp → tar/@tootallnate` build-time toolchain. Removed the
  dead `nodemailer`/`check-email.js` and the `imap-simple` email chain entirely.
  Follow-up: revisit a tested `sqlite3` major bump (or migrate to `better-sqlite3`).
- **Delete/status DB methods** lack a SQL-layer `group_id` clause — currently safe
  (gated by `assertHousehold`); add as defense-in-depth when convenient.
- **Architecture** (separate effort): `dashboard.js` (~4.7k lines) and `database.js`
  (~3.4k lines) should be split into `routes/*` + `db/*Repo.js` modules. Not security-blocking.

---

## Addendum — 2026-07-11 (privacy & production-readiness pass)

The system moved on substantially since the 2026-06-25 log. Current state:

### Auth (superseded)
- The iOS app **no longer stores the account password**. Login/2FA/register
  return a rotating, server-revocable **device refresh token** (`auth_tokens`,
  SHA-256 at rest, rotated on every use with an `AUTH_TOKEN_GRACE_SECONDS`
  grace window). Legacy Keychain passwords are read once for migration then
  scrubbed. "Log out everywhere" = password change revokes all tokens; logout
  hard-deletes the device's refresh + APNs tokens. See `test/auth-token.test.js`.
- Deploy target is **Railway** — the iOS app's production URL is
  `family-life-organizer-production.up.railway.app` (`AppConfig.swift`). The
  stray `render.yaml` (unused; owner confirmed no Render) was **removed
  2026-07-11**; the go-live steps above that say "Railway" are correct. Earlier
  "Render dashboard" mentions in this log's original body mean the Railway
  dashboard.
- Per the owner (2026-07-11): **email 2FA is already configured on Railway**
  (`AUTH_2FA_ENABLED=1` + `RESEND_API_KEY`). Remaining action is just to verify
  one real end-to-end login on the live server.

### Data lifecycle / privacy (new this pass)
- **In-app account deletion** shipped: `POST /api/account/delete` (re-auth)
  transactionally erases the user + personal data; sole-owner households are
  wiped, shared ones survive. Settings → Account → Delete Account. App Store
  5.1.1(v) satisfied. See `test/account-deletion.test.js`.
- Concierge **memory/conversation deletion** and **DM deletion** endpoints added
  (privacy-policy promises that previously had no implementation).
- Household **location presence sharing is opt-in** (`sharePresenceEnabled`,
  default off); the background poll no longer reports coordinates by default.
- Receipt scanning now has its own **AI first-use consent** (5.1.2(i)).
- **Privacy manifest** corrected (valid Fitness type, Linked=true, full data
  inventory). HealthKit clinical-records entitlement + NSHealthUpdate string
  removed (app never writes HealthKit). Profile image written with
  `.completeFileProtection`. PII (receipt amounts, raw emails) removed from logs.

### Still requiring HUMAN action (unchanged / new)

> **Superseded 2026-08-26.** See the pre-launch addendum at the top of this file.
> Git-history purge was completed 2026-07-11 (rotation still required). 2FA on
> Railway is **unconfirmed**. Privacy copy and export were fixed in that pass.

- **Git-history purge NOT done** — plaintext passwords + old session secret
  remain in early commits. Run `git filter-repo`, force-push, rotate the secret.
- **2FA still OFF** in production (`AUTH_2FA_ENABLED` unset) — enable per the
  go-live sequence once the 2FA build is broadly installed.
- **Privacy policy (`website/privacy.html`) still contradicts the code in two
  places**: it says "we do not collect precise GPS" (the server stores
  `last_lat/last_lng` when presence sharing is on) and undersells that receipt
  images are never stored. Reconcile the copy with the shipped behavior.
- **Backups are unencrypted** on the same host disk (14-day retention);
  consider app-level encryption of the nightly `VACUUM INTO` snapshots.
