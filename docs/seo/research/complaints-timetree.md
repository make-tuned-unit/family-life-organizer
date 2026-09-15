# TimeTree — customer complaint & switching-language research

Source note: Reddit was not accessible (fetches to reddit.com were blocked by the tool sandbox; web search did not surface actual Reddit thread text). All quotes below are verbatim from the Apple App Store customer-reviews RSS feed (`https://itunes.apple.com/us/rss/customerreviews/id=952578473/sortBy=mostRecent/page=<N>/json`, US storefront, pages 1–2, fetched 2026-09-15). Third-party comparison articles are cited separately and labeled as such.

## Overview

TimeTree (App Store id 952578473, "TimeTree: Shared Calendar") is a free-first shared calendar with per-event chat/comments, popular with couples and small families for pure scheduling. It's ad-supported on the free tier with a paid ad-removal option, and recently (per its own reviewers, mid-2026) added AI features that a vocal subset of long-time users strongly reject. What it does well, per its reviewers: several long-tenure users (four-plus years, six years) credit it with genuinely improving household communication and even relationship/mental-health outcomes ("Credits app with improving relationship and mental health" — Stephi Styles, 5★).

## Complaint clusters

### 1. Unwanted/forced AI features, including using calendar data to train it
- "Long-time user discontinuing use due to unwanted AI features being integrated into the app." — Tell your mother you love her, 1★, "Nobody wants AI 👎🏽😕," US App Store, 2026-09-04. https://itunes.apple.com/us/rss/customerreviews/id=952578473/sortBy=mostRecent/page=1/json
- "Appreciates app functionality but strongly opposes AI implementation; frustrated that opting out was required." — Fuknheldog, 1★, "Why is ai necessary?," US App Store, 2026-09-03. https://itunes.apple.com/us/rss/customerreviews/id=952578473/sortBy=mostRecent/page=1/json
- "Criticizes forced AI adoption and notes that opting out preferences don't save properly." — GodisntReal:), 1★, "AI Ruined the App," US App Store, 2026-08-31. https://itunes.apple.com/us/rss/customerreviews/id=952578473/sortBy=mostRecent/page=1/json
- "Former user deleting account over AI concerns, noting calendar data trains the AI regardless of opt-out." — june ♪(๑ᴖ◡ᴖ๑)♪, 1★, "added AI," US App Store, 2026-08-22. https://itunes.apple.com/us/rss/customerreviews/id=952578473/sortBy=mostRecent/page=1/json
- "Four-year user deleting app immediately over AI implementation." — (typing...) feature, 1★, "No one wants AI," US App Store, 2026-07-31. https://itunes.apple.com/us/rss/customerreviews/id=952578473/sortBy=mostRecent/page=1/json
- User type: long-tenure couple/family users, privacy-conscious. Intent: **switching** (explicit account deletion language, repeated). Kinrows capability: Concierge AI is opt-in/paid, never forced on free-tier users; llms-full.txt explicitly states "no training of AI models on your content" as a privacy differentiator — direct, honest counter-positioning. Candidate page: **alternative** / **problem** ("timetree alternative without forced AI"). Conversion potential: **very high** — this is the single most concentrated, emotionally-charged, and directly-addressable complaint cluster found across all four competitors; the "trains AI on my data" fear maps precisely onto a stated Kinrows differentiator.

### 2. Ads on the free tier / paywall to remove them
- "excessive pop-up advertisements." — Ted2C, 4★, "Ads," US App Store, 2026-07-30. https://itunes.apple.com/us/rss/customerreviews/id=952578473/sortBy=mostRecent/page=1/json
- "dislikes paywall for ad removal." — shuehenebe, 4★, "Overall decent," US App Store, 2026-07-31. https://itunes.apple.com/us/rss/customerreviews/id=952578473/sortBy=mostRecent/page=1/json
- "too many ads, very annoying. other than that works well." — Meesha1126, 2★, "ads," US App Store, 2026-06-23. https://itunes.apple.com/us/rss/customerreviews/id=952578473/sortBy=mostRecent/page=2/json
- "The ads at the top make the overall calendar hideous. Money hungry app that forces you to pay if you don't want to see ads." — Greetenpug, 1★, "100% NOT worth it," US App Store, 2026-07-06. https://itunes.apple.com/us/rss/customerreviews/id=952578473/sortBy=mostRecent/page=2/json
- User type: general household user. Intent: switching. Kinrows capability: "No ads, no data sale" across the entire free core app (llms-full.txt Differentiator #1). Candidate page: alternative/problem. Conversion potential: high.

### 3. Data loss / sync reliability
- "My entire calendar was randomly wiped out one day! I needed those dates stored on the calendar, they were incredibly important medical appointments and legal due dates and correspondence, and I opened the app one day to find TimeTree deleted all of it! Years of important dates..." — Tehth, 1★, "Timetree deleted everything!," US App Store, 2026-07-22. https://itunes.apple.com/us/rss/customerreviews/id=952578473/sortBy=mostRecent/page=2/json
- "I was using this for a while and was gonna write a good review then today everything just deleted even the shared ones I had with my friends, it started back from new, and I didn't change anything in my phone." — Wismeiry.P, 1★, "Deleted everything," US App Store, 2026-07-12. https://itunes.apple.com/us/rss/customerreviews/id=952578473/sortBy=mostRecent/page=2/json
- "App frequently loses synchronization; user reports manual updates needed almost daily to keep spouse's calendar aligned." — Peter_Da_Purple_PeopleEater, 1★, "Garbage," US App Store, 2026-09-08. https://itunes.apple.com/us/rss/customerreviews/id=952578473/sortBy=mostRecent/page=1/json
- User type: parent/couple relying on the calendar for medical/legal dates — high-stakes use case. Intent: switching (severe trust breach). Kinrows capability: server-scoped household data with parameterized SQL persistence and two-way device calendar sync (not a "never loses data" guarantee — do not overclaim, but reliability/trust is a fair positioning angle). Candidate page: **problem** ("timetree deleted my calendar"). Conversion potential: high, but must be handled carefully/honestly (can't promise zero data loss).

### 4. Billing / cancellation friction
- "I cancelled my subscription and they are still attempting to charge me for it. I contacted Apple who was even worse to deal with. Now I'm unable to download apps on my phone because of this cancelled subscription that I'm not using." — Terrible App for the Price, 1★, "Terrible App for the Price," US App Store, 2026-07-27. https://itunes.apple.com/us/rss/customerreviews/id=952578473/sortBy=mostRecent/page=2/json
- User type: paying subscriber. Intent: switching. Kinrows capability: none specific to billing UX; Apple/Stripe billing per CLAUDE.md. Candidate page: none recommended (too idiosyncratic to Apple's billing system, not really a TimeTree-specific product gap). Conversion potential: low.

### 5. No export / lock-in to Google or Apple Calendar
- "Why can't I export this calendar to something like Google Calendar?? I'm forced to use this one now... Please just use Google calendar or Apple calendar." — Greetenpug, 1★, "100% NOT worth it," US App Store, 2026-07-06. https://itunes.apple.com/us/rss/customerreviews/id=952578473/sortBy=mostRecent/page=2/json
- User type: general user. Intent: switching (actively recommending competitors in the review itself). Kinrows capability: two-way sync with the phone's own calendar (llms-full.txt) — directly relevant, avoids lock-in. Candidate page: alternative. Conversion potential: medium-high.

### 6. Minor UI friction (add-button placement, time zone auto-shift, missing stickers/tasks)
- "Please move the (+) to the bottom toolbar" — • Avid Reader •, 1★, "Add (+)," US App Store, 2026-08-20. https://itunes.apple.com/us/rss/customerreviews/id=952578473/sortBy=mostRecent/page=1/json
- "App automatically changes event times based on different time zones, causing significant frustration." — Bobbie1982, 1★, "Time zone confusion," US App Store, 2026-08-18. https://itunes.apple.com/us/rss/customerreviews/id=952578473/sortBy=mostRecent/page=1/json
- "Misses removed decorative stickers that originally attracted user; app feels generic now." — Cloud Hiccups, 4★, "Missing the stickers:(," US App Store, 2026-09-08. https://itunes.apple.com/us/rss/customerreviews/id=952578473/sortBy=mostRecent/page=1/json
- "Requests task-without-time functionality; suggests 'add task' option alongside event creation." — ChristianNationalist, 3★, "Doesn't do tasks," US App Store, 2026-09-02. https://itunes.apple.com/us/rss/customerreviews/id=952578473/sortBy=mostRecent/page=1/json
- User type: general. Intent: feature request. Kinrows capability: Lists feature covers standalone tasks separate from Calendar events. Candidate page: feature/FAQ. Conversion potential: low-medium.

## Switching & comparison language

- "TimeTree vs Cozi" is a widely-repeated comparison title across independent blogs: cupla.app, kinmory.ai, ourcal.com, listin.gg, theresearchdad.com, usecalendara.com, remindher.app, bsimbframes.com.
- Representative synthesized framing from search results: "TimeTree is a clean, free-first shared calendar with per-event chat; Cozi is a fuller manual family hub." — paraphrase of multiple blog comparisons surfaced for query "timetree vs cozi comparison which is better."
- Explicit switching language from reviewers themselves: "Please just use Google calendar or Apple calendar" (Greetenpug) — a TimeTree user recommending a competitor inside a 1★ review.

## Questions people ask

- "Nobody wants AI" / "Why is AI necessary?" / "How do I opt out of TimeTree AI?" (direct paraphrase of the dominant complaint cluster; opting out reportedly doesn't persist per reviewers)
- "Does TimeTree use my calendar data to train AI?"
- "TimeTree vs Cozi — which is better?" (recurring third-party title pattern)
- "Why did TimeTree delete my calendar?"
- "How do I export TimeTree to Google Calendar?"
