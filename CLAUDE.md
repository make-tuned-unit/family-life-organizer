# Kinrows — Claude Agent Guide

## Project Context

**Kinrows** (formerly FamilyLife) is a family-life organizer: a native SwiftUI iPhone app plus the Express/SQLite backend it talks to — **both live in this repo**. Built by Jesse for multi-household use (households, invite codes, cross-household "clans"), with a paid AI Concierge add-on. Public marketing site at kinrows.com (also in this repo under `website/`).

## Layout

```
FamilyLife/                 # iOS app (SwiftUI, iOS 18+, Xcode 16+)
├── App/                    # FamilyLifeApp, ContentView (tab spine), Login/SignUp/TwoFactorView, AppConfig
├── Views/<Feature>/        # 16 feature areas: Calendar, Care, Concierge, Cook, Decisions,
│                           #   Expenses, Family, Gifts, Home, Lists, Messages, Pantry,
│                           #   People, Rivalries, Trips + shared Components/
├── Models/                 # Codable DTOs mirroring API JSON (snake_case) — NO SwiftData anywhere
└── Services/               # APIService (the REST client, ~200 methods), AuthService (device-token
                            #   auth), CalendarService (EventKit), HealthKitManager, HouseholdService,
                            #   LocationService, MessageCache, NotificationService, ProfileImageCache,
                            #   SubscriptionService (StoreKit 2). There is no SyncEngine.

dashboard.js                # Express server — ALL ~190 /api routes live here (route order matters!)
database.js                 # FamilyDB class — promisified sqlite3, schema bootstrap + inline migrations
schema.sql                  # ~50 tables; applied idempotently at every boot
services/                   # anthropic.js, concierge{Chat,Tools,Brief,Context,Nudge}.js,
                            #   subscription.js, appleVerify.js, email.js, rateLimit.js
push.js                     # Raw APNs over HTTP/2 (env-configured, silently off if unset)
test/                       # node --test suites (npm test) — boot real servers on ports 3995-3999
scripts/                    # demo seeds + concierge-tool-eval.js (structural + live tool-routing eval)
website/                    # kinrows.com static marketing site + llms.txt/llms-full.txt
```

- Bundle ID: `com.mylauft.kinrows` · App name: **Kinrows**
- API base: DEBUG → `http://localhost:3456` · RELEASE → hardcoded prod URL (see `AppConfig.swift`; the `server_url` UserDefaults override is DEBUG-only by design)
- Deploy: Render (`render.yaml`); required env vars are documented in `.env.example`

## iOS: the design system is LAW

`FamilyLife/Views/Components/` is a real, complete design system. Never hand-roll what it provides:

- **Typography**: `Font.fl*` semantic scale on Dynamic Type (`flScreenTitle`, `flTitle`, `flHeadline`, `flBody`, `flSubheadline`, `flFootnote`, `flCaption`, `flCaption2`, `flOverline`, `flHero`, `flStat`). **Never hardcode point sizes on text** — icon glyph sizes, monospaced invite codes, and geometry-derived sizes are the only exemptions.
- **Colors**: `WarmPalette` (cream/ink), `AccentTheme`, `TabAccent` (per-feature), `PersonPalette.color(for: fullName)` for per-person identity colors (pass full names to `FamilyAvatar(initial:size:name:)`). App is deliberately light-mode-only.
- **Surfaces**: `.flCard(tint:)` for cards; corner radii ONLY via `DesignTokens.CornerRadius` (card 22 / cardLarge 28 / tile 18 / small 12); spacing via `DesignTokens.Spacing`.
- **Patterns**: `FLScreenHeader(eyebrow:title:subtitle:accent:)` opens every screen; `.buttonStyle(.flCTA)` is THE primary action; `.flCardPress` on tappable cards; `WarmEmptyState` (possibility-framed copy + `actionLabel:` + optional `conciergePrompt:`); `FLLoadingState` instead of bare spinners; `.inlineError(_:onDismiss:)` for failures — never alerts.
- **Icons**: SF Symbols only, one canonical symbol per feature (calendar/list.bullet.rectangle/house/creditcard/sparkles/chart.bar/flag.2.crossed/person.2/arrow.triangle.swap/fork.knife/note.text/airplane/cabinet/gift/bubble.left.and.text.bubble.right/gearshape). `.fill` in selected/accent chips, outline in content.

## Backend rules

- Every `/api` route: `requireAuth` + a household/owner guard (`requireHouseholdRow`, `requireGroupRow`, `requireListAccess`, `requireItineraryAccess`, `requireContactOwner`, `userOwnsContact`, `usersShareGroup`). Cross-household leakage is the #1 bug class here.
- All SQL parameterized; dynamic updates go through per-table `ALLOWED` column sets in `database.js`.
- Money inputs must pass through `parseMoney()` (SQLite stores strings; `SUM()` silently drops them).
- Auth: rotating device refresh tokens (`auth_tokens`, SHA-256 at rest, grace window via `AUTH_TOKEN_GRACE_SECONDS`); email 2FA behind `AUTH_2FA_ENABLED=1`. The iOS app never stores the password.
- The AI concierge (`services/conciergeTools.js`): fine-grained handlers routed through ~22 domain tools with an `action` enum; load-time assertions enforce full, non-duplicated routing. New capability = new handler + register in `GROUPS`. Every write handler must scope through `ctx.groupId`/`ctx.userId` guards (`assertHousehold`, `assertListAccess`, …). Update `scripts/concierge-tool-eval.js` cases when adding intents.

## Working instructions

1. **Verify on the backend, parse-check on iOS.** `npm test` boots real servers (24+ tests) — run it after any backend change. The iOS app compiles only in Xcode (this dev machine may lack it); at minimum run `xcrun swiftc -parse` on every touched Swift file.
2. **Commit after each feature** — one feature = one commit, descriptive messages.
3. **Every view gets a `#Preview`** with mock data.
4. **Handle errors inline** (`.inlineError` house style), never modal alerts.
5. **No third-party dependencies** on either side unless strictly necessary (backend deps: express, sqlite3, bcryptjs, helmet, connect-sqlite3 — keep it that way).
6. **Route order matters in dashboard.js** — specific paths before `/:param` siblings (e.g. `/api/budget/stats` before `/api/budget/:month`).
7. **iPhone first**; iPad is secondary.
8. Docs: `docs/PRD.md` (vision), `docs/SECURITY_AUDIT.md` + `docs/PROD_READINESS.md` (posture/checklists — keep them current when you change auth/security).
