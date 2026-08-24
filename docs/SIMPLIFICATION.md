# Simplification review — "simple and powerful"

_Audit of every user-facing capability as of 2026-08-24, with the merges that
would make Kinrows feel like one product rather than nineteen. Items marked
**done** shipped with the chores feature; the rest are ranked proposals._

## The problem in one number

A new user currently meets **~19 nouns** before the app makes sense: Task,
List, Event, Receipt, Budget Category, Project, Recurring Payment, Decision,
Rivalry, Person, Milestone, Key Date, Gift Idea, Routine, Coverage Request,
Trip, Itinerary, Note, Post — before Contacts, Groups, Households and Pantry
Items. The tab bar shows five icons but the real root surface is eight (five
tabs + a hidden Concierge tab + two floating buttons). "More" holds eleven
rows, and the two heaviest screens in the app (Household, Family Groups) were
hidden three levels down behind a gear icon.

## Surface today

**Tabs:** Calendar · Lists · Home · Budget · More (+ hidden Concierge tab, chat
bubble, push-to-talk button).

**More → Family:** Household _(new)_ · Decisions · Rivalries · People · Coverage · Routines
**More → Household:** Pantry & Cook _(merged)_ · Notes · Travel
**More:** AI Concierge · Settings

## Done in this pass

| # | Change | Why |
|---|--------|-----|
| ✅ | **Cook folded into Pantry.** Cook has zero tables and two routes — it is a question asked of the pantry. It is now a "What can I make?" card at the top of Pantry, and the More row reads "Pantry & Cook". | One fewer top-level concept, zero lost capability. |
| ✅ | **Household promoted to the top of More.** | Onboarding already said "More → Household"; the path didn't exist. |
| ✅ | **Chores built _inside_ Routines and surfaced on the child's People card + Home**, rather than as a new More row or a new noun. | The audit's strongest pattern: People already absorbed Gifts as a section. Chores follow it — one chores routine per child, shown where the child lives, ticked from Home. |

## Proposed, ranked by impact ÷ risk

1. **Fold Notes into Lists** (high impact, low risk). Notes is a whole More row
   for "a title and a body"; `FamilyListsView` already has a synthetic "Tasks"
   chip — a "Notes" chip is the same trick. Needs a privacy affordance because
   `notes.shared_scope` has no analogue in `lists`. Files:
   `FamilyLife/Views/Lists/FamilyListsView.swift`, `Views/Home/NotesView.swift`.
2. **Delete the orphaned Gifts trio** (`Views/Gifts/PersonGiftListView.swift`,
   `AddGiftPersonView.swift`, `AddSpecialEventView.swift`) and the dead body of
   `Views/Care/IncomingCoverageView.swift`. No call sites outside `#Preview`.
   Needs matching `project.pbxproj` edits — do it in Xcode.
3. **Decisions become posts with a poll** (high impact, medium risk). `decisions`
   and `feed_posts` are the same shape plus `poll_options`; the Home "+" menu
   offers "New Post" _and_ "New Decision", forcing a taxonomy choice before
   the user has typed a word. One composer with an "add poll" toggle;
   `DecisionsView` becomes the feed filtered to polls. Touches 16 routes and
   two concierge groups, and decisions are deep-linked — do it as its own
   release.
4. **A single Family hub** (Household / Groups / People segments, the
   `TravelHubView` pattern) so Family Groups (1,124 lines) stops living under
   Settings. Household is now one tap away; Groups still isn't.
5. **One gamification engine.** `routines(activity)` computes cumulative
   milestones + a non-punitive weekly streak (`services/routineAchievements.js`);
   `rivalries` computes points, leaderboards and XP over name strings. Unify the
   presentation first (one streak/leaderboard card), then consider rivalries as
   "a routine with more than one subject."
6. **One mental model for "add."** Four competing add affordances (Home "+"
   menu, per-screen "+", the concierge ask-bar, push-to-talk). The sheets are
   reused correctly; the user just has no rule for where to add things. Proposal:
   Home "+" always; per-screen "+" only where the screen _is_ the thing.
7. **Fix the tasks backend.** No `POST /api/tasks` (creation goes through the
   legacy `/api/add`), `assigned_to` is a bare string, `recurrence_pattern` is
   stored but never expanded while `appointments` has a working
   `expandRecurrence()`. Not user-visible, but every future "assign this to a
   kid" feature trips over it.
8. **Docs.** `docs/PRD.md` still describes a two-user web app; `docs/FLOW_MAPS.md`
   documents a `GiftsView` that no longer exists and omits Routines, People,
   Care, Notes, Concierge. `docs/ROADMAP.md`'s "Now" item — _reduce root-tab
   overload_ — is still the right one.

## Why chores did NOT become a `tasks` feature

The audit considered building chores on `tasks` + `gift_people`. It would have
needed three backend fixes first (child FK, recurrence expansion, a POST route)
and still had no allowance ledger, no age program, and no privacy model. The
`routines` model already had all of it: a subject with a birthdate resolved from
People, private/shared scope, a history table, a static sourced program pattern
(sleep training), a Home surface (the sleep bar), and a concierge group. Chores
reuse every one of those — which is the same "combine, don't add" principle
this document is arguing for.
