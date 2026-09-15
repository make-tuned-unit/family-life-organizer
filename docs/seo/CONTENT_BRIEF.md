# Content brief for SEO pages (read before writing any `seo/pages/**.json`)

## Truth rules (non-negotiable)
- Ground truth for product claims is `website/llms-full.txt` and `website/llms.txt`. If it is not there, do not claim it.
- Launch status: Kinrows is an iPhone app (iOS 18+), **free, launching September 2026**. Never say "available now" or "download today". CTA is the waitlist.
- Pricing: free core app; Concierge Lite $4.99/mo or $49.99/yr; Premium $9.99/mo or $99.99/yr, per household.
- Competitors: only say what the research files (`docs/seo/research/`) or the competitor's own site support. Quote complaints only verbatim and with attribution ("an App Store reviewer wrote…"). Always state what the competitor does well and who should still choose it.
- No invented statistics, studies, testimonials, review counts, or star ratings. Cite a primary source (URL) for any external fact.
- No keyword stuffing. Write the way a careful friend who runs a household would.

## Voice
Kinrows voice: calm, plain, warm, specific. Short sentences. Canadian/UK spelling ("organiser" is fine; the site uses "organizer" in product names — keep "organizer" for the category noun to match existing pages, "labour" for the mental-load topic). No exclamation marks. No "seamless", "effortless", "game-changer", "unlock".

## Answer-first anatomy (every page)
1. `h1` — the query in natural words.
2. `directAnswer` — 40–110 words that fully answer the query on their own (this is the snippet / AI citation). Name the answer, not the product, first. Product may appear in the last sentence.
3. `keyTakeaway` — one line.
4. `sections` — 3–6 `{heading, html}` blocks: why it happens / what to do / options compared / evidence. Use `<p>`, `<ul>`, `<ol>`, `<table>` sparingly, `<strong>` for scan-ability. Headings are descriptive questions or statements, never clever.
5. `comparisonTable` — only for alternative/vs/roundup-style pages. Columns: the tools; rows: concrete capabilities; cells "yes"/"no"/short text.
6. `productFit` — 80–160 words on how the *specific* feature solves the *specific* problem, with the matching screenshot from `website/assets/shots/`: calendar.png, care.png (care/babysitting requests), chat.png (family chat), concierge-ask.png, concierge-brief.png, home.png, lists.png, rivalries.png (Health-synced family competitions), tasks.png (chores/routines), travel.png (trips).
7. `faq` — 3–5 real questions from research, answers ≤120 words each, first sentence answers it.
8. `cta` — heading + body + label matched to intent ("Join the waitlist" default; alternatives: "Get Kinrows when it launches", "Save your spot").
9. `relatedPages` — ≥3 internal links (mix of page types + a roundup or `/`), labels are the page titles.
10. `sources` — primary sources for any external claim.

## Page-type specifics
- **howto** (`/how-to/…`): "How to X without Y". The answer must work even for someone who never installs Kinrows.
- **alternative** (`/alternatives/<competitor>`): "Best <Competitor> alternatives (2026)". Lead with why people look (quoted complaints), then 4–6 alternatives ranked by explicit criteria; Kinrows only where defensible; "Who should stay with <Competitor>" section is mandatory.
- **compare** (`/compare/kinrows-vs-<competitor>`): honest side-by-side; "Choose <Competitor> if… / Choose Kinrows if…".
- **persona** (`/for/…`): only when the answer materially differs for that persona. Open with that persona's actual situation in their words.
- **question** (`/questions/…`): one question, answered in the first paragraph, expanded with evidence; product relevance is one short section, not the point.
