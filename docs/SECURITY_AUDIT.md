# Security & Architecture Audit — Remediation Log

Date: 2026-06-25. Scope: full-codebase review (auth, authz/isolation, AI/concierge,
payments, email, DB, deploy, iOS) followed by remediation of P0/P1 findings.

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
  corrected to `com.mylauft.kinrows`.

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
- Deploy target is **Render** (`render.yaml`), not Railway — the go-live steps
  above that say "Railway" mean the Render dashboard.

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
- **Git-history purge NOT done** — plaintext passwords + old session secret
  remain in early commits. Run `git filter-repo`, force-push, rotate the secret.
- **2FA still OFF** in production (`AUTH_2FA_ENABLED` unset) — enable per the
  go-live sequence once the 2FA build is broadly installed.
- **Privacy policy (`website/privacy.html`) still contradicts the code in two
  places**: it says "we do not collect precise GPS" (the server stores
  `last_lat/last_lng` when presence sharing is on) and undersells that receipt
  images are never stored. Reconcile the copy with the shipped behavior.
- **Backups are unencrypted** on the same Render disk (14-day retention);
  consider app-level encryption of the nightly `VACUUM INTO` snapshots.
