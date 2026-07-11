# Kinrows — Production Launch Checklist

**Maintained live.** This is the single source of truth for what's left before
App Store submission. Update the checkboxes as items land. Last updated
2026-07-11.

Legend: ✅ done · ⏳ deferred (needs a human / external action) · 🔜 code-ready, needs a build/deploy step.

---

## 1. App Store acceptance (submission blockers)

- ✅ **In-app account deletion** (Guideline 5.1.1(v)) — `POST /api/account/delete` + Settings → Account → Delete Account. Covered by `test/account-deletion.test.js`.
- ✅ **AI data-sharing consent** (5.1.2(i)) — Cook and receipt scanning both show a first-use disclosure before sending data to Anthropic.
- ✅ **Privacy manifest** (`PrivacyInfo.xcprivacy`) — valid data types, `Linked=true`, `CA92.1` reason; no unused required-reason APIs.
- ✅ **Permission usage strings** accurate (location, HealthKit read-only, speech "when supported", camera, photos, notifications).
- ✅ **In-app Privacy Policy & Terms links** (Settings → About).
- ✅ **HealthKit** — removed unused clinical-records entitlement + write usage string (app only reads steps/flights).
- ⏳ **Fill the App Privacy "nutrition label"** in App Store Connect. Answers are pre-written in `docs/APP_PRIVACY_LABEL.md` — copy them into the form. All types **Linked = Yes, Tracking = No**.
- ⏳ **Screenshots + App Store metadata** (description, keywords, support URL, category). Marketing copy lives in `website/` for reference.
- ⏳ **Age rating questionnaire** — likely 4+ (no objectionable content); confirm the messaging/UGC answers.
- ⏳ **Export compliance** — uses standard HTTPS/TLS only; answer "uses exempt encryption" in App Store Connect.

## 2. Build & release pipeline

- ✅ Code compiles under **Xcode 16.2** (Intel dev machine) — `glassEffect` compiler-guarded.
- ⏳ **Build & upload requires Xcode 26 / iOS 26 SDK** (Apple mandate since Apr 2026). This Intel Mac cannot run Xcode 26.
  - **Action:** set up **Xcode Cloud** (App Store Connect → Xcode Cloud) with an Archive workflow on `main`, Xcode "Latest Release", delivering to TestFlight. Enable auto-increment build number.
  - Alternative: archive from any Apple-Silicon Mac.
- ⏳ First real-device / TestFlight pass exercising: login → silent re-login, **account deletion**, receipt-scan consent, cooking mode, and **notification taps** (each type deep-links correctly).
- 🔜 Bump marketing version for the first public build (currently developing at 1.0).

## 3. Security (human-owned)

- ⏳ **Purge git history** of committed secrets. Early commits still contain plaintext passwords + an old session secret (verified present). Run `git filter-repo` (or BFG), force-push, then **rotate `SESSION_SECRET`** and reset those legacy account passwords. Destructive — do deliberately, coordinate with any clones.
- ✅/⏳ **Email 2FA** — configured on **Railway** (`AUTH_2FA_ENABLED=1` + `RESEND_API_KEY`) per the owner. Code path verified (fail-fast guards + `test/two-factor.test.js`). **Verify step:** do one real end-to-end login on the live server and confirm a code is emailed and accepted. Never set `AUTH_2FA_ECHO_CODE` in prod (server fail-fasts if you do).
- ⏳ **Encrypt DB backups** — nightly `VACUUM INTO` snapshots are unencrypted on the same persistent disk (14-day retention). Consider app-level encryption (age/libsodium, key in env) or an encrypted off-disk destination.
- ⏳ **Re-run `npm audit`** before release. Current 5 "high" advisories are all in `tar`, a **build-only** transitive dep of `sqlite3` (never runs in production) — not shipped, but recheck for anything runtime.
- ✅ Rotating device-token auth, household authorization guards, parameterized SQL, money coercion, LIKE-injection escaping, cross-household tests.

## 4. Privacy posture (leader-grade)

- ✅ Account deletion, concierge memory/conversation deletion, DM deletion.
- ✅ Location presence sharing **opt-in** (off by default); trip-ETA location only while a trip is active.
- ✅ No third-party analytics/ads/crash SDKs; on-device-first AI; transient receipt images; PII removed from server logs.
- ⏳ **Reconcile `website/privacy.html`** — DONE for the two known contradictions (GPS collection, receipt images, removed false "usage data" claim). **Re-review the whole policy** end-to-end against the shipped App Privacy label before launch, and have it counsel-reviewed if possible.
- ⏳ **Data-export endpoint** — the policy offers "export a copy of your data." Not yet built (`GET /api/account/export`). Either build it or soften the policy to "by request" until then.
- ⏳ Consider **APNs payload minimization** — pushes currently carry message/coverage/child-name text in the visible alert (Apple can read payloads). A Notification Service Extension fetching content post-delivery would be the privacy-max move (deferred; not a blocker).

## 5. Infrastructure / ops

- ✅ `.env.example` documents all 26 server env vars.
- ⏳ Confirm Railway env has: `SESSION_SECRET`, `ANTHROPIC_API_KEY`, APNs trio (`APNS_KEY_ID`/`TEAM_ID`/`KEY_BASE64`), `RESEND_API_KEY`, `APNS_BUNDLE_ID`. Push and email are silently disabled if unset.
- ⏳ Verify the **APNs production** certificate/key and `aps-environment: production` match the distribution build.
- ⏳ **StoreKit / subscriptions**: products configured in App Store Connect matching `services/subscription.js` IDs; test a sandbox purchase end-to-end (verify, entitlement unlock, `/api/subscription/notifications` server-to-server).
- ⚠️ **Verify DB persistence on Railway.** `database.js` only auto-uses a persistent path when `RENDER_DISK_PATH` is set (Render-specific). On Railway you must set **`FAMILY_DB_DIR` to a mounted volume path** (e.g. `/data`) — otherwise `family.db` lands on ephemeral storage and is **wiped on every redeploy**. Confirm the volume is mounted, `FAMILY_DB_DIR` points at it, and `backups/` (nightly snapshots) is on the same volume. This is the single highest-risk ops item.
- 🔜 Set up basic uptime monitoring on `/healthz`.

## 6. Nice-to-have polish (post-launch OK)

- ⏳ Notification upgrades from the audit: trip pushes to the *household* (not the traveler's own device), rivalry score-update spam throttle, in-context banner suppression (don't notify a DM while that chat is open), `INSendMessageIntent` communication notifications with sender avatars, quick-action categories (reply/approve/check-off). Deep-linking + threading + time-sensitive levels are ✅ done.
- ✅ Concierge `complete_rivalry` now posts the feed celebration + win/loss pushes (parity with the UI button).
- ⏳ iOS unit/UI test target (backend has 28 tests; the app has none).
- ⏳ Widgets / Live Activities (coverage "who has the kids now", active-trip next stop) — flagged by UI/UX research.

---

### How to use this file
When you finish an item, flip its box to ✅ and note the commit. When you
discover new pre-launch work, add it under the right section with ⏳. Keep the
"human-owned" items (git purge, App Store Connect forms, env/secrets, 2FA
enablement) clearly separated from code that just needs a build.
