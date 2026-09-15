# Instructions for content writers (one worker per pageType)

Read in this order, fully: `docs/seo/CONTENT_BRIEF.md`, `seo/README.md` (the JSON schema and gates),
`test/fixtures/seo/pages/<yourType>/*.json` (a valid example), `website/llms-full.txt` (product truth),
your blocks in `docs/seo/BACKLOG.md` (including the "Editorial amendments" at the end and the universal
do-not-claim list), and the research files the blocks cite under `docs/seo/research/`.

Then author one JSON file per page at `seo/pages/<pageType>/<slug>.json` using the slugs in BACKLOG.md
exactly (other workers link to them). Requirements per page:
- `directAnswer` 40–110 words, answers the query on its own, product named at most in the last sentence.
- `sections`: 3–6 blocks of real, specific, well-formed HTML (`<p>`, `<ul>`, `<ol>`, `<strong>`, `<table>` only when it helps). 700–1,400 words total per page. Descriptive headings. No filler, no hype words, no exclamation marks.
- Quotes from research must be verbatim and attributed in-text ("one App Store reviewer wrote…" with rating and year). Never invent quotes, numbers, ratings, or studies. Cite primary sources in `sources`.
- Competitors: state their genuine strengths and who should still choose them. `alternative` and `compare` pages need a `comparisonTable` and a mandatory "Who should stay with X" / "Choose X if…" section. Kinrows wins only where llms-full.txt supports it.
- `productFit` 80–160 words on the specific feature, with the screenshot from the block; `faq` 3–5 items, answers ≤120 words; `cta` matched to intent (waitlist; launch September 2026, never "available now").
- `relatedPages`: use the block's list (root-absolute, no `.html`, labels = page titles). Links to other backlog slugs are allowed even if not yet written.
- `datePublished` and `lastReviewed`: "2026-09-15". `indexStatus`: "index" unless you judge the page thin or not materially distinct, in which case "noindex" and say why in your report.
- Spelling: "organizer" for the category noun, "labour" for the topic; Canadian/UK spelling otherwise.

When done run `node seo/build.js --check`. The ONLY acceptable remaining errors are unresolved `relatedPages` links to slugs that appear in BACKLOG.md but are owned by another worker; everything else (word counts, duplicates, JSON, screenshot paths, `.html` links) must be fixed. Do not run the non-check build, do not touch any file outside `seo/pages/<yourType>/`, do not commit. Report back in under 200 words: files written, any page set to noindex and why, any claim you could not verify and therefore omitted, and the residual --check output.
