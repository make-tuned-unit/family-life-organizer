# SEO Implementation DAG

Atomic tasks, dependencies and verification gates. Status legend: ☐ todo · ◐ in progress · ☑ done.
Companion: `docs/SEO_STRATEGY.md`.

```
T0 audit ─┬─ T1 engine ──────┬─ T4 content pages (T4a…T4e) ─ T6 build+gates ─ T7 QA ─ T8 deploy ─ T9 GSC loop ─ T10 scale
          ├─ T2 clean URLs ──┤
          ├─ T3 measurement ─┘
          └─ R1/R2 research ─┴─ T5 backlog + scores
```

| ID | Task | Depends on | Verification gate | Status |
|----|------|-----------|-------------------|--------|
| T0 | Technical audit + current-state doc (`SEO_STRATEGY.md` §1) | — | Doc lists every gap with a fix ID | ☑ |
| R1 | Complaint mining: Cozi, FamilyWall, TimeTree, Skylight → `docs/seo/research/` | — | Every quote has URL + date; no fabrication | ☑ |
| R2 | Complaint mining: OurHome, AnyList, Maple, Hearth, Picniic, defaults; question/problem phrasing | — | Same | ☑ |
| T1 | `seo/` page engine: JSON model, template, hubs, sitemap generation, gates, `test/seo-pages.test.js` | T0 | `npm run seo:check` passes; unit test green | ☑ |
| T2 | Clean URLs: generic resolver, `.html`→301, branded 404, canonical/link migration, llms.txt, hub footer links | T0 | `test/website-routes.test.js` green; grep finds no `.html"` internal hrefs; `npm test` green | ☑ |
| T3 | Measurement: `landing_path` on waitlist, `waitlist_signup` event, `scripts/seo-report.js` | T0 | Test stores landing; report runs against a DB | ☑ |
| T5 | Cluster + score the backlog (§10–11), competitor matrix (§4) | R1, R2 | 40 pages scored on the 7 factors; each has research evidence | ☑ |
| T4a | 10 problem (`howto`) pages | T1, T5 | Gates + editorial checklist | ☑ |
| T4b | 5 alternative pages | T1, T5 | Fairness section present; claims sourced | ☑ |
| T4c | 5 vs / comparison pages | T1, T5 | Same | ☑ |
| T4d | 10 persona pages | T1, T5 | Answer materially differs per persona | ☑ |
| T4e | 10 question pages | T1, T5 | Direct answer stands alone; sources cited | ☑ |
| T6 | Build, gates, sitemap, hub pages | T4* | `npm run seo:build` clean; sitemap lists all indexable pages | ☑ |
| T7 | QA: rendered HTML, JSON-LD parse, canonical, mobile width, a11y basics, `npm test` | T2, T3, T6 | All green; spot-check 5 pages in a browser | ◐ |
| T8 | Deploy (Railway), submit sitemap to Search Console, request indexing for hubs | T7 | Live URLs 200; `.html` 301; Rich Results test passes on 3 pages | ◐ |
| T9 | Monthly GSC loop → `docs/SEO_OPPORTUNITIES.md` (fix low-CTR impressions before new pages) | T8 | Table updated with date + result | ☐ |
| T10 | Scale winning templates only; stop losers | T9 | Evidence: CTR + conversions per 1,000 impressions by page class | ☐ |

## Editorial checklist (per page, before `indexStatus: "index"`)
- Query exists in research (`docs/seo/research/`) or in GSC.
- First paragraph answers the query and would stand alone as a snippet.
- No fabricated numbers, reviews, or competitor weaknesses; competitor strengths stated.
- Product claims match `website/llms-full.txt`; launch status truthful.
- Screenshot shows the feature the page is about.
- CTA matches intent; ≥3 related links; sources listed for factual claims.
