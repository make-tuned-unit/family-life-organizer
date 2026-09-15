# Kinrows SEO Backlog — Content Specs

40 pages, one block each, grouped by `pageType`. Read `docs/seo/CONTENT_BRIEF.md` (truth rules, voice,
answer-first anatomy) and `docs/SEO_STRATEGY.md` §10–11 (scores, evidence) before writing any page —
this file is the content spec, not the JSON. When a JSON file is authored at `seo/pages/<pageType>/<slug>.json`
per `seo/README.md`, these fields map directly onto its schema (`query`→`query`, `title`→`title`,
`thesis`→seed for `directAnswer`, `sections`→`sections` headings, `faq`→`faq` questions, `screenshot`→
`productFit.screenshot`, `relatedPages`→`relatedPages`, `sources`→`sources`).

Universal do-not-claim list (applies to every page in addition to the page-specific ones below):
Kinrows is iPhone-only (iOS 18+), not available on Android; launching September 2026, not available today;
no crash-rate, uptime, or "zero data loss" guarantee exists to cite; no star ratings, review counts or
testimonials may be invented for Kinrows; no Alexa/Google Home/smart-speaker integration; no home-screen
or lock-screen widget confirmed; no custody/legal record-keeping feature; no medication-tracking feature.

---

## howto — `/how-to/<slug>`

### 1. `share-a-family-calendar-with-a-partner-who-wont-use-it`
- **query:** shared calendar my partner won't use / family calendar my partner won't use
- **searchIntent:** informational (adoption-skepticism, pre-purchase)
- **title:** Sharing a Calendar With a Partner Who Won't Use It
- **thesis:** A shared calendar only works if both people can see it without opening a new app or changing habits first, which is why the fix is usually a calendar that pulls in a partner's existing phone events rather than asking them to adopt a new one.
- **sections:** Why "just share your calendar" usually fails · What actually gets a reluctant partner to look at it · Two-way sync vs. permission-sharing (the real difference) · A 10-minute setup that doesn't require their buy-in first
- **faq:** "Why can't my partner see events I add to our shared calendar?" · "Do we both have to use the same app?" · "What if my partner just won't look at any calendar?" · "Is a shared calendar enough to fix an unequal mental load?"
- **quotes:** "My family can't see my events I added to shared calendar. I can see theirs." — Google Calendar Community thread title, https://support.google.com/calendar/thread/17626208. "If your husband won't use a free shared calendar, why would he use the expensive shared calendar?" — Reddit comment, reported via uninfluencedreview.com (secondary source, attribute as "a widely-upvoted Reddit comment reported by uninfluencedreview.com," not as a direct Reddit quote). "Relationship problems can masquerade as logistical problems, and no calendar feature is going to cure a partner of [not sharing the load]" — sophiehines.substack.com, "The tyranny of the shared calendar."
- **screenshot:** calendar.png
- **relatedPages:** /questions/why-does-my-shared-calendar-not-show-on-my-partners-phone, /blog/sharing-the-mental-load, /blog/family-calendar-organization, /best-family-calendar-app, /for/families-who-tried-cozi-and-quit
- **sources:** https://support.google.com/calendar/thread/17626208 ; https://sophiehines.substack.com/p/the-tyranny-of-the-shared-calendar ; https://forums.anandtech.com/threads/google-calendar-events-disappear-from-phone-show-up-fine-on-website.2168205
- **doNotClaim:** Do not claim a shared calendar alone fixes an unequal mental load — the research explicitly says tool adoption is a symptom, not the root cause; frame Kinrows as removing the *technical* excuse, not as relationship therapy.

### 2. `keep-a-shared-grocery-list-in-sync`
- **query:** shared grocery list not syncing / grocery list duplicating items
- **searchIntent:** troubleshooting → alternative-seeking
- **title:** Fixing a Shared Grocery List That Won't Sync
- **thesis:** A shared grocery list that shows different items on different phones is almost always a sign the app is relying on best-effort sync rather than one server-scoped list every device reads from, and the fix is a list built that way from the start rather than a setting to toggle.
- **sections:** What "not syncing" actually means under the hood · The three failure patterns (duplicate items, ghost items, items that don't cross off) · What a server-scoped list looks like instead · Moving your list over without losing what's on it
- **faq:** "Why does my grocery list show different items on each phone?" · "Why do items get crossed off on one phone but not another?" · "Why does my shared list keep making duplicates?" · "Is there a shared grocery list app that actually stays in sync?"
- **quotes:** "Purchased items are crossed off the list on one phone but still appear as unpurchased on the other." — vtamoeba, AnyList, 2★, "Syncing not reliable," 2026-07-25, App Store US. "When we try to Add anything it makes three of the same items and gets rid of the category." — Beth0r, FamilyWall, 2★, "Unable to use shopping list," App Store US. "Updates will occasionally erase list memory" — The GrimRocker, AnyList, 1★, "Frustrating," 2026-07-25, App Store US.
- **screenshot:** lists.png
- **relatedPages:** /questions/why-is-my-shared-grocery-list-not-syncing, /compare/kinrows-vs-anylist, /best-shared-shopping-list-app, /how-to/keep-a-pantry-list-that-doesnt-go-stale
- **sources:** https://itunes.apple.com/us/rss/customerreviews/id=522167641/sortBy=mostRecent/page=1/json ; https://itunes.apple.com/us/rss/customerreviews/id=496889629/sortBy=mostRecent/page=2/json
- **doNotClaim:** Do not claim Kinrows lists have never had a sync bug — claim the architecture (server-scoped, household-validated) rather than a zero-defect history.

### 3. `decide-whether-to-tie-allowance-to-chores`
- **query:** should you tie allowance to chores
- **searchIntent:** informational
- **title:** Should Allowance Be Tied to Chores?
- **thesis:** Most child-development research favors paying a fixed allowance separate from required household chores while using non-punitive rewards or bonuses for extra effort, because docking pay for missed chores tends to undermine intrinsic motivation rather than build it.
- **sections:** The case for tying allowance to chores · The case against (what the research says about motivation) · A middle path: fixed allowance plus optional bonuses · How this changes by age
- **faq:** "Should you tie allowances to chores?" · "What happens if a kid skips a chore — should you dock their allowance?" · "How much allowance is normal by age?" · "What's the difference between a chore and a paid task?"
- **quotes:** "should you tie allowances to chores" — Substack essay title (verbatim search-result title, attribute as "a widely-cited parenting essay title"). Age-band price phrasing pattern: "$0.50 to $1.00 per task for ages 6 to 8," "$1.00 to $2.50 for ages 9 to 11," "$2.00 to $5.00 for ages 12 and up" — aggregated from multiple chore-chart search-result titles, cite as a pattern not a single source.
- **screenshot:** tasks.png
- **relatedPages:** /questions/how-much-allowance-should-i-give-my-kid-by-age, /for/parents-of-toddlers, /for/parents-of-teens, /best-chore-app-for-families
- **sources:** research citations in `llms-full.txt`: Rossmann (2002), White et al. (2019), Warneken & Tomasello (2008), Deci, Koestner & Ryan (1999) — cite the studies by name/year only; do not fabricate DOIs or publishers not already in llms-full.txt.
- **doNotClaim:** Do not present Kinrows' "fixed allowance, never docked" design as the only research-backed answer — present it honestly as one defensible position among several, and say why Kinrows chose it.

### 4. `babysitter-information-sheet`
- **query:** babysitter information sheet
- **searchIntent:** transactional (wants a fill-in-the-blank sheet)
- **title:** Building a Babysitter Information Sheet People Actually Use
- **thesis:** A babysitter information sheet only works if it is easy to update and reaches the sitter at the moment they need it, which is why a living, shareable version beats a printed sheet stuck to the fridge that goes stale after the first change of plans.
- **sections:** What belongs on a babysitter info sheet (the essentials) · Why printable templates go stale · Making it something the sitter can actually check mid-visit · Care coverage without a 30-text group chat
- **faq:** "What information should I leave for a babysitter?" · "What should be on a babysitter emergency sheet?" · "Does a babysitter need to download an app to see this?" · "How do grandparents fit into this differently than a paid sitter?"
- **quotes:** "Free Printable Babysitter's Information Guide" / "Babysitter Information Sheet Free Printable" / "The Ultimate Grandparents' Emergency Babysitting Checklist" — recurring search-result title pattern across 6+ printable-template sites (cite as a pattern, not individual URLs, per `questions-and-problems.md`).
- **screenshot:** care.png
- **relatedPages:** /questions/what-information-should-i-leave-for-a-babysitter, /for/single-parents, /for/grandparents-in-the-loop, /how-to/turn-family-group-chat-into-a-plan
- **sources:** none external beyond the search-title pattern already cited in `docs/seo/research/questions-and-problems.md` §4.
- **doNotClaim:** Do not claim Care coverage replaces a human backup plan for emergencies — frame it as organizing logistics (time windows, approvals), not as safety-critical infrastructure.

### 5. `turn-family-group-chat-into-a-plan`
- **query:** family group chat too much noise / separate logistics from family group chat
- **searchIntent:** informational (venting → seeking a better system)
- **title:** Getting Logistics Out of a Chaotic Family Group Chat
- **thesis:** A family group chat mixes jokes and forwarded links with the one message that actually mattered, so the fix isn't a quieter chat — it's giving logistics (who's picking up whom, what's for dinner, is Saturday free) a separate home that isn't scrollback.
- **sections:** Why group chats collapse under their own weight · The specific failure: "it was said in chat but never made it onto the list" · A structure with a chat and a logistics layer, not one giant thread · What to actually move out of the group chat first
- **faq:** "Why is our family group chat so overwhelming?" · "How do I stop important messages from getting buried in the family chat?" · "Should logistics and social chat be in the same thread?" · "What's a better system than a WhatsApp family group?"
- **quotes:** "A survey of people in the United States and United Kingdom found that 40% of respondents indicated they were overwhelmed by group chat messages and notifications." — statistic, paraphrased via WebSearch aggregation, cite generally, no single URL. A father "announcing he was leaving his family group chat because he did not want to 'lol or like everyone's random thoughts'" — reported by gulfnews.com and other outlets. Family WhatsApp groups often "collapse under its own weight" once extended family is added — jimmerrett.substack.com, "the whatsapp group chats you can[']t..."
- **screenshot:** chat.png
- **relatedPages:** /how-to/share-a-family-calendar-with-a-partner-who-wont-use-it, /blog/sharing-the-mental-load, /for/big-families
- **sources:** https://gulfnews.com/world/americas/i-cant-live-with-this-pressure-us-dad-goes-viral-after-hilariously-announcing-hes-leaving-his-family-group-chat-1.1674829397022 ; https://jimmerrett.substack.com/p/the-whatsapp-group-chats-you-cant
- **doNotClaim:** Do not claim Kinrows Messages will make family members stop using WhatsApp/iMessage — position it as an additional, purpose-built layer for logistics, not a chat replacement mandate.

### 6. `move-off-a-family-calendar-app-that-deleted-your-events`
- **query:** TimeTree deleted my calendar / family calendar app lost my events
- **searchIntent:** troubleshooting → switching
- **title:** What to Do When a Family Calendar App Deletes Your Events
- **thesis:** When a calendar app silently wipes shared events, the first priority is recovering what you can from each device's local cache or linked account before switching apps, and the second is choosing a replacement that treats your phone's own calendar as the source of truth rather than a private database only the app controls.
- **sections:** What to check first (device calendar, email confirmations, a linked account) · Why this kind of data loss happens · What "two-way sync with your phone's calendar" actually protects against · Moving over without re-entering everything by hand
- **faq:** "Why did my calendar app delete all my events?" · "Can I recover events after a calendar app wipes my data?" · "Does two-way calendar sync protect me from this?" · "How do I move to a new family calendar app without losing history?"
- **quotes:** "My entire calendar was randomly wiped out one day! ... TimeTree deleted all of it! Years of important dates... all gone!" — Tehth, TimeTree, 1★, "Timetree deleted everything!," 2026-07-22, App Store US. "I was using this for a while and was gonna write a good review then today everything just deleted even the shared ones I had with my friends, it started back from new" — Wismeiry.P, TimeTree, 1★, "Deleted everything," 2026-07-12, App Store US.
- **screenshot:** calendar.png
- **relatedPages:** /alternatives/timetree, /compare/kinrows-vs-timetree, /best-family-calendar-app
- **sources:** https://itunes.apple.com/us/rss/customerreviews/id=952578473/sortBy=mostRecent/page=2/json
- **doNotClaim:** Do not promise Kinrows can never lose data — say what the architecture does (server-scoped, parameterized storage, two-way phone sync as a second copy) without a zero-loss guarantee.

### 7. `turn-whats-in-the-fridge-into-tonights-dinner`
- **query:** what can I make with what I have / recipes based on what you have
- **searchIntent:** transactional
- **title:** Turning What's in the Fridge Into Tonight's Dinner
- **thesis:** The fastest way to decide what's for dinner is to start from what's already in the pantry and fridge rather than browsing recipes and hoping the ingredients match, which is why a pantry-aware recipe tool that shows "you have 4 of 6" beats a general recipe search.
- **sections:** Why recipe search is the wrong starting point · Cooking from inventory instead of a recipe · What to do about the ingredients you're missing · A hands-free way to cook once you've decided
- **faq:** "How do I decide what to cook from what's already in the fridge?" · "Is there an app that suggests recipes from what I have?" · "What do I do about the ingredients a recipe needs that I don't have?"
- **quotes:** none — this cluster is transactional/tool-seeking with low direct-quote volume per `questions-and-problems.md` §7; do not fabricate a quote to fill the section.
- **screenshot:** lists.png
- **relatedPages:** /how-to/keep-a-pantry-list-that-doesnt-go-stale, /best-family-organizer-apps, /blog/family-budgeting-without-friction
- **sources:** none beyond `questions-and-problems.md` §7 (search-title pattern only, no citable URL).
- **doNotClaim:** Do not claim the AI recipe suggestions are nutritionally vetted or medically appropriate for allergies — Cook is a convenience feature, not a dietary safety tool.

### 8. `get-a-family-command-center-without-buying-hardware`
- **query:** family calendar without buying hardware / family command center without hardware
- **searchIntent:** commercial
- **title:** A Family Command Center Without Buying Hardware
- **thesis:** A wall-mounted family display can cost $170–$700 up front and still require a subscription to keep basic features working, so most of what a "command center" actually does — a shared calendar, lists, chores, a place everyone checks — runs just as well on the phones the household already owns.
- **sections:** What a hardware display actually promises · The subscription-after-purchase problem · What a phone-first setup gets you instead · Where a physical display still genuinely wins
- **faq:** "Is there a family calendar without buying hardware?" · "Do I need a wall display to keep the family organized?" · "What's the real ongoing cost of a hardware family calendar?"
- **quotes:** "Don't see the value of paying for an annual subscription for such an inferior implementation." — JAinDC, Skylight, 2★, "Great concept, terrible app.," App Store US, 2026-08-31. "Because of canceling we cannot do any of the basic stuff. Like the to dos... Such a waste of money and scam." — Aspencupcake, Hearth Display, 1★, "Overly expensive," App Store US, 2025-08-25.
- **screenshot:** home.png
- **relatedPages:** /alternatives/skylight, /compare/kinrows-vs-skylight, /questions/is-hearth-display-worth-the-money, /questions/is-skylight-calendar-worth-it
- **sources:** https://itunes.apple.com/us/rss/customerreviews/id=1438779037/sortBy=mostRecent/page=2/json ; https://itunes.apple.com/us/rss/customerreviews/id=6498717775/sortBy=mostRecent/page=1/json
- **doNotClaim:** Say honestly where a physical always-on display wins (ambient visibility with no phone pickup, works for kids who can't read a phone) — do not claim a phone app fully replaces that for every household.

### 9. `keep-a-pantry-list-that-doesnt-go-stale`
- **query:** pantry expiry tracker app / food expiration date tracker
- **searchIntent:** transactional
- **title:** Keeping a Pantry List That Doesn't Go Stale
- **thesis:** A pantry list only stays useful if it's updated at the moment food goes in and comes out, which means the tracker has to live wherever you already put groceries away and log meals, not as a separate spreadsheet or one-time inventory.
- **sections:** Why pantry spreadsheets stop getting updated after week one · Tracking by location (pantry, fridge, freezer) instead of one long list · Expiry alerts that don't get ignored · Closing the loop from pantry to dinner
- **faq:** "What's the easiest way to track pantry and fridge inventory?" · "Is there an app that tracks food expiration dates?" · "How do I stop wasting food that expires before I use it?"
- **quotes:** none verbatim — cluster is app-name-driven search behavior per `questions-and-problems.md` §6; do not fabricate a review quote.
- **screenshot:** lists.png
- **relatedPages:** /how-to/turn-whats-in-the-fridge-into-tonights-dinner, /best-shared-shopping-list-app, /blog/family-budgeting-without-friction
- **sources:** none beyond `questions-and-problems.md` §6.
- **doNotClaim:** Do not state specific shelf-life numbers for any food item (e.g. "milk keeps for X days") — that is food-safety guidance Kinrows has no authoritative source for; keep the page about tracking, not expiry facts.

### 10. `keep-grandparents-in-the-loop-without-sharing-everything`
- **query:** keep grandparents in the loop without sharing everything / long-distance caregiving family updates
- **searchIntent:** informational
- **title:** Sharing Family Updates With Grandparents Without Merging Everything
- **thesis:** Keeping grandparents in the loop doesn't require giving them access to your household's budget or private notes — a separate group that only overlaps through shared people lets you share milestones, photos and select plans while your household's sensitive data stays put.
- **sections:** Why "just add them to the family calendar" overshares · A separate group that shares people, not data · What's worth sharing with grandparents (and what isn't) · Long-distance caregiving: staying informed without taking over
- **faq:** "How do I keep grandparents updated without giving them access to everything?" · "Is there a way to have a separate group for extended family?" · "What should I share with a long-distance grandparent vs. keep private?"
- **quotes:** "long-distance caregiving" (established term of art); "meeting neighbors and getting their contact information," "gathering copies of insurance cards and medical history," "set a specific day and time each week for a video call" — practical checklist phrasing, aggregated via WebSearch, cite as a pattern per `questions-and-problems.md` §11, no single attributable source.
- **screenshot:** home.png
- **relatedPages:** /for/grandparents-in-the-loop, /for/caregivers-of-ageing-parents, /for/blended-and-co-parenting-families
- **sources:** none with a specific URL beyond the general pattern in `questions-and-problems.md` §11 — this theme is flagged in research as "underserved by dedicated apps," treat as a content opportunity, not a feature-match page.
- **doNotClaim:** Do not claim Clans include any elder-care-specific feature (medication tracking, health monitoring) — Clans are a general-purpose separate group, nothing more.

---

## alternative — `/alternatives/<slug>`

### 11. `timetree`
- **query:** TimeTree alternative
- **searchIntent:** switching
- **title:** Best TimeTree Alternatives (2026)
- **thesis:** People leave TimeTree mainly over forced AI features that train on calendar data even after opting out, ads on the free tier, and severe data-loss incidents — so the strongest alternatives are apps that are explicit about not training on your data and that don't gate the calendar behind ads.
- **sections:** Why people search for a TimeTree alternative · What TimeTree does well (fair to say) · Ranked alternatives · Who should stay with TimeTree
- **faq:** "Why are people leaving TimeTree?" · "Does TimeTree use my calendar data to train AI?" · "What happened to my TimeTree calendar data?" · "Is there a TimeTree alternative without ads?"
- **quotes:** "Former user deleting account over AI concerns, noting calendar data trains the AI regardless of opt-out." — june ♪(๑ᴖ◡ᴖ๑)♪, 1★, "added AI," App Store US, 2026-08-22. "Criticizes forced AI adoption and notes that opting out preferences don't save properly." — GodisntReal:), 1★, "AI Ruined the App," App Store US, 2026-08-31. "The ads at the top make the overall calendar hideous. Money hungry app that forces you to pay if you don't want to see ads." — Greetenpug, 1★, "100% NOT worth it," App Store US, 2026-07-06. Credits app with improving relationship and mental health — Stephi Styles, 5★ (fair-to-TimeTree strength).
- **screenshot:** concierge-ask.png
- **relatedPages:** /compare/kinrows-vs-timetree, /questions/do-family-calendar-apps-use-my-data-to-train-ai, /how-to/move-off-a-family-calendar-app-that-deleted-your-events, /best-family-calendar-app
- **sources:** https://itunes.apple.com/us/rss/customerreviews/id=952578473/sortBy=mostRecent/page=1/json and page=2
- **doNotClaim:** "Who should stay with TimeTree" is mandatory — acknowledge its free-first simplicity and per-event chat for couples who don't need a full household system.

### 12. `cozi`
- **query:** Cozi alternative
- **searchIntent:** switching
- **title:** Best Cozi Alternatives (2026)
- **thesis:** Cozi's core complaint is a paywall that creeps onto features that used to feel free — a 30-day calendar view limit, ads, login/widget failures — so the strongest alternatives are apps whose free tier isn't a time-limited trial of the real product.
- **sections:** Why people search for a Cozi alternative · What Cozi does well (ten-year loyalty is real) · Ranked alternatives · Who should stay with Cozi
- **faq:** "Is Cozi Gold worth it?" · "Why does Cozi look different on Android than iPhone?" · "What's a free alternative to Cozi?" · "Why did Cozi start pushing AI features?"
- **quotes:** "I was really disappointed with this app... Requires $80/yr subscription to use." — Sally Mach E, 2★, App Store US, 2026-08-24. "Charges you to plan 30 days in advance." — ForeignScrews, 1★, "Bad," App Store US, 2026-08-16. "The widget always says I'm signed out even though I'm not." — Josh8877, 1★, "Widget Doesn't Work," App Store US, 2026-08-09. "I have used this app for probably 10 years." — 10Jem, 2★, "Used to be great," App Store US, 2026-07-31 (fair-to-Cozi strength: long loyalty).
- **screenshot:** home.png
- **relatedPages:** /compare/kinrows-vs-cozi, /questions/is-cozi-gold-worth-it, /for/families-who-tried-cozi-and-quit, /best-family-organizer-apps
- **sources:** https://itunes.apple.com/us/rss/customerreviews/id=407108860/sortBy=mostRecent/page=1/json
- **doNotClaim:** Verify Cozi Gold's current price at cozi.com before publishing — the research found conflicting $39 vs $80/yr figures and flags it as unverified; do not assert a specific price without checking.

### 13. `familywall`
- **query:** FamilyWall alternative
- **searchIntent:** switching
- **title:** Best FamilyWall Alternatives (2026)
- **thesis:** FamilyWall's most common complaint by far is instability — crashes right after updates, broken invite flows that block onboarding entirely — so the strongest alternatives are apps that let every household member actually get in and stay in.
- **sections:** Why people search for a FamilyWall alternative · What FamilyWall does well (elder-care coordination is genuinely praised) · Ranked alternatives · Who should stay with FamilyWall
- **faq:** "Why does FamilyWall keep crashing after an update?" · "How do I leave a FamilyWall Circle?" · "Is FamilyWall really free?" · "What's a more stable alternative to FamilyWall?"
- **quotes:** "App keeps crashing after latest update. So annoying!" — Sjy919, 1★, App Store US, 2026-08-24. "Would not let me invite my family members or even join other circles... Would not recommend." — Gabescaptive, 1★, "Unusable," App Store US, 2026-07-05. "Complains about requiring paid subscription to add even one additional family member for basic features." — Jennpom, 1★, "Dumb," App Store US, 2026-09-01. "This app has been a Godsend for our family for the past 4 years... [caring for aging parent]" — Eileen Pup, 5★, App Store US, 2026-09-13 (fair-to-FamilyWall strength).
- **screenshot:** home.png
- **relatedPages:** /compare/kinrows-vs-familywall, /for/caregivers-of-ageing-parents, /best-family-organizer-apps
- **sources:** https://itunes.apple.com/us/rss/customerreviews/id=496889629/sortBy=mostRecent/page=1/json and page=2
- **doNotClaim:** Do not claim a specific crash-rate advantage over FamilyWall — no comparative data exists; stick to citing FamilyWall's own reviewers.

### 14. `skylight`
- **query:** Skylight Calendar alternative
- **searchIntent:** switching
- **title:** Best Skylight Calendar Alternatives (2026)
- **thesis:** Skylight pairs $170–$630 hardware with a subscription needed to unlock meal planning and chore rewards, so the strongest alternatives for most households are ones that deliver the same shared-planning function without the upfront hardware cost.
- **sections:** Why people search for a Skylight alternative · What Skylight does well (the always-on display is real) · Ranked alternatives · Who should stick with Skylight
- **faq:** "Is Skylight Calendar worth it?" · "Do I need the Skylight subscription?" · "Is there a family calendar without buying hardware?" · "Why won't my Skylight app connect to my work schedule?"
- **quotes:** "Don't see the value of paying for an annual subscription for such an inferior implementation." — JAinDC, 2★, App Store US, 2026-08-31. "Criticizes subscription model for photo display and billing difficulties." — Zacblack09, 1★, "Cash Grab," App Store US, 2026-09-05. "Extensive feedback on technical problems including duplicate display items, task scheduling bugs, and interface lag." — fizzypop80, 3★, "Glitchy and not intuitive," App Store US, 2026-09-04.
- **screenshot:** home.png
- **relatedPages:** /compare/kinrows-vs-skylight, /questions/is-skylight-calendar-worth-it, /how-to/get-a-family-command-center-without-buying-hardware
- **sources:** https://itunes.apple.com/us/rss/customerreviews/id=1438779037/sortBy=mostRecent/page=1/json and page=2
- **doNotClaim:** "Who should stick with Skylight" is mandatory — the always-visible wall display and multi-kid schedule centralization are genuine, cited strengths a phone app can't fully replace.

### 15. `ourhome`
- **query:** OurHome alternative
- **searchIntent:** switching / navigational
- **title:** Best OurHome Alternatives (2026)
- **thesis:** The original OurHome chores app appears to have stopped receiving updates since 2022 and its points-sync between phones is reported as broken, so families are searching for an actively maintained chores-and-rewards app rather than trying to keep an abandoned one working.
- **sections:** What happened to OurHome · What OurHome did well when it was active · Ranked alternatives · A note on other family apps that have shut down (Picniic)
- **faq:** "Is OurHome still supported or being updated?" · "Why isn't OurHome syncing between phones?" · "Is there more than one OurHome app?" · "What's a good free chore and allowance app for families?"
- **quotes:** "no updates recorded since 2022" — paraphrased via choresplit.com/compare/ourhome (secondary source, attribute as such, not a direct developer statement). "the points system stopped syncing between phones, with kids losing motivation when their progress disappeared" — paraphrased, aggregated via WebSearch. "The app has been discontinued, and the site no longer works" — Picniic, paraphrased secondary-source summary, used here as a "this has happened before" aside, not the page's main subject.
- **screenshot:** tasks.png
- **relatedPages:** /how-to/decide-whether-to-tie-allowance-to-chores, /questions/how-much-allowance-should-i-give-my-kid-by-age, /best-chore-app-for-families
- **sources:** https://choresplit.com/compare/ourhome ; https://apps.apple.com/us/app/ourhome-by-elusios/id6753957205 ; https://alternativeto.net/software/picniic/
- **doNotClaim:** Keep every OurHome claim clearly labeled as paraphrased/secondary-source (the research could not retrieve verbatim App Store reviews) — do not present these as direct quotes.

---

## compare — `/compare/kinrows-vs-<slug>`

### 16. `kinrows-vs-cozi`
- **query:** Kinrows vs Cozi
- **searchIntent:** commercial
- **title:** Kinrows vs Cozi: Which Should You Choose?
- **thesis:** Cozi is the most established free-first family calendar and list app; Kinrows is a newer, broader household system whose entire core (not just the calendar) is free and whose optional AI layer never trains on your data — the honest choice depends on whether you want Cozi's long track record or Kinrows' wider free feature set.
- **sections:** What each app actually is · Side-by-side comparison table · Choose Cozi if... · Choose Kinrows if...
- **faq:** "Is Cozi or Kinrows better for families?" · "Is Cozi Gold worth it compared to Kinrows' free tier?" · "Does either app show ads?" · "Which app is more established?"
- **quotes:** "Requires $80/yr subscription to use." — Sally Mach E, Cozi, 2★, App Store US, 2026-08-24. "I have used this app for probably 10 years." — 10Jem, Cozi, 2★, App Store US, 2026-07-31 (fair-to-Cozi).
- **screenshot:** home.png
- **relatedPages:** /alternatives/cozi, /questions/is-cozi-gold-worth-it, /compare, /best-family-organizer-apps
- **sources:** https://itunes.apple.com/us/rss/customerreviews/id=407108860/sortBy=mostRecent/page=1/json
- **doNotClaim:** Do not claim Kinrows has more total users or a longer track record than Cozi — Cozi's decade-plus tenure is real and should be stated plainly.

### 17. `kinrows-vs-timetree`
- **query:** Kinrows vs TimeTree
- **searchIntent:** commercial
- **title:** Kinrows vs TimeTree: Which Should You Choose?
- **thesis:** TimeTree is a free, ad-supported pure scheduling app popular with couples; Kinrows is a paid-optional broader household system that never trains AI on your data — choose TimeTree for the simplest possible shared calendar, Kinrows if you want lists, chores, budget and care coordination in the same place with a stated no-AI-training policy.
- **sections:** What each app actually is · Side-by-side comparison table · Choose TimeTree if... · Choose Kinrows if...
- **faq:** "Does TimeTree use my calendar data to train AI?" · "Is TimeTree or Kinrows better for couples?" · "Which app has ads?" · "What happened to users' TimeTree calendars?"
- **quotes:** "Former user deleting account over AI concerns, noting calendar data trains the AI regardless of opt-out." — june ♪(๑ᴖ◡ᴖ๑)♪, TimeTree, 1★, App Store US, 2026-08-22. Credits app with improving relationship and mental health — Stephi Styles, TimeTree, 5★ (fair-to-TimeTree).
- **screenshot:** concierge-ask.png
- **relatedPages:** /alternatives/timetree, /questions/do-family-calendar-apps-use-my-data-to-train-ai, /how-to/move-off-a-family-calendar-app-that-deleted-your-events
- **sources:** https://itunes.apple.com/us/rss/customerreviews/id=952578473/sortBy=mostRecent/page=1/json
- **doNotClaim:** Do not claim TimeTree's per-event chat/comments feature has a direct Kinrows equivalent — Messages and Decisions are a different shape; describe the difference honestly rather than claiming parity.

### 18. `kinrows-vs-familywall`
- **query:** Kinrows vs FamilyWall
- **searchIntent:** commercial
- **title:** Kinrows vs FamilyWall: Which Should You Choose?
- **thesis:** FamilyWall packs a broad feature set (calendar, tasks, photos, location, finance, messaging) into one app and is praised for elder-care coordination, but is dogged by crashes and broken invite flows; Kinrows covers similar ground with a different reliability profile and household/clan model, at the cost of FamilyWall's photo-album and location-sharing depth.
- **sections:** What each app actually is · Side-by-side comparison table · Choose FamilyWall if... · Choose Kinrows if...
- **faq:** "Is FamilyWall or Kinrows more reliable?" · "Which is better for elder-care coordination?" · "How do invite/circle flows compare?" · "Is FamilyWall really free?"
- **quotes:** "App keeps crashing after latest update. So annoying!" — Sjy919, FamilyWall, 1★, App Store US, 2026-08-24. "This app has been a Godsend for our family for the past 4 years... [caring for aging parent]" — Eileen Pup, FamilyWall, 5★, App Store US, 2026-09-13 (fair-to-FamilyWall).
- **screenshot:** home.png
- **relatedPages:** /alternatives/familywall, /for/caregivers-of-ageing-parents, /best-family-organizer-apps
- **sources:** https://itunes.apple.com/us/rss/customerreviews/id=496889629/sortBy=mostRecent/page=1/json
- **doNotClaim:** Do not claim Kinrows matches FamilyWall's photo-album or location-sharing feature depth — llms-full.txt does not document a photo-album feature or live location sharing beyond trip ETA.

### 19. `kinrows-vs-skylight`
- **query:** Kinrows vs Skylight
- **searchIntent:** commercial
- **title:** Kinrows vs Skylight: Which Should You Choose?
- **thesis:** Skylight is a physical wall display with genuine ambient visibility that a phone app can't replicate, paired with hardware cost and a subscription for extras; Kinrows is a phone-first, hardware-free system where the app is the whole product, not a companion to a screen on the wall.
- **sections:** What each app/device actually is · Side-by-side comparison table · Choose Skylight if... · Choose Kinrows if...
- **faq:** "Is Skylight Calendar worth the hardware cost?" · "Do I need a wall display, or does a phone app work as well?" · "What does the Skylight subscription unlock?"
- **quotes:** "Don't see the value of paying for an annual subscription for such an inferior implementation." — JAinDC, Skylight, 2★, App Store US, 2026-08-31.
- **screenshot:** home.png
- **relatedPages:** /alternatives/skylight, /questions/is-skylight-calendar-worth-it, /how-to/get-a-family-command-center-without-buying-hardware
- **sources:** https://itunes.apple.com/us/rss/customerreviews/id=1438779037/sortBy=mostRecent/page=2/json
- **doNotClaim:** Do not claim a phone app is strictly better for every household — for families who specifically want an always-on shared screen visible without picking up a phone, say plainly that a physical display is the better fit.

### 20. `kinrows-vs-anylist`
- **query:** Kinrows vs AnyList
- **searchIntent:** commercial
- **title:** Kinrows vs AnyList: Which Should You Choose?
- **thesis:** AnyList is a mature, single-purpose shared grocery list and recipe manager; Kinrows' Lists and Cook features cover grocery lists and pantry-aware recipe ideas as part of a wider household system — choose AnyList if grocery lists and recipe import are the whole job, Kinrows if you want that connected to calendar, budget and chores too.
- **sections:** What each app actually is (single-purpose vs. whole-household) · Side-by-side comparison table · Choose AnyList if... · Choose Kinrows if...
- **faq:** "Is AnyList or Kinrows better for a shared grocery list?" · "Does Kinrows import recipes like AnyList?" · "Why isn't my AnyList shopping list syncing?"
- **quotes:** "We've used this app for a long time but are growing frustrated with syncing issues... Purchased items are crossed off the list on one phone but still appear as unpurchased on the other." — vtamoeba, AnyList, 2★, App Store US, 2026-07-25.
- **screenshot:** lists.png
- **relatedPages:** /how-to/keep-a-shared-grocery-list-in-sync, /best-shared-shopping-list-app
- **sources:** https://itunes.apple.com/us/rss/customerreviews/id=522167641/sortBy=mostRecent/page=1/json
- **doNotClaim:** Do not claim Kinrows Cook matches AnyList's recipe-import maturity or its (lost) Alexa integration — Cook generates ideas from pantry inventory, a different mechanism, and Kinrows has no voice-assistant integration.

---

## persona — `/for/<slug>`

### 21. `families-who-tried-cozi-and-quit`
- **query:** quit Cozi, what to use instead
- **searchIntent:** switching
- **title:** For Families Who Tried Cozi and Quit
- **thesis:** If you left Cozi over a paywall that crept onto features that used to feel free, or a widget/login that stopped working, the honest question isn't "which app has more features" but "which one won't do that again" — and that starts with knowing exactly what's free forever versus what's optional.
- **sections:** Why people quit Cozi (in their own words) · What "free forever" means at Kinrows, specifically · Bringing your calendar and lists back over · What Cozi still does well, for households it still fits
- **faq:** "Why do people quit Cozi?" · "Is Kinrows really free, or does it paywall things later?" · "How do I move my Cozi calendar and lists to a new app?"
- **quotes:** "I was really disappointed with this app. Even after paying for the..." — Sally Mach E, 2★, "Requires $80/yr subscription to use," App Store US, 2026-08-24. "I have used this app for probably 10 years. But they only changes..." — 10Jem, 2★, "Used to be great," App Store US, 2026-07-31. "It seems like all the update are pushing more AI into this app" — llburgess, 2★, "Too many changes," App Store US, 2026-09-11.
- **screenshot:** home.png
- **relatedPages:** /alternatives/cozi, /compare/kinrows-vs-cozi, /questions/is-cozi-gold-worth-it
- **sources:** https://itunes.apple.com/us/rss/customerreviews/id=407108860/sortBy=mostRecent/page=1/json
- **doNotClaim:** Do not disparage Cozi as a company — stick to what its own reviewers said; acknowledge the ten-year loyalty many users describe before it eroded.

### 22. `families-with-a-newborn`
- **query:** family organizer for new parents / app for new parents
- **searchIntent:** informational
- **title:** For Families With a Newborn
- **thesis:** The first months with a newborn are less about a single big feature and more about a dozen small logistics — who's covering the next feeding shift, when the last diaper change was, what to tell a grandparent who's helping out — which is why a newborn-stage household benefits most from care coverage and shared notes, not a dedicated "baby app."
- **sections:** What actually changes in the first months · Sharing night-shift and care coverage without 30 texts · A living version of "here's what the baby needs" for helpers · Logging the small things that matter later (milestones)
- **faq:** "What's the best way to organize help in the first months with a newborn?" · "How do I coordinate night shifts and visitors without a group chat?" · "Does this replace a sleep-training plan?"
- **quotes:** none specific to newborns in the research set — this page is a product-fit page grounded in `llms-full.txt` (Care coverage, Routines, People & gifts milestone logging), not a complaint-cluster page. Do not fabricate a quote to fill this gap.
- **screenshot:** care.png
- **relatedPages:** /blog/how-to-sleep-train-a-baby, /how-to/babysitter-information-sheet, /for/single-parents
- **sources:** none beyond `website/llms-full.txt`.
- **doNotClaim:** This page must not duplicate `/blog/how-to-sleep-train-a-baby` — keep this page to logistics/coordination, and link to the sleep-training post rather than re-explaining the method.

### 23. `single-parents`
- **query:** app to help single parents manage the household
- **searchIntent:** informational
- **title:** For Single Parents Running a Household Solo
- **thesis:** Running a household without a co-parent to split the mental load with means the "who's tracking this" question has one answer by default, which is why a single parent benefits most from a support network they can pull in for specific coverage — a sitter, a grandparent, a friend — without handing over the whole household.
- **sections:** Why the mental-load problem looks different with one adult in the house · Building a care network without merging your whole household · What to share with helpers, and what stays private · Kids' chores and routines when there's one parent running them
- **faq:** "What's the best way for a single parent to organize household logistics?" · "How do I get help from family or friends without giving them full access to my household?" · "Can kids' chores and allowance still work with one parent managing it?"
- **quotes:** none specific to single parents in the research set. The "mental-load carrier" persona in `default-tools.md` is the closest evidence and applies generally, not single-parent-specifically — do not overstate the match.
- **screenshot:** care.png
- **relatedPages:** /blog/sharing-the-mental-load, /how-to/babysitter-information-sheet, /for/grandparents-in-the-loop
- **sources:** none page-specific beyond `default-tools.md`'s general mental-load research.
- **doNotClaim:** Do not claim Kinrows has any single-parent-specific feature (there isn't one) — the page's value is showing how existing features (Care coverage, Clans, Notes) apply to this situation, not a dedicated mode.

### 24. `blended-and-co-parenting-families`
- **query:** app for co-parenting schedule across two homes
- **searchIntent:** commercial
- **title:** For Blended and Co-Parenting Families
- **thesis:** Kinrows is not a custody-record or legal-communication system built for adversarial co-parenting — for that, purpose-built tools like OurFamilyWizard exist — but for co-parents on cooperative terms who need a shared calendar and lists visible across two homes without merging every other part of family life, the household/clan model can help.
- **sections:** What a dedicated co-parenting app does that Kinrows doesn't · Where a shared calendar across two homes still helps · Keeping each home's other data (budget, notes) separate · When to use a court-recommended co-parenting app instead
- **faq:** "Is Kinrows good for co-parenting or custody schedules?" · "What's the difference between Kinrows and a dedicated co-parenting app?" · "Can two households share a calendar without merging everything else?"
- **quotes:** "handles complex custody schedules that other family calendar apps can't manage" — KidCal product-positioning phrase, cited as an example of what the *category leaders* claim, not what Kinrows claims. Named comparison set for context: OurFamilyWizard, TalkingParents, 2houses, KidCal, Pairently, Kidtime.
- **screenshot:** calendar.png
- **relatedPages:** /how-to/share-a-family-calendar-with-a-partner-who-wont-use-it, /for/grandparents-in-the-loop, /best-family-calendar-app
- **sources:** `questions-and-problems.md` §10 (named-app pattern only, no single citable URL).
- **doNotClaim:** This is the single most important "do not claim" page in the backlog: no custody-record, court-admissible logging, or legal-communication feature exists in Kinrows. State this explicitly and point cooperative co-parents to what does work (shared calendar) rather than implying feature parity with OurFamilyWizard-class tools.

### 25. `caregivers-of-ageing-parents`
- **query:** help aging parents from a distance / long-distance caregiving app
- **searchIntent:** informational
- **title:** For Caregivers of Ageing Parents From a Distance
- **thesis:** Long-distance caregiving is currently underserved by dedicated apps relative to how much people search for it, and while Kinrows has no medication-tracking or health-monitoring feature, a separate clan for an ageing parent's circle plus shared notes can hold the practical, non-medical information a distant adult child actually needs.
- **sections:** What long-distance caregiving actually requires day to day · What Kinrows does not do (be upfront about this) · A separate circle for a parent's care network · Practical information worth keeping in one shared place
- **faq:** "What's the best way to help an aging parent from a distance?" · "Does Kinrows track medications or health information?" · "How do I coordinate with siblings or other caregivers?"
- **quotes:** "long-distance caregiving" (established term of art); "meeting neighbors and getting their contact information," "gathering copies of insurance cards and medical history," "set a specific day and time each week for a video call" — practical checklist phrasing pattern, aggregated via WebSearch per `questions-and-problems.md` §11.
- **screenshot:** home.png
- **relatedPages:** /for/grandparents-in-the-loop, /how-to/keep-grandparents-in-the-loop-without-sharing-everything, /for/blended-and-co-parenting-families
- **sources:** none with a specific citable URL — flagged in research as a content opportunity rather than a feature-match, keep the tone accordingly (a guide, not a product pitch).
- **doNotClaim:** Explicitly state Kinrows has no medication-tracking or elder-health-monitoring feature — this page's honesty about the gap is what makes it defensible; do not imply Care coverage is built for medical needs.

### 26. `couples-without-kids`
- **query:** shared calendar and grocery list app for couples
- **searchIntent:** informational
- **title:** For Couples Without Kids
- **thesis:** A couple running a shared household doesn't need chore charts or sleep-training programs — the answer for them is narrower: one calendar, one grocery list, and a shared view of money, without the kid-specific features cluttering the picture.
- **sections:** What actually matters for a two-person household · Calendar and lists without the kid-specific noise · Splitting or tracking shared expenses · When it's worth adding more (moving in, planning a family)
- **faq:** "What's the best shared calendar and grocery list app for couples?" · "Do we need a full family organizer if it's just the two of us?" · "How do couples track shared expenses in the same app as everything else?"
- **quotes:** none specific — this cluster (`questions-and-problems.md` §3, §8) is transactional/tool-seeking with pattern-level evidence, not individual quotes.
- **screenshot:** lists.png
- **relatedPages:** /how-to/keep-a-shared-grocery-list-in-sync, /blog/family-budgeting-without-friction, /best-shared-shopping-list-app
- **sources:** none page-specific beyond `questions-and-problems.md` §3 and §8 patterns.
- **doNotClaim:** Do not push kid-specific features (chores, routines, sleep training) onto this persona — the point of the page is that the answer is narrower, not "everything, just in case."

### 27. `grandparents-in-the-loop`
- **query:** keep grandparents updated on the family
- **searchIntent:** informational
- **title:** For Keeping Grandparents in the Loop
- **thesis:** Grandparents usually don't need — or want — access to a household's budget or private notes; what they want is milestones, photos, and select plans, which is exactly what a separate clan (rather than adding them to the household itself) is built for.
- **sections:** Why adding grandparents to the household oversharres · What a clan is instead · What's worth sharing (milestones, photos, key dates) · Making it easy for a grandparent who isn't tech-savvy
- **faq:** "Should grandparents be added to the family household or a separate group?" · "What's the easiest way for a grandparent to stay updated without learning a new app?" · "Can grandparents see budgets or private notes by accident?"
- **quotes:** "long-distance caregiving" (established term of art), per `questions-and-problems.md` §11 — same underlying research as #10 and #25; do not restate their content verbatim, differentiate this page by focusing on the *sharing model* (clans) rather than caregiving logistics.
- **screenshot:** home.png
- **relatedPages:** /how-to/keep-grandparents-in-the-loop-without-sharing-everything, /for/caregivers-of-ageing-parents, /for/big-families
- **sources:** none beyond `questions-and-problems.md` §11 pattern.
- **doNotClaim:** Do not claim the household/clan boundary is impossible to misconfigure — describe it accurately as "groups only overlap through shared members" per llms-full.txt, without overstating foolproofness.

### 28. `parents-of-toddlers`
- **query:** chore chart for toddlers
- **searchIntent:** informational
- **title:** For Parents of Toddlers
- **thesis:** Chores for a 2–5-year-old are about building the habit, not earning money — a tappable morning/evening routine with simple, age-appropriate tasks works better than an allowance system a toddler can't meaningfully understand yet.
- **sections:** What "chores" means at 2–5 (habit, not income) · Age-appropriate tasks for this stage · Why allowance usually starts later · Keeping it non-punitive at this age
- **faq:** "What chores are appropriate for a toddler?" · "Should a 3-year-old get an allowance?" · "How do I make a chore chart a toddler will actually use?"
- **quotes:** none toddler-specific in the research set — grounded in `llms-full.txt`'s documented age bands (2–3, 4–5), not a complaint cluster.
- **screenshot:** tasks.png
- **relatedPages:** /how-to/decide-whether-to-tie-allowance-to-chores, /for/parents-of-teens, /best-chore-app-for-families
- **sources:** research citations already in `llms-full.txt` (Rossmann 2002; White et al. 2019; Warneken & Tomasello 2008; Deci, Koestner & Ryan 1999) — cite by name/year, do not invent additional sources.
- **doNotClaim:** Do not suggest a fixed weekly allowance is appropriate at this age unless llms-full.txt's age-band guidance is checked — keep specific dollar amounts out unless sourced from the app's own documented program.

### 29. `parents-of-teens`
- **query:** allowance and chores for teenagers
- **searchIntent:** informational
- **title:** For Parents of Teens
- **thesis:** By the teen years, chores and allowance shift from habit-building to a closer approximation of real responsibility and real money — bigger allowance bands, optional bonuses for consistency, and enough autonomy that it doesn't feel like a toddler's chart with higher numbers.
- **sections:** How chores and allowance change by the teen years · What's a reasonable allowance range at this age · Behaviour bonuses vs. a fixed base amount · Money and gift tracking as teens start to have more of both
- **faq:** "How much allowance should a teenager get?" · "Should teenage chores work differently than younger kids'?" · "What's a fair way to add bonuses without turning it into a negotiation every week?"
- **quotes:** "$2.00 to $5.00 for ages 12 and up" — aggregated age-banded price phrasing pattern from `questions-and-problems.md` §5, cite as a pattern across multiple chore-chart sources, not a single URL.
- **screenshot:** tasks.png
- **relatedPages:** /questions/how-much-allowance-should-i-give-my-kid-by-age, /how-to/decide-whether-to-tie-allowance-to-chores, /for/parents-of-toddlers
- **sources:** `llms-full.txt` age-band citations (Rossmann 2002; White et al. 2019; Warneken & Tomasello 2008; Deci, Koestner & Ryan 1999).
- **doNotClaim:** Do not present a single "correct" allowance number for teens — the research shows a range across sources; present Kinrows' guidance as one defensible approach, not the only one.

### 30. `big-families`
- **query:** organizer app for a big family with several kids
- **searchIntent:** informational
- **title:** For Big Families With Several Kids
- **thesis:** The more kids in a household, the more a single shared calendar or list turns into an unreadable wall of entries unless each person has their own color and their own profile — which is exactly the gap reviewers of hardware displays credit those products for closing, and a per-person system on a phone can close the same way.
- **sections:** Why a big family's calendar gets unreadable fast · Per-person color coding and profiles at scale · Splitting chores and allowance across several kids without it becoming a spreadsheet · Keeping the family feed useful when there's a lot happening
- **faq:** "How do you keep a family calendar readable with four or five kids on it?" · "Can chores and allowance work differently for each kid?" · "Is there a family organizer built for larger households specifically?"
- **quotes:** Third-party reviewers of Skylight "consistently praise it for centralizing multiple kids' schedules" — paraphrased overview claim from `complaints-skylight.md`, cite as a general pattern, not a specific verbatim review, since the underlying source is a synthesized overview line.
- **screenshot:** calendar.png
- **relatedPages:** /how-to/turn-family-group-chat-into-a-plan, /for/parents-of-toddlers, /for/parents-of-teens
- **sources:** none with a specific URL — the Skylight overview claim in `complaints-skylight.md` is itself a paraphrase of aggregated third-party review sentiment (cybernews.com, tasteofhome.com, theeverymom.com, decoratorsvoice.com).
- **doNotClaim:** Do not claim a specific number of "supported" children or profiles — llms-full.txt doesn't document a cap or limit either way; describe the per-person color coding and People profiles factually without inventing a scale claim.

---

## question — `/questions/<slug>`

### 31. `why-does-my-shared-calendar-not-show-on-my-partners-phone`
- **query:** why doesn't my shared calendar show on my partner's phone
- **searchIntent:** troubleshooting
- **title:** Why Doesn't My Shared Calendar Show on My Partner's Phone?
- **thesis:** This is almost always a permission-sharing problem, not a bug: apps like Google Calendar share a personal calendar with view/edit permissions rather than creating one calendar both people natively belong to, so events can lag, fail to appear, or show only on the device where they were entered.
- **sections:** Why this happens (permission-sharing vs. a native shared calendar) · How to check your current sharing settings · What a native shared calendar does differently
- **faq:** "Why can't my partner see events I add to our shared calendar?" · "Why do events show on the web but not on mobile?" · "Is this fixable, or is it a limitation of the app?"
- **quotes:** "My family can't see my events I added to shared calendar. I can see theirs." — Google Calendar Community thread title, https://support.google.com/calendar/thread/17626208. "Google Calendar events disappear from phone, show up fine on website" — forums.anandtech.com thread title.
- **screenshot:** calendar.png
- **relatedPages:** /how-to/share-a-family-calendar-with-a-partner-who-wont-use-it, /best-family-calendar-app
- **sources:** https://support.google.com/calendar/thread/17626208 ; https://forums.anandtech.com/threads/google-calendar-events-disappear-from-phone-show-up-fine-on-website.2168205
- **doNotClaim:** Do not claim Kinrows has diagnosed or fixed a specific Google Calendar bug — describe the general permission-sharing-vs-native-calendar distinction, which is accurate regardless of the specific app.

### 32. `why-is-my-shared-grocery-list-not-syncing`
- **query:** why isn't my grocery list updating on my partner's phone
- **searchIntent:** troubleshooting
- **title:** Why Isn't My Grocery List Updating on My Partner's Phone?
- **thesis:** A shared list that shows different contents on different phones is usually relying on local caching or best-effort background sync rather than a single server copy every device reads live, which is why the same list can look "crossed off" on one phone and "still there" on another.
- **sections:** What's actually happening when a list looks out of sync · Quick things to check (connectivity, app version, re-adding the list) · Why a server-scoped list avoids this by design
- **faq:** "Why do items get crossed off on one phone but not another?" · "Why does my list show duplicate items after adding something?" · "Is there a shared list that syncs reliably?"
- **quotes:** "Purchased items are crossed off the list on one phone but still appear as unpurchased on the other." — vtamoeba, AnyList, 2★, App Store US, 2026-07-25. "Then hours later, when I went to look at the list on my phone, it had not yet crossed over.. So we opened his list up again... and his list flickered and disappeared." — 2thomps, AnyList, 1★, App Store US, 2026-08-22.
- **screenshot:** lists.png
- **relatedPages:** /how-to/keep-a-shared-grocery-list-in-sync, /compare/kinrows-vs-anylist
- **sources:** https://itunes.apple.com/us/rss/customerreviews/id=522167641/sortBy=mostRecent/page=1/json
- **doNotClaim:** Do not claim Kinrows lists have zero sync latency — describe the server-scoped architecture accurately without an absolute reliability guarantee.

### 33. `do-family-calendar-apps-use-my-data-to-train-ai`
- **query:** does TimeTree use my calendar data to train AI
- **searchIntent:** informational / trust
- **title:** Does TimeTree Use My Calendar Data to Train AI?
- **thesis:** Multiple recent TimeTree reviewers report that the app's AI features use calendar data for training regardless of opt-out attempts, which is the reason a concentrated group of long-time users have deleted their accounts — anyone concerned about this should look for an explicit, published no-training policy rather than taking an opt-out toggle at face value.
- **sections:** What TimeTree reviewers are reporting · Why an opt-out toggle isn't the same as a no-training policy · What to look for in an alternative's privacy stance
- **faq:** "Do TimeTree's AI features train on my calendar data?" · "Does opting out of AI actually stop TimeTree from using my data?" · "What's a family calendar app with a clear no-data-training policy?"
- **quotes:** "Former user deleting account over AI concerns, noting calendar data trains the AI regardless of opt-out." — june ♪(๑ᴖ◡ᴖ๑)♪, TimeTree, 1★, "added AI," App Store US, 2026-08-22. "Criticizes forced AI adoption and notes that opting out preferences don't save properly." — GodisntReal:), TimeTree, 1★, "AI Ruined the App," App Store US, 2026-08-31.
- **screenshot:** concierge-ask.png
- **relatedPages:** /alternatives/timetree, /compare/kinrows-vs-timetree
- **sources:** https://itunes.apple.com/us/rss/customerreviews/id=952578473/sortBy=mostRecent/page=1/json
- **doNotClaim:** Report only what TimeTree's own reviewers say — Kinrows has no independent verification of TimeTree's actual data-training practices beyond these reviews; state that clearly rather than presenting reviewer claims as confirmed fact.

### 34. `how-much-allowance-should-i-give-my-kid-by-age`
- **query:** how much allowance by age
- **searchIntent:** informational
- **title:** How Much Allowance Should I Give My Kid, by Age?
- **thesis:** Commonly cited ranges run roughly $0.50–$1.00 per task for ages 6–8, $1.00–$2.50 for ages 9–11, and $2.00–$5.00 for ages 12 and up, though there's no single "correct" number — what matters more than the exact amount is whether it's paid consistently and not docked for a missed chore.
- **sections:** Common allowance ranges by age · Per-task vs. a fixed weekly amount · What the research says about docking pay for missed chores
- **faq:** "How much allowance should a 6-year-old get?" · "How much allowance is normal for a 9 to 11-year-old?" · "Should allowance go up automatically with age?" · "Should I dock allowance for a missed chore?"
- **quotes:** "$0.50 to $1.00 per task for ages 6 to 8," "$1.00 to $2.50 for ages 9 to 11," "$2.00 to $5.00 for ages 12 and up" — aggregated age-band price phrasing pattern from `questions-and-problems.md` §5.
- **screenshot:** tasks.png
- **relatedPages:** /how-to/decide-whether-to-tie-allowance-to-chores, /for/parents-of-toddlers, /for/parents-of-teens
- **sources:** `llms-full.txt` chores research citations (Rossmann 2002; White et al. 2019; Warneken & Tomasello 2008; Deci, Koestner & Ryan 1999).
- **doNotClaim:** Present the dollar ranges as commonly-cited figures from parenting content, not as a Kinrows-endorsed standard — Kinrows' own stance (fixed weekly allowance, never docked) is one specific position within this range, not "the answer."

### 35. `is-there-an-ai-that-can-manage-my-family-calendar`
- **query:** is there an AI that can manage my family calendar
- **searchIntent:** commercial
- **title:** Is There an AI That Can Actually Manage My Family Calendar?
- **thesis:** Most "AI calendar" features only summarize or suggest — an AI assistant that can actually move a dentist appointment, add and remove grocery items, or send a message on your behalf needs write access across the whole household system, not just the calendar, which is a meaningfully different (and rarer) kind of product.
- **sections:** Why most AI calendar features are read-only · What it takes for an AI to actually make changes, not just suggest them · What this looks like in practice
- **faq:** "Can an AI assistant actually move or edit my calendar events, not just suggest them?" · "Is an AI family assistant safe to give real access to?" · "What can an AI concierge actually do besides answer questions?"
- **quotes:** none from the competitor complaint files — this page is grounded directly in `llms-full.txt`'s Concierge section (full create/edit/delete/move across 22 tool domains, 100+ actions) rather than a complaint cluster.
- **screenshot:** concierge-ask.png
- **relatedPages:** /alternatives/timetree, /for/families-who-tried-cozi-and-quit, /best-family-organizer-apps
- **sources:** `website/llms-full.txt` Concierge section.
- **doNotClaim:** Do not claim the Concierge is infallible or requires no confirmation for sensitive actions — llms-full.txt states guardrails exist (household-scoped, consent-sensitive actions stay behind explicit UI taps); represent that accurately rather than overselling autonomy.

### 36. `is-cozi-gold-worth-it`
- **query:** is Cozi Gold worth it
- **searchIntent:** commercial
- **title:** Is Cozi Gold Worth It?
- **thesis:** Cozi Gold removes ads and unlocks the full calendar view and other features that are otherwise capped or ad-supported on the free tier, so whether it's worth it depends mainly on how much the 30-day view limit and ads bother you — for households that want the same functionality with no paid tier at all, that's worth comparing against free-forever alternatives before paying.
- **sections:** What Cozi Gold actually unlocks · What free-tier Cozi still limits · How this compares to apps with no paid calendar/list tier at all
- **faq:** "What does Cozi Gold include that the free version doesn't?" · "How much does Cozi Gold cost?" · "Is there a free alternative to Cozi Gold?"
- **quotes:** "I was really disappointed with this app. Even after paying for the... Requires $80/yr subscription to use." — Sally Mach E, 2★, App Store US, 2026-08-24. "Charges you to plan 30 days in advance." — ForeignScrews, 1★, "Bad," App Store US, 2026-08-16.
- **screenshot:** home.png
- **relatedPages:** /alternatives/cozi, /compare/kinrows-vs-cozi, /for/families-who-tried-cozi-and-quit
- **sources:** https://itunes.apple.com/us/rss/customerreviews/id=407108860/sortBy=mostRecent/page=1/json
- **doNotClaim:** Verify Cozi Gold's actual current price at cozi.com before publishing — research found conflicting $39/yr (third-party pricing sites) vs $80/yr (a reviewer's figure, possibly a legacy/bundled tier) and could not confirm which is current.

### 37. `is-skylight-calendar-worth-it`
- **query:** is Skylight Calendar worth it
- **searchIntent:** commercial
- **title:** Is Skylight Calendar Worth It?
- **thesis:** Skylight's hardware ($170–$630) buys an always-on shared display that reviewers credit with calming family planning, but several of its most useful extras — meal planning, chore rewards — sit behind an optional ~$79/year subscription, so "worth it" depends on whether the ambient display alone justifies the upfront cost without the subscription.
- **sections:** What you get from the hardware alone · What's locked behind the subscription · Who the hardware cost makes sense for · What to compare it against
- **faq:** "What does the Skylight subscription add that the hardware doesn't?" · "Is Skylight worth it without the subscription?" · "What's a cheaper alternative to Skylight?"
- **quotes:** "Love the calendar itself but trying to manage it via the app is very frustrating... Don't see the value of paying for an annual subscription for such an inferior implementation." — JAinDC, 2★, App Store US, 2026-08-31. Third-party paraphrase: "some of its most appealing extras, like meal planning and chore rewards, are locked behind an optional subscription" (cybernews.com / theeverymom.com).
- **screenshot:** home.png
- **relatedPages:** /alternatives/skylight, /compare/kinrows-vs-skylight, /how-to/get-a-family-command-center-without-buying-hardware
- **sources:** https://itunes.apple.com/us/rss/customerreviews/id=1438779037/sortBy=mostRecent/page=2/json
- **doNotClaim:** Give Skylight's genuine strength (always-on ambient display, multi-kid schedule centralization per third-party reviews) fair weight — this is a "worth it" question, not an alternatives pitch, so the honest answer may be "yes, for some households."

### 38. `what-information-should-i-leave-for-a-babysitter`
- **query:** what information to leave for a babysitter
- **searchIntent:** informational
- **title:** What Information Should I Leave for a Babysitter?
- **thesis:** At minimum, a babysitter needs emergency contacts, any allergies or medications, the house/wifi basics, bedtime and routine notes, and how to reach you — a fixed printed list works for one evening, but it goes stale the moment plans change, which is the main reason people search for a better format than a printable.
- **sections:** The core information every sitter needs · What changes evening to evening (and why that's the hard part) · A version that stays current instead of a fixed printout
- **faq:** "What should be on a babysitter information sheet?" · "What do I need to tell a new babysitter before they arrive?" · "Is a printable babysitter sheet good enough?"
- **quotes:** "Free Printable Babysitter's Information Guide" / "Babysitting Checklist (Free Printable)" / "The Ultimate Grandparents' Emergency Babysitting Checklist" — recurring search-result title pattern, `questions-and-problems.md` §4.
- **screenshot:** care.png
- **relatedPages:** /how-to/babysitter-information-sheet, /for/single-parents
- **sources:** none beyond the pattern cited in `questions-and-problems.md` §4.
- **doNotClaim:** Do not present this as medical or safety advice — it's a logistics checklist; recommend parents follow their own judgment and any relevant emergency guidance, not a Kinrows-authored safety protocol.

### 39. `is-hearth-display-worth-the-money`
- **query:** is Hearth Display worth it / worth $700
- **searchIntent:** commercial
- **title:** Is Hearth Display Worth the Money?
- **thesis:** Hearth Display costs around $700 for the hardware and roughly $84/year to keep basic functions like to-do lists working, so several of its own reviewers describe it as becoming "the most expensive picture frame" once the subscription lapses — worth it mainly for households certain they'll keep paying the subscription indefinitely.
- **sections:** What Hearth Display costs, hardware and subscription · What stops working if you cancel · What reviewers say after a year of ownership · What to weigh it against
- **faq:** "What happens to Hearth Display if I cancel the subscription?" · "Is Hearth Display worth $700?" · "What's a cheaper alternative to Hearth Display?"
- **quotes:** "We have owned the hearth for a year now, and truly have enjoyed it... Because of canceling we cannot do any of the basic stuff. Like the to dos... Such a waste of money and scam." — Aspencupcake, 1★, "Overly expensive," App Store US, 2025-08-25. "It's the most expensive frame that's just hung on our wall. It hasn't been used in almost a year." — KF2, 1★, "Expensive calendar display," App Store US, 2025-08-18.
- **screenshot:** home.png
- **relatedPages:** /how-to/get-a-family-command-center-without-buying-hardware, /alternatives/skylight
- **sources:** https://itunes.apple.com/us/rss/customerreviews/id=6498717775/sortBy=mostRecent/page=1/json
- **doNotClaim:** Do not claim Kinrows is a substitute for the specific ambient always-on display experience Hearth provides — state the cost/subscription facts and let the comparison speak for itself rather than overclaiming feature parity.

### 40. `should-couples-use-one-app-for-shared-and-personal-money`
- **query:** budgeting apps for couples to manage money together
- **searchIntent:** commercial
- **title:** Should Couples Use One App for Shared and Personal Money?
- **thesis:** Most couples do better with a system that tracks shared household spending in one visible place while keeping personal accounts separate, rather than either fully merging finances in one app or tracking shared costs across scattered receipts and memory — the right setup depends on whether you're asking "what did we spend on the house" or "let's combine everything."
- **sections:** Fully merged vs. shared-only vs. fully separate finances · What a shared household budget needs to track (categories, receipts, recurring costs) · Where this fits alongside the rest of household admin
- **faq:** "Should couples combine all their finances in one app?" · "What's the best way to track shared household spending without merging bank accounts?" · "Does a family organizer app handle budgeting too, or do I need a separate app?"
- **quotes:** none specific — cluster is comparison-shopping among named finance apps (Honeydue, Goodbudget, YNAB, Monnetta cited in `questions-and-problems.md` §8), not a complaint cluster; do not fabricate a review quote.
- **screenshot:** home.png
- **relatedPages:** /blog/family-budgeting-without-friction, /for/couples-without-kids, /best-family-organizer-apps
- **sources:** none page-specific beyond `questions-and-problems.md` §8 (named-app comparison pattern).
- **doNotClaim:** Do not claim Kinrows' Budget feature is a substitute for a dedicated finance app like YNAB for households that want deep financial planning — position it as household expense tracking within a broader organizer, not a full personal-finance product.

## Editorial amendments (2026-09-15)
- Page 33 was renamed from a TimeTree-specific AI-training question to `do-family-calendar-apps-use-my-data-to-train-ai`. The page must answer generically (how to read App Privacy labels and a privacy policy, what "used to train AI" means, questions to ask), may quote reviewer concern about TimeTree only with attribution and only alongside what TimeTree's own published policy says (fetch it; if it cannot be verified, do not name TimeTree), and states Kinrows' own policy from llms-full.txt.
- Slugs shortened for URL quality: `keep-a-shared-grocery-list-in-sync`, `babysitter-information-sheet`, `turn-family-group-chat-into-a-plan`, `keep-grandparents-in-the-loop-without-sharing-everything`, `is-there-an-ai-that-can-manage-my-family-calendar`.
