# SEO Opportunities (Search Console feedback loop)

Google Search Console is verified for `sc-domain:kinrows.com`. `https://kinrows.com/sitemap.xml` was
submitted on 2026-09-15 (status Success, 21 URLs read from the then-deployed sitemap; it will re-read the
66-URL sitemap after the next deploy). Run this loop monthly.

Look first for **queries with impressions but low or no clicks** — Google is already testing a
page against the query. Fix the page (title, opening answer, headings, missing info, internal links)
before writing new pages. Pair with `node scripts/seo-report.js --days 30` for conversions per page class.

| Query | Page | Impressions | Clicks | CTR | Position | Intent | Recommended change | Date changed | Result |
|-------|------|-------------|--------|-----|----------|--------|--------------------|--------------|--------|
| kinrow (branded, misspelt) | / | 24 | 1 | 4.2% | — | navigational | none; brand demand only | — | — |
| how to sleep train a newborn | /blog/how-to-sleep-train-a-baby | 1 | 0 | 0% | — | informational | title already covers newborns; watch for growth | — | — |

## Baseline snapshot — 2026-09-15 (last 3 months, before the 40 new pages)

| Metric | Value |
|---|---|
| Total impressions | 94 |
| Total clicks | 3 |
| Average CTR | 3.2% |
| Average position | 10.8 |
| Indexed pages | 15 |
| Not indexed | 4 (2 "page with redirect", 2 "alternate page with proper canonical" — both benign; the `.html` → clean-URL 301s will add more of the first kind, which is expected) |
| Queries shown | 3 (all brand or near-zero volume); no non-brand demand yet |

Impressions by page (3 months): `/` 67 · `/compare.html` 21 · `/privacy.html` 16 · `/terms.html` 11 · `/blog/` 10 ·
`/blog/how-to-sleep-train-a-baby.html` 7 · `/blog/what-is-emotional-labour.html` 6 ·
`/blog/signs-too-much-emotional-labour.html` 5 · `/blog/emotional-labour-vs-mental-load.html` 5 ·
`/blog/family-calendar-organization.html` 3 (14 pages total). Note GSC still reports the `.html` URLs; after
deploy these will migrate to the clean URLs via the 301s, so compare like-for-like next month.

**Reading:** the site has effectively no non-brand organic footprint yet, so there are no "losers to optimize"
this cycle. The next review (mid-October 2026) should check (1) the 45 new URLs are indexed, (2) which page
classes earn impressions first, and (3) any query with ≥20 impressions and CTR under 2% — those get the
title/opening-answer rewrite before any new pages are written.
