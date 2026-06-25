# Security & Architecture Audit — Remediation Log

Date: 2026-06-25. Scope: full-codebase review (auth, authz/isolation, AI/concierge,
payments, email, DB, deploy, iOS) followed by remediation of P0/P1 findings.

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
