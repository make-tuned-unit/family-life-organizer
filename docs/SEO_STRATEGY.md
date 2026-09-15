# Kinrows — SEO / AEO / GEO Strategy

Owner: Jesse · Last reviewed: 2026-09-15 · Status: living document

This is the plan for organic acquisition: capturing high-intent Google searches and being
discoverable, understood and cited by AI answer engines. The site is treated as product
infrastructure, not a content farm. Companion docs: `docs/SEO_IMPLEMENTATION_DAG.md`
(atomic tasks + gates), `docs/SEO_OPPORTUNITIES.md` (Search Console feedback loop),
`docs/seo/research/` (verbatim complaint mining), `seo/README.md` (the page engine).

---

## 0. Inputs

| | |
|---|---|
| Product | Kinrows — private all-in-one household organizer (iPhone, iOS 18+) with optional paid AI Concierge |
| Website | https://kinrows.com (static HTML in `website/`, served by Express in `dashboard.js`) |
| Markets | English-speaking: US, Canada, UK, Australia (copy uses Canadian/UK spelling "labour") |
| Primary conversion | **Waitlist signup** (`POST /api/waitlist`) until App Store launch; then App Store install; then Concierge subscription (`/subscribe`) |
| Primary users | Parents and couples running a shared household; the person carrying the "mental load"; multi-household families (grandparents, co-parents, "clans") |
| Competitors | Cozi, FamilyWall, TimeTree, Skylight, OurHome, AnyList, Maple, Hearth; and the defaults: Google Calendar, Apple Reminders/Family Sharing, WhatsApp/iMessage group chats |

---

## 1. Technical SEO audit (state on 2026-09-15, before this work)

**What already worked**
- Static server-rendered HTML; every page fully indexable without JS.
- Unique `<title>`, meta description, canonical, OG/Twitter tags on every page.
- JSON-LD: Organization + WebSite + MobileApplication on home; BlogPosting + BreadcrumbList (+FAQPage/HowTo) on posts; ItemList + FAQPage + BreadcrumbList on roundups.
- `robots.txt` explicitly welcomes AI crawlers (GPTBot, ClaudeBot, PerplexityBot, …) and blocks only `/app`, `/login`, `/api/`, `/c/`.
- `llms.txt` + `llms-full.txt` published; `speakable` markup on articles.
- Strict CSP on marketing HTML; first-party analytics (Permagent) with no third-party tags.
- Four honest roundup pages (`/best-family-organizer-apps`, `/best-family-calendar-app`, `/best-chore-app-for-families`, `/best-shared-shopping-list-app`) and a `/compare` page already exist.
- Hero LCP image preloaded; fonts preconnected.

**Gaps found**
| # | Gap | Impact | Fix (DAG task) |
|---|-----|--------|----------------|
| 1 | Canonicals and internal links use `.html` (`/compare.html`) while `/compare` also resolves → two URLs per page, no redirect | Duplicate URLs, split signals | T2 clean URLs + 301 |
| 2 | One hard-coded Express route per page; adding a page needs a code change | No scalable page model | T2 generic resolver |
| 3 | No content model or generator; every page hand-written | Cannot scale without slop or drift | T1 `seo/` engine |
| 4 | Sitemap hand-maintained; no `lastmod` discipline | Stale crawl hints | T1 generated sitemap |
| 5 | No 404 page; unknown paths fall through | Soft-404 risk, poor UX | T2 branded 404 |
| 6 | Waitlist signups record `source` (form) but not landing page | Cannot compute conversions per page / per intent class | T3 `landing_path` + `waitlist_signup` event |
| 7 | No organic reporting; no Search Console integration | Blind to impressions/CTR | T3 `scripts/seo-report.js`; T9 GSC loop |
| 8 | Pages are roundups/blog only — no problem, alternative, vs, persona or question pages | Missing the highest-intent query classes | T5–T8 initial 40 pages |
| 9 | Hubs absent → new pages would be orphans | Crawl/indexing depth | T1 hub pages + footer links |
| 10 | `og-card.html` indexable helper page | Low-quality URL in index | noindex |
| 11 | No localization/hreflang (single `en`) | None now; revisit if `en-GB`/`en-AU` variants ever differ | — |
| 12 | Blog canonical `/blog/` OK; post URLs `.html` | See #1 | T2 |

Rendering: pure static HTML, so SSR/SSG concerns do not apply. Core Web Vitals: light pages, one CSS file, fonts from Google (render-blocking stylesheet; acceptable, `display=swap`). Images: PNG screenshots — lazy-load below the fold.

---

## 2. Product / search-intent analysis

Jobs-to-be-done the product serves, mapped to the five intent classes:

| Job | Problem page (how-to) | Alternative / vs | Persona | Question |
|---|---|---|---|---|
| Keep everyone on one calendar without nagging | share a family calendar with a partner who won't use apps | Cozi/TimeTree/Google Calendar alternatives | couples, blended families, grandparents | "why doesn't my shared calendar show on my partner's phone" |
| Get the mental load out of one head | share the mental load with a partner | FamilyWall alt | the default parent | "what is the mental load" (blog exists) |
| One shopping list that actually syncs | shared grocery list without a group chat | AnyList alt | couples | "how to share a grocery list on iPhone" |
| Know what food is in the house | stop wasting food with a pantry list | — | busy parents | "how long does X keep" |
| Cook from what you have | plan meals from what's in the fridge | — | parents of picky eaters | "what can I make with…" |
| Kids pitch in, allowance is fair | age-appropriate chores without a chore-chart war | OurHome alt | parents of 5–12s | "how much allowance by age" |
| Cover care without 30 texts | arrange a babysitter/grandparent cover in one tap | — | working parents | "what information to leave for a babysitter" |
| Sleep-train with a plan | baby sleep schedule by age | — | new parents | blog exists |
| Money without friction | track family spending as a couple | — | couples | "how to split expenses with partner" |
| Two households, one family | organize two households / co-parenting | Cozi alt for co-parents | co-parents, grandparents | "best app for co-parenting schedule" |
| An assistant that does the admin | run the household with an AI assistant | — | the overwhelmed organizer | "is there an AI that can manage my family calendar" |

Positioning that must hold on every page: **private (no ads, no data sale, no AI training on your data), all-in-one, and the Concierge actually takes actions**. Launch status must be stated truthfully: "free on iPhone, launching September 2026; join the waitlist".

---

## 3. Customer complaint research

See `docs/seo/research/` (verbatim quotes, sources, dates — nothing fabricated).
Summary tables: `SUMMARY-A.md` (Cozi, FamilyWall, TimeTree, Skylight) and `SUMMARY-B.md`
(OurHome, AnyList, Maple, Hearth, Picniic, Google/Apple/group-chat defaults, and the
question/problem language). The ranked clusters are reproduced in §5.

**Research limitation:** every quote below traces to `docs/seo/research/`. Most verbatim evidence is Apple App Store customer-review RSS (US storefront, pages 1–2, fetched 2026-09-15) — this table is therefore **App-Store-review-weighted**, not a full social-listening picture. `reddit.com` fetches were blocked by the research tool's sandbox and web search did not reliably surface indexable Reddit thread text; where a Reddit quote appears it is via a secondary source (e.g. uninfluencedreview.com) and is flagged as such. OurHome, Picniic and Maple returned few or zero retrievable App Store reviews, so their rows lean on paraphrased secondary-source evidence — flagged in the source files as "paraphrased, not verbatim."

Merged and ranked from `SUMMARY-A.md` (Cozi/FamilyWall/TimeTree/Skylight) and `SUMMARY-B.md` (OurHome/AnyList/Maple/Hearth/Picniic/defaults/question language):

| Rank | Cluster | Representative verbatim phrase (competitor · source) | User type | Intent | Kinrows capability | Page type | Conversion potential |
|---|---|---|---|---|---|---|---|
| 1 | Paywall / subscription gates core or basic functionality | "Requires $80/yr subscription to use" (Cozi, App Store 2★) | Budget-conscious parent | Switching | Free core app for the whole household; only optional Concierge is paid | alternative, compare | High |
| 2 | Forced/unwanted AI feature that trains on your data | "Former user deleting account over AI concerns, noting calendar data trains the AI regardless of opt-out" (TimeTree, App Store 1★) | Long-tenure, privacy-conscious couple/family | Switching (account deletion) | "No ads, no data sale, no training of AI models on your content" (llms-full.txt); Concierge is opt-in and paid, never forced | alternative, question | Very high |
| 3 | Real-time sync silently breaking, causing duplicate work or missed events | "Purchased items are crossed off the list on one phone but still appear as unpurchased on the other" (AnyList, App Store 2★, 2026-07-25) | Couple/family sharing a grocery list | Troubleshooting → switching | Lists — server-scoped, household-scoped shared lists, automatic categorization | howto, question | High |
| 4 | Shared calendar/app doesn't work if the partner won't buy in | "If your husband won't use a free shared calendar, why would he use the expensive shared calendar?" (Reddit comment, reported via uninfluencedreview.com — secondary source, not independently verified) | The mental-load carrier | Informational / adoption-skepticism, pre-purchase | Native shared household calendar (not permission-sharing a personal one) + two-way phone-calendar sync so a reluctant partner's existing events show up unchanged | howto, question | High |
| 5 | App crashes / breaks after an update | "App keeps crashing after latest update. So annoying!" (FamilyWall, App Store 1★) | Paying subscriber | Switching (includes "scam" framing from paying customers) | No citable crash-rate claim; native SwiftUI engineering discipline is context, not a documented guarantee | alternative | High |
| 6 | Expensive hardware plus an ongoing subscription "cash grab" | "Don't see the value of paying for an annual subscription for such an inferior implementation" (Skylight, App Store 2★); "Such a waste of money and scam" re: to-dos locked behind a lapsed subscription (Hearth Display, App Store 1★, 2025-08-25) | Parent who already sunk $170–$700 into hardware | Switching / buyer's remorse | Free core app, no hardware purchase required; Concierge is a clearly optional $4.99–$9.99/mo add-on, not a second toll on something already bought | alternative, howto | High |
| 7 | Subscription required just to add another family member | "Complains about requiring paid subscription to add even one additional family member for basic features" (FamilyWall, App Store 1★) | Parent onboarding the whole household | Switching | Free core is per-household, unlimited members; one Concierge subscription (if purchased) covers the whole household | alternative | High |
| 8 | Ads on the free tier / paywall to remove them | "The ads at the top make the overall calendar hideous. Money hungry app" (TimeTree, App Store 1★) | General household user | Switching | No ads anywhere in the free core app | alternative | Medium-high |
| 9 | Broken onboarding: can't invite family members, join or leave a group | "Would not let me invite my family members or even join other circles... Would not recommend" (FamilyWall, App Store 1★) | New user onboarding the family (first-run failure) | Switching (immediate abandonment) | Household invite codes + separate "clan" groups that only overlap through shared members | alternative, howto | High |
| 10 | Well-funded family apps quietly shutting down, stranding users | "The app has been discontinued, and the site no longer works" (Picniic, paraphrased secondary-source summary — not a direct quote) | Early-adopter who invested setup time | Navigational → comparison ("what happened to X") | Actively maintained single app identity; not a documented "will never shut down" guarantee — position on trust, not permanence | alternative | Medium (low volume, near-zero competition) |
| 11 | Family group chats become unmanageable noise that buries logistics | "A survey ... found that 40% of respondents indicated they were overwhelmed by group chat messages and notifications" (statistic, paraphrased via WebSearch aggregation); viral anecdote of a father "leaving his family group chat" (reported by gulfnews.com and others) | Any family member trying to extract a decision from scroll-back | Venting / seeking a better system | Messages (DMs + group chats with quoted items — share a list/event/decision into a chat) + Decisions (structured polls) as a non-chat home for logistics | howto | High |
| 12 | "What to leave the babysitter/grandparent" served only by static printables | "Free Printable Babysitter's Information Guide" (recurring search-result title pattern across 6+ sources) | Parent/caregiver preparing to be away | Transactional (wants a fill-in-the-blank sheet) | Care coverage (proposed time windows, approved via share link, no app needed for the helper) + shareable Notes + People profiles | howto, question | High |
| 13 | Chores/allowance searched by exact age band; apps answer with static price charts, not per-child guidance | "$0.50 to $1.00 per task for ages 6 to 8," "$1.00 to $2.50 for ages 9 to 11" (age-banded price phrasing, aggregated search titles); "should you tie allowances to chores" (Substack essay title, verbatim) | Parent of a 5–12-year-old | Informational, commercial-adjacent | Age-banded chores program (2–3/4–5/6–8/9–12/13+) with a fixed weekly allowance never docked for a missed chore, grounded in cited research (Rossmann 2002; White et al. 2019; Warneken & Tomasello 2008; Deci, Koestner & Ryan 1999) | question, howto | High |
| 14 | Privacy/data-sale concerns as a late-funnel trust check | "Personal information is sold or rented to third parties ... personalized advertising is displayed" (Common Sense Privacy Evaluation, re: Cozi) | Household comparing shortlisted apps before committing family data | Informational / trust research, late-funnel | "Private by design. Each household's data is isolated at the database level ... No ads, no data sale, no training of AI models on your content" (llms-full.txt) | alternative, compare | Medium-high |
| 15 | Data loss / sync failure that wipes out important dates | "TimeTree deleted all of it! Years of important dates ... all gone!" (TimeTree, App Store 1★) | Parent/couple relying on the calendar for medical/legal dates | Switching (severe trust breach) | Server-scoped, parameterized-SQL persistence and two-way device sync — cannot promise zero data loss; position on trust and architecture, not a guarantee | howto, alternative | High (handle carefully — do not overclaim) |

Two clusters dominate across both summaries: **paywalls on basic functionality** (every major competitor, different flavors) and **forced/unwanted AI with data used for training** (concentrated in TimeTree — five reviewers used explicit "deleting the app" language within about six weeks). Both map directly onto stated Kinrows differentiators. Reliability (crashes, data loss, broken invite flows) is the third major theme.

---

## 4. Competitor analysis

All claims sourced to `docs/seo/research/complaints-*.md` and `default-tools.md`. "Where Kinrows should NOT claim to win" is mandatory reading before writing any alternative/compare page for that competitor.

| Competitor | Who it's good for | Genuine strengths | Recurring complaints | Comparison searches that exist | Where Kinrows materially differs | Where Kinrows should NOT claim to win |
|---|---|---|---|---|---|---|
| **Cozi** | Long-tenure parents of school-age kids wanting a simple, trusted, free-first shared calendar + lists | Dependable core calendar/lists relied on daily for years; some reviewers credit it with "saving my marriage"; strongest brand recognition in category | Paywall creeps onto basic functions (30-day view limit, "$80/yr" cited); login/widget failures; iOS vs Android look/behave differently; "used to be great" loyalty erosion + unwanted AI push | "Cozi vs Skylight," "Cozi vs TimeTree," "Cozi vs FamilyWall," "Is Cozi Gold worth it," "Cozi alternatives" — all established, multi-blog SERP patterns | Entire core app free (not just calendar/lists) with no 30-day/feature caps; Concierge AI is opt-in, never pushed; no ads | Cross-platform reach (Cozi ships Android, Kinrows is iPhone-only); 10+ years of install base and brand trust; meal-planner/recipe-box maturity |
| **FamilyWall** | Families wanting one broad "family hub" (calendar + tasks + photos + location + finance + messaging), notably strong for elder-care coordination | Broad feature surface genuinely useful for multi-generational households when it works; explicit 5★ elder-care testimonial | Dominant crash/instability cluster (recipes, grocery list, calendar all crash post-update, including from paying "scam"-framing subscribers); subscription required to add even one more family member; broken invite/"Circle" join-and-leave flow; confusing onboarding | "FamilyWall vs Cozi" (multiple independent blogs), "Is FamilyWall really free?" | Free for the whole household including every member; no reports (yet) to compare against on stability — do not claim a crash-rate advantage without evidence beyond "not FamilyWall" | Photo-album depth, location-sharing maturity, or elder-care-specific feature depth — FamilyWall's elder-care praise is a genuine, cited strength |
| **TimeTree** | Couples and small families wanting a free-first, ad-supported, pure scheduling app with per-event chat | Long-tenure users (4–6 years) credit it with improving household communication and even relationship/mental-health outcomes | The single most concentrated complaint cluster in the whole research set: forced AI that trains on calendar data despite opt-out attempts (5 near-identical 1★ deletions in six weeks); ads; catastrophic data loss ("deleted everything," "years of important dates ... all gone"); no calendar export/lock-in; billing/cancellation friction | "TimeTree vs Cozi" (8+ independent blogs) | "No training of AI models on your content" is explicit and documented (llms-full.txt); Concierge is paid/opt-in, never forced; two-way phone-calendar sync avoids lock-in | Cannot promise zero data loss — position on architecture/trust, not a guarantee; TimeTree's per-event chat/comment feature has no direct Kinrows equivalent (Kinrows has Messages + Decisions instead, a different shape) |
| **Skylight** | Families wanting an always-on physical wall display as the shared hub, not another phone app | Third-party reviews (4.7/5, 845 reviews per one cited source) credit it with centralizing multiple kids' schedules and calming planning after months of use | "Cash grab": $170–$630 hardware plus a ~$79/yr subscription for meal planning/chore rewards; buggy, laggy, unintuitive companion app (duplicate items, no admin interface); restrictive 2-notification cap; work-schedule (QGenda) incompatibility; "not user friendly" for less tech-savvy family members | "Is Skylight Calendar worth it?" (cybernews, tasteofhome, theeverymom, decoratorsvoice — same framing across 4+ sites), "Skylight vs Cozi," "Hearth vs Skylight" | No hardware purchase required; the phone app *is* the product, not an afterthought bolted onto hardware; Concierge pricing is a clean optional add-on, not a second toll on a sunk cost | The always-visible, ambient wall-display experience itself — a phone app cannot replicate a kitchen-counter screen; Skylight's multi-kid schedule centralization is a genuine, cited strength |
| **OurHome** | Families wanting a free, simple chores-and-rewards app with points/gamification | Combines chores + shopping + calendar for free; was praised as "App of the Week" for gamified chore tracking in its heyday | Original listing appears delisted/abandonware ("no updates recorded since 2022"); points/rewards sync breaks between phones, killing kids' motivation; confusing duplicate "OurHome" listings from different developers | "OurHome alternatives" (25+ listed on alternativeto.net), "What happened to the OurHome app in 2026?" (choresplit.com) | Actively maintained; a single stable app identity; server-validated chores/allowance ledger | Cannot claim years of gamification-UX polish OurHome built up in its active period — most evidence here is paraphrased/secondary, not verbatim, so keep claims modest |
| **AnyList** | Couples/families wanting a mature, well-regarded grocery-list-and-recipe-manager specifically (no calendar, budget, pantry-expiry, or chores) | Long track record; strong recipe-import feature; widely recommended as "the" shared grocery list app | Real-time sync periodically breaks the core "shared list" promise (duplicate purchases, "wasted money," items flickering/disappearing); lost Alexa/lock-screen-widget integration; can't reliably delete crossed-off items across iPhone/Mac; broken ChatGPT recipe import | "AnyList vs Kinrows Cook" is a defensible narrow angle (per research); general "shared grocery list app that syncs" queries | Lists are one part of a whole-household system (calendar, pantry, budget, chores together), not a single-purpose grocery app; Cook generates recipe ideas from actual pantry inventory rather than importing external recipes | Recipe-import maturity and Alexa/smart-home integration — Kinrows has neither; AnyList's narrow focus is a genuine strength for shopping-list-only households |
| **Maple** | Families wanting AI-assisted "email inbox that turns into tasks" plus calendar/chores/meal-planning/notes in one app | Closest AI-assistant positioning to Kinrows' Concierge; broad feature breadth similar to Kinrows' "everything in one place" pitch | New paywalls on previously-free features (bait-and-switch trust erosion); setup friction with data/configuration disappearing; glitchy performance; no widgets | "Maple vs Cozi" (implied by comparison framing), "Is Maple family assistant worth paying for" | Core app is free permanently — only the optional Concierge layer is paid, never a feature that was free and got paywalled later | Most Maple evidence is paraphrased, not verbatim (App Store RSS returned zero entries) — do not overstate the comparison's evidentiary strength; Maple's email-to-task conversion has no direct Kinrows equivalent |
| **Hearth Display** | Families wanting a $700 wall-mounted display plus SMS AI assistant ("Hearth Helper") that consolidates whiteboards and multiple calendars | AI photo-import of events praised as a genuine time-saver; effective at reducing kids' nagging when task lists work; reduces reliance on scattered whiteboards | Core to-do functionality stops working once the ~$84/yr subscription lapses after a $700 purchase ("scam," "waste of money," "most expensive picture frame"); wall unit and companion app "do not speak to each other"; missing widgets/multi-alert/voice/smart-home; adoption problem if a partner won't engage regardless of hardware | "Hearth Display vs Skylight," "Is Hearth Display worth it/worth $700?" | No hardware purchase, ever; nothing "stops working" behind a lapsed subscription because the free core app has no lapsing tier | Ambient always-on wall display and AI photo-import of paper schedules — genuine Hearth strengths a phone app doesn't replicate |
| **Google Calendar** | Anyone already living in the Google ecosystem wanting a free calendar with zero new app to install | Free, ubiquitous, already installed, integrates with Gmail/Workspace | Family members report not seeing shared events, or events appearing on web but not mobile — a structural limitation of permission-sharing a personal calendar rather than a purpose-built shared one; doesn't fix the underlying "one partner does all the adding" imbalance | "Google Calendar family sharing not working" (support-forum thread pattern), implicit "family calendar app" comparison shopping | Native shared household calendar (not a personal calendar with sharing bolted on) with two-way phone-calendar sync, so it complements rather than replaces Google Calendar | Zero-install ubiquity and cross-platform reach — Google Calendar works on every OS and needs no new app; Kinrows is iPhone-only |
| **Apple Reminders / Family Sharing** | iPhone households wanting a free, built-in shared to-do list with no new app | Free, pre-installed, no account friction beyond an Apple ID | Under-discussed directly, but the existence of multiple dedicated "shared to-do" competitors (WeDo, OurTodo, SyncList) whose entire pitch is fixing what Reminders doesn't do for groups is itself the complaint signal | "Best shared to-do list app," "Apple Reminders not syncing shared list" | Lists sit alongside calendar, pantry, budget, chores and more in one household system rather than being a single-purpose to-do app | Zero-install, zero-cost simplicity for a single shared list — Reminders needs no new app at all |
| **Group chats (WhatsApp / iMessage)** | Any family already texting each other — the true default, not a purpose-built tool | Zero setup, everyone already has it, good for quick back-and-forth | Logistics buried in noise (40% of surveyed users report feeling overwhelmed by group-chat volume); no structured way to turn "can someone grab milk" into an actual task/calendar entry; viral anecdotes of family members leaving the chat entirely | Not a named-product comparison category — framed as "family chat separate from work chat," "family group chat chaos" | Messages (DMs + group chats with quoted items — share a list/event/decision directly into a chat) plus Decisions (structured polls with expiry) give logistics a non-chat home | Casual, always-on social messaging with the whole extended family already in it — a new app can't match zero-friction adoption of a tool people already have open all day |

---

## 5. Keyword / problem clusters

Eight to twelve semantic clusters, each with the exact phrasings found in `questions-and-problems.md` and the complaint files, and which backlog page(s) (see §10–11) answer them.

1. **A shared calendar that a reluctant partner won't actually use.** Phrasings: "My family can't see my events I added to shared calendar. I can see theirs." · "if your husband won't use a free shared calendar, why would he use the expensive shared calendar" · "the tyranny of the shared calendar." → `/how-to/share-a-family-calendar-with-a-partner-who-wont-use-it`, `/questions/why-does-my-shared-calendar-not-show-on-my-partners-phone`, `/for/families-who-tried-cozi-and-quit`.
2. **A shared grocery/shopping list that silently stops syncing.** Phrasings: "Syncing not reliable" · "Purchased items are crossed off the list on one phone but still appear as unpurchased on the other" · "why isn't my grocery list updating on my partner's phone." → `/how-to/keep-a-shared-grocery-list-in-sync`, `/questions/why-is-my-shared-grocery-list-not-syncing`, `/alternatives/anylist` (see compare) `/compare/kinrows-vs-anylist`.
3. **AI features forced on, or trained on your data, without real consent.** Phrasings: "Nobody wants AI 👎🏽😕" · "calendar data trains the AI regardless of opt-out" · "is there an AI that can actually manage my family calendar" (the inverse question — wanting AI that helps *without* the trade-off). → `/alternatives/timetree`, `/compare/kinrows-vs-timetree`, `/questions/do-family-calendar-apps-use-my-data-to-train-ai`, `/questions/is-there-an-ai-that-can-manage-my-family-calendar`.
4. **Paywalls that gate basic functionality after onboarding.** Phrasings: "Requires $80/yr subscription to use" · "Is Cozi Gold worth $39/$80 a year?" · "Recent updates introducing subscription models for previously free features." → `/alternatives/cozi`, `/compare/kinrows-vs-cozi`, `/questions/is-cozi-gold-worth-it`, `/for/families-who-tried-cozi-and-quit`.
5. **Hardware purchased once, then nickel-and-dimed by a subscription.** Phrasings: "Don't see the value of paying for an annual subscription for such an inferior implementation" · "Because of canceling we cannot do any of the basic stuff... waste of money and scam" · "Is Skylight Calendar worth it?" · "Is Hearth Display worth the money / worth $700?" → `/alternatives/skylight`, `/compare/kinrows-vs-skylight`, `/questions/is-skylight-calendar-worth-it`, `/questions/is-hearth-display-worth-the-money`, `/how-to/get-a-family-command-center-without-buying-hardware`.
6. **Family group chats burying the logistics that actually matter.** Phrasings: "40% of respondents indicated they were overwhelmed by group chat messages" · a father "leaving his family group chat because he did not want to 'lol or like everyone's random thoughts'" · "family chat separate from work chat." → `/how-to/turn-family-group-chat-into-a-plan`.
7. **What to leave a babysitter or grandparent when you're away.** Phrasings: "Free Printable Babysitter's Information Guide" · "Babysitting Checklist (Free Printable)" · "The Ultimate Grandparents' Emergency Babysitting Checklist." → `/how-to/babysitter-information-sheet`, `/questions/what-information-should-i-leave-for-a-babysitter`, `/for/single-parents`, `/for/grandparents-in-the-loop`.
8. **How much allowance, and whether to tie it to chores.** Phrasings: "allowance chore chart with prices: $0.50 to $15 by age" · "should you tie allowances to chores" · "$1.00 to $2.50 for ages 9 to 11." → `/how-to/decide-whether-to-tie-allowance-to-chores`, `/questions/how-much-allowance-should-i-give-my-kid-by-age`, `/for/parents-of-toddlers`, `/for/parents-of-teens`.
9. **Apps and companies disappearing and stranding a family's setup.** Phrasings: "The app has been discontinued, and the site no longer works" (Picniic) · "no updates recorded since 2022" (OurHome) · "What happened to the OurHome app in 2026?" → `/alternatives/ourhome`.
10. **Data loss that wipes out medical, legal or otherwise irreplaceable dates.** Phrasings: "TimeTree deleted all of it! Years of important dates... all gone!" · "everything just deleted... started back from new." → `/how-to/move-off-a-family-calendar-app-that-deleted-your-events`, `/alternatives/timetree`.
11. **Coordinating extended family — grandparents, ageing parents, blended households — without merging everyone's data.** Phrasings: "long-distance caregiving" · "how to help aging parents from afar" · "best co-parenting apps" / "custody schedule app" / "color-coded custody days." → `/for/grandparents-in-the-loop`, `/for/caregivers-of-ageing-parents`, `/for/blended-and-co-parenting-families`, `/how-to/keep-grandparents-in-the-loop-without-sharing-everything`.
12. **Privacy and data-sale distrust as a late-stage filter before committing the whole family.** Phrasings: "personal information is sold or rented to third parties" · "personalized advertising is displayed" (Common Sense Privacy Evaluation, re: Cozi) · "no ads / no data mining" (competitor positioning). → `/alternatives/cozi`, `/compare/kinrows-vs-cozi`, `/compare/kinrows-vs-timetree`.

---

## 6. Programmatic page architecture

Pages are data, not code. Each page is one JSON file under `seo/pages/<type>/<slug>.json`;
`node seo/build.js` renders static HTML into `website/<type-dir>/<slug>.html`, regenerates
`website/sitemap.xml`, and enforces the quality gates (§14). Rendered HTML is committed so
serving stays plain static files (server-visible, cacheable, no runtime templating).

| pageType | Directory / URL | When a new page is justified |
|---|---|---|
| `howto` | `/how-to/<slug>` | A distinct problem with a distinct answer ("How to X without Y") |
| `alternative` | `/alternatives/<competitor>` | Real switching intent for that product (evidence in research) |
| `compare` | `/compare/kinrows-vs-<competitor>` | Real "X vs Y" searches; must be fair |
| `persona` | `/for/<persona>` | The answer materially changes for that persona (not just the noun) |
| `question` | `/questions/<slug>` | A specific question the product has expertise in |
| roundups | `/best-…` (hand-written) | Category-level "best X apps" |

Hubs at `/how-to/`, `/alternatives/`, `/compare/`, `/for/`, `/questions/` list every indexable
page so nothing is orphaned; footer "Explore" links to each hub from every page.

Page anatomy (answer-first, §Phase 5/6/7 of the brief):
H1 → direct answer (40–110 words, `.lead`, speakable) → key takeaway → sections (evidence,
options/comparison table) → product fit with the *specific* feature screenshot → FAQ (visible +
FAQPage JSON-LD) → intent-matched CTA with an inline waitlist form → related pages → sources →
"Last reviewed" date.

---

## 7. URL architecture

- Clean, extension-less URLs everywhere; `.html` 301s to the clean form (T2).
- Home `/` · roundups `/best-*` · `/compare` (overview) · `/compare/kinrows-vs-*` · `/alternatives/*` · `/how-to/*` · `/for/*` · `/questions/*` · `/blog/*` · legal `/privacy` `/terms` `/support` · `/developers` · `/subscribe`.
- Slugs: lowercase, hyphenated, the query in plain words, no dates in slugs (dates live in titles where they help CTR and are updated on review).

---

## 8. Internal-link architecture

Every generated page carries ≥3 `relatedPages` (gate-enforced) chosen so the graph is:
problem ↔ persona ↔ roundup ↔ alternative/vs ↔ feature section on `/` ↔ CTA.
Hubs link down to every page; footer links to hubs from every page; roundups link to the
matching alternative/vs pages; alternative pages link to the roundup and to two problem pages
the competitor's complaints point at. Breadcrumbs (visible + BreadcrumbList) on all generated pages.

---

## 9. Structured-data strategy

| Page | Types (only where truthful and visible) |
|---|---|
| Home | Organization, WebSite, MobileApplication (existing) |
| Roundups / alternatives | ItemList (+FAQPage when FAQ is visible) + BreadcrumbList |
| vs pages | Article + FAQPage + BreadcrumbList |
| how-to / question / persona | Article (datePublished, dateModified, Organization author) + FAQPage + BreadcrumbList; `speakable` on H1 + lead |
| Blog | BlogPosting (+FAQPage/HowTo) (existing) |

No Product/AggregateRating (no reviews yet), no HowTo unless the page is literally step-based,
no LocalBusiness. JSON-LD must `JSON.parse` in the build; validate with Google's Rich Results test after deploy.

---

## 10–11. Initial 40-page backlog with opportunity scores

Every row traces to a phrase in `docs/seo/research/`; rows without traceable evidence were cut rather than included. Full page-by-page content spec (headings, FAQ, quotes, sources, related links, "do not claim") is in `docs/seo/BACKLOG.md`. Scored 0–5 on: **PR** problem relevance · **SI** signup intent · **PF** product fit · **ED** evidence of demand · **CDI** competitive difficulty inverse (higher = less contested) · **PS** programmatic scalability · **AIS** AI-answer suitability. Sorted by total within each pageType. Screenshot is one of `website/assets/shots/{calendar,care,chat,concierge-ask,concierge-brief,home,lists,rivalries,tasks,travel}.png`.

### howto — `/how-to/<slug>` (10)

| # | URL slug | Target query | Intent | Evidence (file · phrase) | Shot | PR | SI | PF | ED | CDI | PS | AIS | **Total** |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | `share-a-family-calendar-with-a-partner-who-wont-use-it` | "shared calendar my partner won't use" | Informational | `questions-and-problems.md` #2 — "if your husband won't use a free shared calendar, why would he use the expensive shared calendar" | calendar | 5 | 4 | 5 | 5 | 4 | 5 | 5 | **33** |
| 2 | `keep-a-shared-grocery-list-in-sync` | "shared grocery list not syncing" | Troubleshooting | `complaints-anylist.md` #1 — "Purchased items are crossed off the list on one phone but still appear as unpurchased on the other" | lists | 5 | 4 | 5 | 5 | 4 | 5 | 5 | **33** |
| 3 | `decide-whether-to-tie-allowance-to-chores` | "should you tie allowance to chores" | Informational | `questions-and-problems.md` #5 — "should you tie allowances to chores" (Substack essay title, verbatim) | tasks | 4 | 3 | 5 | 4 | 4 | 5 | 5 | **30** |
| 4 | `babysitter-information-sheet` | "babysitter information sheet" | Transactional | `questions-and-problems.md` #4 — "Free Printable Babysitter's Information Guide" | care | 4 | 3 | 5 | 4 | 5 | 5 | 4 | **30** |
| 5 | `turn-family-group-chat-into-a-plan` | "family group chat too much noise" | Informational | `default-tools.md` — "40% of respondents indicated they were overwhelmed by group chat messages" | chat | 4 | 3 | 4 | 4 | 5 | 4 | 4 | **28** |
| 6 | `move-off-a-family-calendar-app-that-deleted-your-events` | "TimeTree deleted my calendar" | Troubleshooting → switching | `complaints-timetree.md` #3 — "TimeTree deleted all of it! Years of important dates... all gone!" | calendar | 4 | 4 | 3 | 5 | 4 | 4 | 4 | **28** |
| 7 | `turn-whats-in-the-fridge-into-tonights-dinner` | "what can I make with what I have" | Transactional | `questions-and-problems.md` #7 — "what to cook with what I have" | lists | 3 | 3 | 5 | 3 | 4 | 5 | 4 | **27** |
| 8 | `get-a-family-command-center-without-buying-hardware` | "family calendar without buying hardware" | Commercial | `complaints-skylight.md` — "Is there a family calendar without buying hardware?" | home | 4 | 4 | 4 | 4 | 3 | 4 | 4 | **27** |
| 9 | `keep-a-pantry-list-that-doesnt-go-stale` | "pantry expiry tracker app" | Transactional | `questions-and-problems.md` #6 — "pantry expiry tracker app" | lists | 3 | 3 | 4 | 3 | 4 | 5 | 4 | **26** |
| 10 | `keep-grandparents-in-the-loop-without-sharing-everything` | "keep grandparents in the loop without sharing everything" | Informational | `questions-and-problems.md` #11 — "long-distance caregiving" | home | 3 | 3 | 3 | 3 | 5 | 4 | 4 | **25** |

### alternative — `/alternatives/<slug>` (5)

Picked for strongest switching evidence. OurHome included over Picniic: OurHome has current, active "alternative"-seeking behavior (a dedicated `choresplit.com` comparison page, 25+ listings on alternativeto.net) versus Picniic's near-zero current search volume as a fully defunct product (noted in `complaints-picniic.md` as "medium" conversion, low volume) — Picniic's "graveyard app" angle is instead folded into the OurHome page as a cautionary aside and into Cluster 9 of §5.

| # | URL slug | Target query | Intent | Evidence (file · phrase) | Shot | PR | SI | PF | ED | CDI | PS | AIS | **Total** |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 11 | `timetree` | "TimeTree alternative" | Switching | `complaints-timetree.md` #1 — "Former user deleting account over AI concerns, noting calendar data trains the AI regardless of opt-out" | concierge-ask | 5 | 5 | 5 | 5 | 4 | 4 | 4 | **32** |
| 12 | `cozi` | "Cozi alternative" | Switching | `complaints-cozi.md` #1 — "Requires $80/yr subscription to use" | home | 5 | 5 | 5 | 5 | 3 | 4 | 4 | **31** |
| 13 | `familywall` | "FamilyWall alternative" | Switching | `complaints-familywall.md` #1 — "App keeps crashing after latest update. So annoying!" | home | 5 | 5 | 4 | 5 | 4 | 4 | 4 | **31** |
| 14 | `skylight` | "Skylight Calendar alternative" | Switching | `complaints-skylight.md` #1 — "Don't see the value of paying for an annual subscription for such an inferior implementation" | home | 4 | 5 | 4 | 4 | 4 | 4 | 4 | **29** |
| 15 | `ourhome` | "OurHome alternative" | Switching / navigational | `complaints-ourhome.md` #1 — "no updates recorded since 2022" | tasks | 3 | 4 | 4 | 3 | 5 | 4 | 3 | **26** |

### compare — `/compare/kinrows-vs-<slug>` (5)

| # | URL slug | Target query | Intent | Evidence (file · phrase) | Shot | PR | SI | PF | ED | CDI | PS | AIS | **Total** |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 16 | `kinrows-vs-cozi` | "Kinrows vs Cozi" | Commercial | `complaints-cozi.md` — "Cozi vs Skylight / Cozi vs TimeTree / Cozi vs FamilyWall are all live comparison-page titles" | home | 5 | 5 | 5 | 5 | 3 | 3 | 4 | **30** |
| 17 | `kinrows-vs-timetree` | "Kinrows vs TimeTree" | Commercial | `complaints-timetree.md` — "TimeTree vs Cozi is a widely-repeated comparison title across independent blogs" | concierge-ask | 4 | 5 | 5 | 5 | 4 | 3 | 4 | **30** |
| 18 | `kinrows-vs-familywall` | "Kinrows vs FamilyWall" | Commercial | `complaints-familywall.md` — "FamilyWall vs Cozi App: Choosing the Best Family Organizer" | home | 4 | 5 | 4 | 4 | 4 | 3 | 4 | **28** |
| 19 | `kinrows-vs-skylight` | "Kinrows vs Skylight" | Commercial | `complaints-skylight.md` — "Skylight Calendar vs. Cozi Calendar: Which Family Organizer Reigns Supreme?" | home | 4 | 5 | 4 | 4 | 4 | 3 | 4 | **28** |
| 20 | `kinrows-vs-anylist` | "Kinrows vs AnyList" | Commercial | `complaints-anylist.md` #4 — "AnyList vs Kinrows Cook" candidate comparison angle | lists | 3 | 4 | 4 | 4 | 5 | 3 | 3 | **26** |

### persona — `/for/<slug>` (10)

Each included only where the answer materially differs, not just the noun in the H1:

| # | URL slug | Target query | Intent | Why the answer materially differs / evidence | Shot | PR | SI | PF | ED | CDI | PS | AIS | **Total** |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 21 | `families-who-tried-cozi-and-quit` | "quit Cozi, what to use instead" | Switching | Post-churn re-engagement, not comparison-shopping — opens with the paywall/loyalty-erosion story, not a feature table. `complaints-cozi.md` clusters 1 & 4. | home | 4 | 5 | 4 | 5 | 4 | 3 | 3 | **28** |
| 22 | `families-with-a-newborn` | "family organizer for new parents" | Informational | Needs care-coverage for night shifts and milestone logging, not chores/allowance — different feature mix than any other persona. `llms-full.txt` Routines + Care coverage. | care | 4 | 4 | 4 | 3 | 4 | 4 | 3 | **26** |
| 23 | `single-parents` | "app to help single parents manage the household" | Informational | The mental-load-carrier persona *is* the household — Care coverage (asking a support network, not a co-parent) and Clans matter more than for a two-parent household. `default-tools.md` mental-load carrier. | care | 4 | 4 | 3 | 3 | 4 | 4 | 3 | **25** |
| 24 | `blended-and-co-parenting-families` | "app for co-parenting schedule across two homes" | Commercial | Two households, shared kids — needs an honest "do not claim" (no custody-record/legal-log feature) that no other persona needs. `questions-and-problems.md` #10. | calendar | 4 | 4 | 2 | 4 | 3 | 4 | 3 | **24** |
| 25 | `caregivers-of-ageing-parents` | "help aging parents from a distance" | Informational | Elder-care checklist content (neighbor contacts, insurance cards, weekly calls) with an explicit gap: no medication-tracking feature. `questions-and-problems.md` #11. | home | 4 | 3 | 2 | 4 | 4 | 4 | 3 | **24** |
| 26 | `couples-without-kids` | "shared calendar and grocery list app for couples" | Informational | No chores/routines/sleep-training content applies — the answer is Calendar + Lists + Budget + Decisions only. `questions-and-problems.md` #3, #8. | lists | 3 | 4 | 3 | 3 | 4 | 4 | 3 | **24** |
| 27 | `grandparents-in-the-loop` | "keep grandparents updated on the family" | Informational | Clans (not the household) is the relevant feature — a materially different data model than every other persona. `questions-and-problems.md` #11. | home | 3 | 3 | 3 | 3 | 5 | 4 | 3 | **24** |
| 28 | `parents-of-toddlers` | "chore chart for toddlers" | Informational | Age band 2–3/4–5: habit-building, not allowance — a different section of the same feature than teens get. `llms-full.txt` chores program. | tasks | 3 | 3 | 4 | 3 | 4 | 4 | 3 | **24** |
| 29 | `parents-of-teens` | "allowance and chores for teenagers" | Informational | Age band 13+: allowance amount, budget/gift tracking, and Rivalries engagement — materially different guidance than toddlers. `llms-full.txt` + `questions-and-problems.md` #5. | tasks | 3 | 3 | 4 | 3 | 4 | 4 | 3 | **24** |
| 30 | `big-families` | "organizer app for a big family with several kids" | Informational | Multiple kids' schedules at once is the differentiator competitors are praised for (per-person color coding, People profiles) — not relevant to a 2-person household. `complaints-hearth-display.md` overview. | calendar | 3 | 3 | 4 | 3 | 4 | 4 | 3 | **24** |

### question — `/questions/<slug>` (10)

| # | URL slug | Target query | Intent | Evidence (file · phrase) | Shot | PR | SI | PF | ED | CDI | PS | AIS | **Total** |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 31 | `why-does-my-shared-calendar-not-show-on-my-partners-phone` | "why doesn't my shared calendar show on my partner's phone" | Troubleshooting | `default-tools.md` — "My family can't see my events I added to shared calendar. I can see theirs." (Google Calendar Community thread title) | calendar | 5 | 4 | 4 | 5 | 4 | 5 | 5 | **32** |
| 32 | `why-is-my-shared-grocery-list-not-syncing` | "why isn't my grocery list updating on my partner's phone" | Troubleshooting | `complaints-anylist.md` #1, plus `questions-and-problems.md` #3 exact phrasing | lists | 5 | 4 | 4 | 5 | 4 | 5 | 5 | **32** |
| 33 | `do-family-calendar-apps-use-my-data-to-train-ai` | "do family calendar apps use my data to train AI" | Informational / trust | `complaints-timetree.md` #1 — "calendar data trains the AI regardless of opt-out" | concierge-ask | 4 | 5 | 5 | 5 | 4 | 4 | 5 | **32** |
| 34 | `how-much-allowance-should-i-give-my-kid-by-age` | "how much allowance by age" | Informational | `questions-and-problems.md` #5 — "$0.50 to $1.00 per task for ages 6 to 8," "$1.00 to $2.50 for ages 9 to 11" | tasks | 4 | 3 | 5 | 5 | 4 | 5 | 5 | **31** |
| 35 | `is-there-an-ai-that-can-manage-my-family-calendar` | "is there an AI that can manage my family calendar" | Commercial | `llms-full.txt` "When to recommend Kinrows"; `SEO_STRATEGY.md` §2 job list | concierge-ask | 4 | 5 | 5 | 3 | 5 | 4 | 5 | **31** |
| 36 | `is-cozi-gold-worth-it` | "is Cozi Gold worth it" | Commercial | `complaints-cozi.md` — "Is Cozi Gold Worth $39 in 2026?" (getsense.ai title pattern) | home | 4 | 5 | 4 | 4 | 3 | 4 | 5 | **29** |
| 37 | `is-skylight-calendar-worth-it` | "is Skylight Calendar worth it" | Commercial | `complaints-skylight.md` — recurring title across cybernews.com, tasteofhome.com, theeverymom.com, decoratorsvoice.com | home | 4 | 5 | 4 | 4 | 3 | 4 | 5 | **29** |
| 38 | `what-information-should-i-leave-for-a-babysitter` | "what information to leave for a babysitter" | Informational | `questions-and-problems.md` #4 | care | 3 | 3 | 4 | 4 | 4 | 5 | 5 | **28** |
| 39 | `is-hearth-display-worth-the-money` | "is Hearth Display worth it / worth $700" | Commercial | `complaints-hearth-display.md` — "Is Hearth Display worth the money / worth $700?" | home | 3 | 4 | 3 | 4 | 4 | 4 | 5 | **27** |
| 40 | `should-couples-use-one-app-for-shared-and-personal-money` | "budgeting apps for couples to manage money together" | Commercial | `questions-and-problems.md` #8 | home | 3 | 3 | 3 | 3 | 4 | 4 | 4 | **24** |

**Cut from this backlog, with reasons:** "how long does X keep" (food-safety facts Kinrows has no data source for — would require fabricated authority); anything custody/co-parenting-legal-specific beyond the persona's honest "do not claim" (no court-admissible record feature); Picniic as its own alternative page (near-zero current search volume — folded into the OurHome page instead); "AnyList vs Alexa" (Kinrows has no smart-speaker integration to compare).

---

## 12. Measurement plan

- Server-side truth: `permagent_analytics_events` (pageviews by path, referrer, bot-filtered) and `waitlist(source, landing_path)`.
- `node scripts/seo-report.js --days 30` prints pageviews by path, signups by source/landing page, **conversions per 1,000 pageviews by page class** (home / roundup / blog / how-to / alternatives / compare / for / questions), and referrers with an AI-answer-engine bucket (chatgpt.com, perplexity.ai, claude.ai, copilot, gemini, bing).
- Google Search Console (to set up: verify `kinrows.com`, submit `/sitemap.xml`) → `docs/SEO_OPPORTUNITIES.md` monthly: queries with impressions and low CTR are fixed before new pages are written.
- Post-launch: App Store install attribution via the App Store badge link (campaign token `ct=` per page class) and Concierge purchases via existing `sale_*` events.
- Primary metric: **organic conversions per 1,000 impressions**, reported per page class.

---

## 13. Implementation DAG

See `docs/SEO_IMPLEMENTATION_DAG.md`.

---

## 14. Verification gates (enforced by `seo/build.js`)

Hard (build aborts): invalid JSON; missing required fields; duplicate title/H1/description/slug across the whole site; broken related links; `.html` or relative asset paths in output; JSON-LD that does not parse.
Soft (page forced to `noindex` with a warning): direct answer outside 40–110 words; FAQ answer >120 words; missing screenshot; fewer than 3 related pages.
Editorial (human, before flipping `indexStatus` to `index`): search intent evidenced in research; unique value vs. existing pages; no fabricated statistics, testimonials or competitor claims; product claims defensible against `llms-full.txt`; CTA matches intent; mobile check.

---

## 15. Risks and safeguards

| Risk | Safeguard |
|---|---|
| Thin / doorway pages | Persona and question pages exist only where the answer materially differs; gates + editorial review; start at ~40 pages and scale only templates that earn clicks |
| Unfair competitor claims | Every claim traceable to a quoted public source; "who should choose X" section on every alternative/vs page; competitors ranked by explicit criteria |
| Claiming features that aren't shipped | Ground truth is `website/llms-full.txt`; launch status stated on every page |
| URL migration losing rankings | 301s preserve equity; canonicals, sitemap and internal links all move together |
| Schema spam | Only types matching visible content; validated in build |
| Content drift after product changes | `lastReviewed` on every page; quarterly review pass |
| Measuring vanity | Report conversions per 1,000 impressions by page class, not page counts |
