# Kinrows — Production Launch Checklist

**Maintained live.** This is the single source of truth for what's left before
App Store submission. Update the checkboxes as items land. Last updated
2026-08-31 (rebased pre-launch security PR onto main).

Legend: ✅ done · ⏳ deferred (needs a human / external action) · 🔜 code-ready, needs a build/deploy step.

---

## 1. App Store acceptance (submission blockers)

- ✅ **In-app account deletion** (Guideline 5.1.1(v)) — password re-auth *or* a fresh Sign in with Apple identity token. Apple-only accounts never had a password they could type. Covered by `test/account-deletion.test.js` and `test/apple-signin.test.js`.
- ✅ **AI data-sharing consent** (5.1.2(i)) — Cook, receipt scanning, **and Concierge chat** show a first-use disclosure before sending data to Anthropic.
- ✅ **UGC report** (Guideline 1.2) — in-app Report on DMs and household feed posts → `POST /api/content/report`. Covered by `test/content-report.test.js`.
- ✅ **Privacy manifest** (`PrivacyInfo.xcprivacy`) — includes Name, Email, Phone Number, Physical Address, User ID, Fitness, Precise Location, Photos, Messages, Other User Content, Other Financial Info, Purchase History. `Linked=true`, tracking=false, `CA92.1`.
- ✅ **Permission usage strings** accurate (location, HealthKit read-only steps+flights, on-device speech, camera, photos, notifications, calendar read/write/share).
- ✅ **In-app Privacy Policy & Terms links** (Settings → About, paywall, signup/login footer).
- ✅ **Paywall 3.1.2** — auto-renew legal copy plus Privacy / Terms links and Restore Purchases.
- ✅ **HealthKit** — no write usage string; `requestAuthorization` only after an explicit Connect Health tap, not on launch or a poll.
- ✅ **iPhone-only** (`TARGETED_DEVICE_FAMILY = 1`).
- ⏳ **Fill the App Privacy "nutrition label"** in App Store Connect. Answers are pre-written in `docs/APP_PRIVACY_LABEL.md` — copy them into the form. All types **Linked = Yes, Tracking = No**.
- ⏳ **Screenshots + App Store metadata** (description, keywords, support URL `https://kinrows.com/support.html`, category). Marketing copy lives in `website/` for reference.
- ⏳ **Age rating questionnaire** — likely 4+ (no objectionable content); confirm the messaging/UGC answers (report + block exists).
- ⏳ **Export compliance** — uses standard HTTPS/TLS only; answer "uses exempt encryption" in App Store Connect.

## 2. Build & release pipeline

- ✅ Code compiles under **Xcode 26.6** (iOS 26.5 SDK present on this Mac) — `glassEffect` compiler-guarded for older toolchains.
- ⏳ **Archive & upload to TestFlight** from Xcode 26 (Apple's iOS 26 SDK mandate). Paid Apps agreement + the four IAP products must exist in App Store Connect first or the binary review will fail Guideline 2.1.
- ⏳ First real-device / TestFlight pass exercising: Sign in with Apple **and** password login → silent re-login, **account deletion** (both re-auth paths), Concierge first-use disclosure, receipt-scan consent, cooking mode, Report on a DM, and **notification taps**.
- 🔜 Bump marketing version for the first public build (currently developing at 1.0).
- 🔜 Deploy this branch so live `robots.txt` `Disallow: /c/`, blog CSP, and coverage-page CSP match the code (verified absent on production 2026-08-26).

## 3. Security (human-owned)

- ✅ **Git history purged** (2026-07-11) — `git filter-repo` scrubbed the two legacy plaintext passwords + the old session secret to `***REMOVED***` across all 381 commits (verified: zero real secrets remain on either branch; HEAD tree byte-identical; old SHAs 1db4954/753b017/5b2a956 gone). Also stripped the old committed `node_modules` (37→27MB). Force-pushed main + the feat branch. **Backup bundle:** scratchpad/PREPURGE-backup.bundle.
  - ✅ **`SESSION_SECRET` rotated 2026-08-26** via Railway CLI (everyone must sign in again). Still reset the legacy jesse/sophie **passwords** if those accounts exist. Optionally ask GitHub Support to purge cached views of the old commits. Anyone with an existing clone should re-clone.
- ⏳ **Email 2FA is OFF in production** (Railway CLI 2026-08-26: `AUTH_2FA_ENABLED` is present but empty; `AUTH_2FA_ECHO_CODE` unset). Code path verified (`test/two-factor.test.js`). Enable only after every TestFlight user has the 2FA UI; `RESEND_API_KEY` is already set.
- ⏳ **Encrypt DB backups** — nightly `VACUUM INTO` snapshots are unencrypted on the same persistent disk (14-day retention). Consider app-level encryption (age/libsodium, key in env) or an encrypted off-disk destination. P2; not a submit blocker.
- ✅ **`npm audit` re-run 2026-08-26.** Highs/critical are build-only under `sqlite3 → node-gyp` (`tar`, `ip-address`, `brace-expansion`). Not imported by the server. Do not `npm audit fix --force` (breaking sqlite3 major). Recheck only if a **runtime** advisory appears.
- ✅ Rotating device-token auth, household authorization guards, parameterized SQL, money coercion, LIKE-injection escaping, cross-household tests, pre-launch isolation tests (`test/prelaunch-security.test.js`). `npm test` = 160 cases.

## 4. Privacy posture (leader-grade)

- ✅ Account deletion, concierge memory/conversation deletion, DM deletion.
- ✅ Location presence sharing **opt-in and server-enforced** (`users.share_presence`, default off); trip-ETA location only while a trip is active.
- ✅ No third-party analytics/ads/crash SDKs; on-device-first AI; transient receipt images; PII removed from server logs.
- ⏳ **Reconcile `website/privacy.html`** — DONE for the two known contradictions (GPS collection, receipt images, removed false "usage data" claim). **Re-review the whole policy** end-to-end against the shipped App Privacy label before launch, and have it counsel-reviewed if possible.
- ✅ **Data export** — `GET /api/account/export` + Settings → Export my data (no hashes/tokens/blobs). Email `kinrows@atlasatlantic.co` remains an alternate path.
- ⏳ Consider **APNs payload minimization** — pushes currently carry message/coverage/child-name text in the visible alert (Apple can read payloads). A Notification Service Extension fetching content post-delivery would be the privacy-max move (deferred; not a blocker).

## 5. Infrastructure / ops

- ✅ `.env.example` documents server env vars including `STRIPE_ALLOW_TEST` / `STOREKIT_ALLOW_SANDBOX` / `COMP_PREMIUM_ALL` (all default off).
- ✅ Railway env confirmed 2026-08-26 via CLI (project **Kinrows** / service **family-life-organizer**): `SESSION_SECRET` **rotated**, `ANTHROPIC_API_KEY`, APNs trio + `APNS_BUNDLE_ID` + `APNS_ENV=production`, `RESEND_API_KEY`. Leftover `GMAIL_USER` / `GMAIL_APP_PASSWORD` deleted (IMAP feature is gone). **Stripe is live** (`sk_live_` / `pk_live_`, live webhook secret, live `STRIPE_PRICE_*`; `STRIPE_ALLOW_TEST` removed).
- ✅ **`FAMILY_DB_DIR`** set to the volume mount `/opt/render/project/src/vault/family-life` (volume `family-life-organizer-family-data`, ~526 MB used / 5 GB). Legacy `RENDER_DISK_PATH` still points at the same path; do not change the mount.
- ✅ Unset in production: `AUTH_2FA_ECHO_CODE`, `STOREKIT_ALLOW_SANDBOX`, **`COMP_PREMIUM_ALL`** (was `1` — every household was being comped on boot; flag removed. Existing `comp:` SQLite rows may still entitle households until you revoke them via `POST /api/admin/comp`). `ADMIN_USER_IDS` is a single real id.
- ✅ **Stripe live cutover 2026-08-26** — live products/prices + webhook `https://kinrows.com/api/subscription/stripe`; Railway on `sk_live_` / `pk_live_`; `STRIPE_ALLOW_TEST` deleted. Deploy `50fbf719` healthy (`/healthz`, catalog `"stripe":true`). **Funnel (this branch):** confirmation polling, Resend billing emails, portal plan-switch, Lite 10 / Premium 40 chat caps with upgrade 429. **Presentment:** CAD/USD/EUR stickers on the four live prices; Adaptive Pricing elsewhere. **Apple Pay:** live payment-method domains registered (`kinrows.com`, `www.kinrows.com`, `apple_pay=active`); Google Pay also on in the default PMC. **App-first:** paywall Subscribe opens Safari Checkout (`source=app`), public `/open/subscribed` bounces to `kinrows://`, app confirms + foreground refresh. Enable Associated Domains on App ID `com.kinrows.app` in the developer portal so Universal Links sign. Still do one real Checkout purchase after this branch deploys (Safari + Wallet, then return to the app).
- ⏳ Verify the **APNs production** certificate/key and `aps-environment: production` match the distribution build.
- ⏳ **StoreKit / subscriptions**: products configured in App Store Connect matching `services/subscription.js` IDs; test a sandbox purchase end-to-end (verify, entitlement unlock, `/api/subscription/notifications` server-to-server).
- 🔜 Set up basic uptime monitoring on `/healthz` (live probe returns `{"ok":true}` only; TLS 1.3 + HSTS verified 2026-08-26).

## 6. Nice-to-have polish (post-launch OK)

- ⏳ Notification upgrades from the audit: trip pushes to the *household* (not the traveler's own device), rivalry score-update spam throttle, in-context banner suppression (don't notify a DM while that chat is open), `INSendMessageIntent` communication notifications with sender avatars, quick-action categories (reply/approve/check-off). Deep-linking + threading + time-sensitive levels are ✅ done.
- ✅ Concierge `complete_rivalry` now posts the feed celebration + win/loss pushes (parity with the UI button).
- ✅ **Waitlist referral program** (2026-07-11) — each signup gets a shareable `?ref=` code; referring friends moves you up the queue (rank by referrals then signup id). Post-signup card shows position + copy/share link + referral count. `/api/waitlist` returns standing; `/api/waitlist/status` refreshes it. Covered by `test/waitlist-referral.test.js` (5 tests). The higher-leverage conversion lever from the UX research, now built.
- ⏳ iOS unit/UI test target (backend `npm test` is 160 cases; the app has none).
- ⏳ Widgets / Live Activities (coverage "who has the kids now", active-trip next stop) — flagged by UI/UX research.
- ⏳ **Avatar cache invalidation** (from bug sweep, low) — `ProfileImageCache.loadFromHousehold` guards on `images[userId] == nil`, so another member's *new* profile photo isn't picked up until app relaunch/logout even though `fetchGroupMembers` returns fresh base64. Fix: overwrite the cached image when the inline base64 differs, or add an avatar version/hash to the me/group-members payload and refetch on change.
- ⏳ **Coverage deep-link precision** (from bug sweep, low) — `handleDeepLink` maps `coverage`/`coverage_request`/`coverage_confirmed` to the combined list and ignores `ref_id`, so a helper tapping "X needs your help" lands on the list rather than the specific request. Recoverable, but thread `pendingRefId` into the coverage view to scroll to the referenced request.
- ⏳ **Message-notification de-dup race** (from bug sweep, low) — `checkForNewMessages` fires local notifications from two loops (MessageCache.preload on foreground + ContentView.pollUnread's 15s timer) sharing only a UserDefaults dedup set; a genuinely-new DM on foreground can notify twice. Fix: make one owner (pollUnread) fire notifications while preload only warms the cache, or serialize the read+write of `notified_dm_ids` in an actor.

---

### How to use this file
When you finish an item, flip its box to ✅ and note the commit. When you
discover new pre-launch work, add it under the right section with ⏳. Keep the
"human-owned" items (git purge, App Store Connect forms, env/secrets, 2FA
enablement) clearly separated from code that just needs a build.
