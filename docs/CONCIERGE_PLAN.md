# AI Life Concierge — Plan

> Status: proposal · Last updated: 2026-06-17
> Decisions locked: **per-household billing**, **hybrid AI (server Claude + on-device FoundationModels)**.

## 1. Vision

A paid "AI life butler" tier layered on top of the existing Family Life Organizer. The free app
works exactly as it does today. The paid tier adds a **Concierge** that organizes the household's
information across every feature and collapses 143 endpoints / 5 tabs into one coherent
conversation. It:

- **Briefs you** — a warm, prioritized "here's your family right now" digest.
- **Does things for you** — natural-language front door to every feature (writes via tool-calling).
- **Keeps you on top of things** — proactive nudges when something needs attention.

The butler is **not a new data feature** — it is an orchestration + personality layer over the
endpoints and tables that already exist.

## 2. What exists today (audit baseline)

| Layer | Reality |
|---|---|
| Backend | Express + SQLite, ~143 REST endpoints, 25 tables, group-scoped (`group_id`) isolation |
| Domains | Tasks, Calendar, Groceries, Pantry, Recipes, Receipts/Budget, Projects, Rivalries (HealthKit), Decisions, Feed, Gifts/Events, Trips/Itineraries, Care Cascade, Messaging, Location/Presence, Household graph |
| iOS | SwiftUI, tabs Calendar/Lists/Home/Budget/More, `@Observable` MVVM, single `APIService`, Liquid Glass design system |
| AI live | Claude Sonnet 4 server-side; receipt scan (`dashboard.js:1604`) + recipe suggest (`dashboard.js:1859`); graceful fallback without key |
| Consent | `AIConsentManager` + `AIDisclosureView` (App Store 5.1.2(i) compliant) — already built |
| Scaffold | `AskAIButton.swift` + `AIContext` enum exists, wired only to Cook — ready to extend |
| Reusable infra | APNs push (`push.js`), Gmail receipt ingestion, location/presence, HealthKit sync |

**Blocking gaps:**
1. **No monetization** — no StoreKit/Stripe, no entitlements, no tier flag on `users`.
2. **No orchestration** — current AI is one-shot prompt→JSON; butler needs tool-calling + memory + a proactive loop.

## 3. Architecture

### 3.1 Hybrid AI split

| Runs where | Used for | Why |
|---|---|---|
| **Server — Claude Sonnet 4 + tool use** | Actions (writes), cross-feature reasoning, the daily brief, anything touching multiple domains | Tool-calling over the existing API; reasons across all household data |
| **On-device — Apple FoundationModels (iOS 26+)** | Quick private summaries, draft text, on-the-fly rephrasing, offline "what's on today" from cached data | Privacy, latency, zero token cost; degrades gracefully on unsupported devices |

Default to server for anything that reads broad family data or writes. Use on-device only where the
input is already on the phone and privacy/latency win. The on-device path is additive — Phase 5+, not
required for launch.

### 3.2 Server orchestration layer

```
iOS Concierge tab
   └─ POST /api/concierge/chat   { message, conversation_id }
        │
   Concierge Service (new module: concierge.js)
        ├─ load context: group_id, members, recent activity
        ├─ load butler memory (concierge_memory rows)
        ├─ Claude Sonnet 4 with TOOL DEFINITIONS mapped to existing routes:
        │     get_calendar, add_appointment, list_tasks, add_task,
        │     get_budget, list_pantry, suggest_recipes, open_decision,
        │     request_coverage, get_gifts, add_gift_idea, send_message ...
        ├─ executes tool calls via extracted service functions (no HTTP round-trip)
        └─ returns assistant message + structured "action cards"
```

### 3.3 The key refactor (Phase 0)

Route handlers are currently inline in `dashboard.js`. Extract business logic into plain callable
functions (e.g. `services/appointments.create(groupId, payload)`) that **both** the Express route and
the concierge tool layer call. This is the single biggest enabler and is reused everywhere.

### 3.4 New tables

- `concierge_memory` (id, user_id, group_id, kind, content, created_at) — durable facts the butler
  learns; user-viewable/clearable. (Mirror the existing generic `memory` table pattern.)
- `concierge_conversations` / `concierge_messages` — chat history per household.

### 3.5 Briefing generator

`GET /api/concierge/brief` — server gathers a structured snapshot (overdue tasks, next 7 days
calendar, open decisions, budget vs limit, expiring pantry, upcoming birthdays without gift ideas,
pending coverage), Claude turns it into a warm prioritized digest + action cards. Cache per-day,
regenerate on demand.

## 4. Per-feature integration map

Each domain gets a proactive **butler verb** and a conversational **tool**. Priority top-down:

| Domain | Proactive | Tool |
|---|---|---|
| Calendar | "3 events this week; Thu 3pm overlaps Sophie's work block" | create/move/cancel appts |
| Tasks | surfaces overdue + suggests assignee | add/complete/reassign |
| Pantry → Cook | "Milk + chicken expire in 2 days → 2 recipes" (chains existing recipe AI) | "what can I cook tonight" |
| Budget/Receipts | "80% through Groceries, 10 days left" | "how much on dining this month?" |
| Decisions | "Poll open 5 days, Sophie hasn't voted — nudge?" | open a decision from a sentence |
| Gifts/Events | "Rowan's birthday in 9 days, no idea logged" | add gift idea, set reminder |
| Trips/Itinerary | "Trip in 14 days, no accommodation booked" | plan stays, flag gaps |
| Care Cascade | "Need coverage Thu — ask Helen & Tom?" | fire coverage request to contacts |
| Rivalries | "2k steps behind Sophie, 4h left" | start/log/standings |
| Feed | drafts a post for milestones (rivalry win, trip) | post on your behalf |

Fully realizes the half-built `AskAIButton` / `AIContext`: every feature view gets a contextual
"Ask the butler" entry that deep-links into the Concierge with that screen's context preloaded.

## 5. iOS Concierge tab

New tab between Home and More. Reuses the design system (AmbientBackground `.concierge`,
FamilyAvatar, WarmChip, FLCardModifier):

- **Top:** today's brief as warm prose + a row of action cards (tap = pre-filled task/appt/vote, one confirm).
- **Middle:** "Needs you" — the proactive prompts list ("prompting you to fill things out / stay organized").
- **Bottom:** chat composer (adapt existing `ChatSheet` infra).
- Butler has a persona (warm tone matching terracotta/sage); let the family name it.

Wiring: add `MainTab.concierge` (ContentView:5), `TabAccent.concierge` (DesignTokens.swift), route in
`tabView(for:)` (ContentView:341), accent in `accentColor(for:)` (ContentView:388), new
`Views/Concierge/`. **Must hand-edit `FamilyLife.xcodeproj/project.pbxproj`** for every new file
(no automatic file discovery).

## 6. Monetization — per-household

**StoreKit 2 auto-renewable subscription** (App Store native; no Stripe needed for current distribution).

- `users` gains `tier`, `subscription_expires_at`, `subscription_origin`. Entitlement resolved at the
  **household (`group`) level**: one paying seat unlocks the butler for the whole group.
- iOS: StoreKit 2 `Product.products` + `Transaction.currentEntitlements`; on purchase POST signed
  transaction to `/api/subscription/verify`, which validates with Apple and flips the household tier.
- Server `requirePremium` middleware on all `/api/concierge/*` routes; proactive engine runs only for
  premium households.
- iOS `AppConfig.isConciergeEnabled = household entitlement active`. Free users see the tab with a
  paywall preview — offer one free brief/week as a conversion teaser.

## 7. Proactive engine

Scheduled job runs gap-detector queries (expressible as SQL over existing tables), ranks findings, and
for premium households sends APNs nudges via `pushToUser`/`pushToGroup`. Each nudge deep-links into the
Concierge (extend `DeepLinkRouter` with a `concierge` case). Throttle hard (max N/day) to avoid nag fatigue.

## 8. Privacy & consent

Extend `AIConsentManager` / `AIDisclosureView`. The butler sends far more family data to Claude than
Cook does, so the disclosure must be broader and explicit, plus a **data-scope toggle** (what the butler
may read). Keep "not stored after response" true except the explicit `concierge_memory`, which the user
can view and clear. On-device summaries stay on-device — call that out as a privacy win.

## 9. Phased roadmap

| Phase | Scope | Outcome |
|---|---|---|
| **0 — Refactor** | Extract route logic into callable service functions | Unblocks tool-calling; no user-facing change |
| **1 — Read-only brief** | `/api/concierge/brief` + Concierge tab with daily digest + action cards (deep-link to existing forms, no write tools) | Fast value, low risk |
| **2 — Conversational + tools** | `/api/concierge/chat` + calendar/tasks/budget/pantry tools + memory table | The butler can act |
| **3 — Monetization** | StoreKit 2, household entitlements, paywall, gating | Paid tier live |
| **4 — Proactive engine** | Gap-detector + throttled APNs nudges | "Needs you" prompts |
| **5 — Full coverage + hybrid + polish** | Remaining tools, on-device FoundationModels summaries, "Ask the butler" across all views, persona polish | Complete experience |

## 10. Risks / open items

- **Tool fan-out cost** — broad context per chat turn burns tokens; cache the brief, scope tool reads, consider prompt caching.
- **Write safety** — model-initiated writes need confirm-before-commit on destructive/ambiguous actions (action cards = the confirm step).
- **FoundationModels availability** — gated on iOS 26 + supported hardware; always have a server fallback.
- **Nudge fatigue** — strict throttling + user controls.
- **Household entitlement edge cases** — what happens when the paying member leaves the group; define downgrade behavior.
