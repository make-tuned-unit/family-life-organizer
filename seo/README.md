# Kinrows programmatic SEO engine

Generates the `website/how-to/`, `website/alternatives/`, `website/compare/`,
`website/for/` and `website/questions/` pages (plus their hub index pages and
`website/sitemap.xml`) from JSON page definitions. Node built-ins only, no
third-party deps.

## Add a page

1. Pick a page type and drop a JSON file in `seo/pages/<pageType>/<slug>.json`.

   | pageType      | output file                          | URL                      |
   |---------------|---------------------------------------|---------------------------|
   | `howto`       | `website/how-to/<slug>.html`          | `/how-to/<slug>`          |
   | `alternative` | `website/alternatives/<slug>.html`    | `/alternatives/<slug>`    |
   | `compare`     | `website/compare/<slug>.html`         | `/compare/<slug>` (e.g. `kinrows-vs-cozi`) |
   | `persona`     | `website/for/<slug>.html`             | `/for/<slug>`             |
   | `question`    | `website/questions/<slug>.html`       | `/questions/<slug>`       |

2. Run `npm run seo:check` to validate, then `npm run seo:build` to render.
3. Commit the JSON *and* the generated HTML + `website/sitemap.xml`.

## Schema (compact)

```jsonc
{
  "slug": "kebab-case-slug",
  "pageType": "howto|alternative|compare|persona|question",
  "query": "search query this page targets",
  "searchIntent": "informational|commercial|...",
  "title": "<=60 chars ideally, <=70 hard cap",
  "description": "<=160 chars ideally, <=170 hard cap",
  "h1": "page heading",
  "eyebrow": "small label above the H1",
  "directAnswer": "40-110 words, plain text — becomes the .lead paragraph and the speakable selector",
  "keyTakeaway": "optional one-line summary",
  "sections": [{ "heading": "H2 text", "html": "trusted, already-escaped HTML" }],
  "comparisonTable": {                       // optional
    "caption": "table caption",
    "columns": ["", "Kinrows", "Competitor"],
    "rows": [["Feature", "yes", "no"]]        // first cell is the row header; "yes"/"no" render as cmp-yes/cmp-no
  },
  "productFit": {                             // optional
    "heading": "H2 text",
    "html": "trusted HTML",
    "screenshot": { "src": "website/assets/shots/<name>.png", "alt": "alt text" } // optional, file must exist
  },
  "faq": [{ "q": "question", "a": "answer, <=120 words" }],   // optional; renders FAQPage JSON-LD when non-empty
  "cta": { "heading": "...", "body": "...", "label": "button label" },
  "relatedPages": [{ "href": "/root-absolute-url", "label": "..." }], // >= 3, must resolve to a generated or manifest page
  "sources": [{ "title": "...", "url": "https://..." }],      // optional
  "persona": "optional metadata string",
  "problem": "optional metadata string",
  "competitor": "optional metadata string",
  "productFeature": "optional metadata string",
  "datePublished": "YYYY-MM-DD",
  "lastReviewed": "YYYY-MM-DD",               // shown as "Last reviewed", used as sitemap lastmod
  "indexStatus": "index|noindex"
}
```

## Commands

- `npm run seo:build` — render every `seo/pages/**/*.json` into `website/`, regenerate the 5 hub
  index pages, and rewrite `website/sitemap.xml` (hand-written pages from `seo/site-manifest.json`
  + every indexable generated page + the hubs).
- `npm run seo:check` — run every quality gate without writing anything.
- `node seo/build.js --dry-run` — render in memory and print `NEW` / `CHANGED` / `UNCHANGED` per
  output file (including the sitemap) without writing.
- `npm test` (repo root) picks up `test/seo-pages.test.js` along with everything else.

## Quality gates

Hard issues abort the whole build (nothing is written) and are listed together:
invalid JSON, missing required fields, unknown `pageType`, non-kebab-case `slug`, title/description
over the hard length caps, empty `sections`, `cta` missing a field, fewer than 3 `relatedPages`,
a `relatedPages` href containing `.html` or not root-absolute, a `relatedPages` href that doesn't
resolve to a generated page/hub/manifest entry, a `sources` url that isn't `http(s)`, a malformed
`comparisonTable`, an out-of-pattern `productFit.screenshot.src`, and any duplicate `title` / `h1` /
`description` / `slug` across **every** page — generated and hand-written alike.

Soft issues still build the page but force it to `noindex` and print a `WARN` line: `directAnswer`
outside 40–110 words, a `faq` answer over 120 words, or a `productFit.screenshot` file that doesn't
exist on disk.

## Files

- `seo/pages/<pageType>/*.json` — page content (empty for now; a content team adds real pages next).
- `seo/site-manifest.json` — the hand-written pages (`website/index.html`, `website/blog/*.html`, …)
  with their clean URL, source file, and sitemap `lastmod`/`changefreq`/`priority`. Update this file
  whenever a hand-written page is added, removed, or its `lastmod` changes.
- `seo/build.js` — CLI entry point; also exports `run()` and friends for `test/seo-pages.test.js`
  (every directory it touches is an option, so tests point it at fixtures instead of the real site).
- `seo/lib/` — `util.js` (paths/escaping/page-type config), `png.js` (reads PNG width/height from the
  file header), `head-meta.js` (parses `<title>`/description/H1 out of hand-written pages),
  `validate.js` (the quality gates), `render.js` (HTML + JSON-LD templating), `sitemap.js`.

## Notes for other workers

- Hub URLs the nav/footer may eventually want to link to: `/how-to/`, `/alternatives/`, `/compare/`,
  `/for/`, `/questions/`. They're generated every build regardless of whether any pages exist yet.
- Everything this engine emits uses root-absolute hrefs and asset paths (`/assets/style.css?v=…`,
  `/#notify`, `/compare`), per the clean-URL migration — it does not link to any `.html` path.
