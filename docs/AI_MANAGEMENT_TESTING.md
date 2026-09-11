# AI management and Home regression coverage

Validated locally on 2026-09-10 against isolated SQLite databases and an isolated iOS simulator. No production household records were modified.

## Results

- Full backend suite: **371 passed, 0 failed** (`npm test`).
- All **123 actions across 25 model-facing tools** have contract tests, both grouped and direct-handler entry points. Missing required fields, wrong types, invalid enums and unsupported fields fail before database or external operations. This is exhaustive action-boundary coverage, not a claim that every valid natural-language interpretation has been tested.
- **60 routing intents** pass structural validation. `npm run test:ai:routing` also exercises the live model when `ANTHROPIC_API_KEY` is configured. The violin case checks exact time, first date, weekly recurrence and attendee, rather than just the selected tool.
- **iOS app and WidgetKit extension build succeeded**, Debug, iOS Simulator, code signing disabled.
- Visual checks in fictional QA household: pin Budget/Trips, saved Home cards, two-column layout, corrected profile circle, crew-only login artwork, grocery/standard list layouts and check-off, routine archive/history/restore.

## Behavioral coverage

| Area | Verified behavior |
| --- | --- |
| Calendar | Weekly violin at 09:20 for Rowan with full fixture address persists; future occurrences include end date; changing frequency/time preserves other fields; recurrence can be removed; invalid dates/times/rules never write. |
| Recurrence | Long-running daily/weekly series stay visible after 400 occurrences; month-end and leap-day clamping; daylight-saving transition dates. |
| Venues | Saved household addresses, no-household rejection, cited search results, missing citation/provider failure. Public lookup uses the existing Anthropic key; no guessed addresses are represented as verified results. |
| Routine archive | Creator-only; repeated archive/restore is safe; history is unchanged; archived routines disappear from Home sleep tracking and active tool results; reminder reconciliation and hidden logging controls in iOS. |
| History | Dated calendar venue retrieval, merchant and scanned receipt item search, literal wildcard handling, stable pagination, all source queries execute, private notes/routines and other-household receipts excluded. |
| Purchases | Scanned line items come from receipt notes. Checked lists and pantry stock are labeled as weaker evidence. Missing records are not a definite “did not buy.” |
| Home priorities | Ordered persistence per user; invalid/duplicate pins rejected; unpinning works; clan itineraries require actual shared-group access; monthly budget distinguishes no limit, normal pace, ahead-of-pace spending, and over-budget spending, including uncategorized receipts. |
| AI orchestration | Text, voice, and chat-extraction through both regular and streaming paths; multiple tools in one turn; partial failures flagged to model; exhausted tool budgets cannot claim “Done.” |
| Other domains | Existing lifecycle/security tests plus pantry, contacts, recurring payments, notes and trip create/update/read/delete checks. |
| Protocols | Existing developer REST/MCP authentication, scope, transport, isolation and conformance tests remain in the full suite. |

## Limits and follow-up verification

No Anthropic key was available locally, so live natural-language routing, real public venue search and the user's exact school request remain unverified. Model selection cannot be certified by mocked orchestration or schema tests. Run the live routing eval in an environment with the existing key and web search enabled, then verify a full conversation's stored results.

History searches retained records; they cannot reconstruct deleted records, purchases never entered, previous revisions of a list item, or historical budget limits before those limits were changed. Calendar history search returns saved series origins; calendar range listing expands occurrences.

Home priorities drive a snapshot published by the app. The iPhone widget does not independently fetch server data; changes appear after the app refreshes Home and WidgetKit accepts its reload request. Small shows the first pinned card, medium the first two. Accessibility text sizes use a single Home column.

Nothing was deployed in this task. The physical-device/TestFlight build and live household data were not changed.
