'use strict';

const fs = require('fs');
const path = require('path');
const {
  PAGE_TYPES,
  SLUG_RE,
  wordCount,
  isHttpUrl,
  pageUrlPath,
  pageOutputFile,
  hubUrlPath,
} = require('./util');

const REQUIRED_STRING_FIELDS = [
  'slug',
  'pageType',
  'query',
  'searchIntent',
  'title',
  'description',
  'h1',
  'eyebrow',
  'directAnswer',
  'datePublished',
  'lastReviewed',
  'indexStatus',
];

function pageLabel(page, fileRel) {
  return `${fileRel} (${page && page.pageType}/${page && page.slug})`;
}

// Validates the loaded pages (each { page, file, parseError }) plus the
// hand-written manifest pages, and returns:
//   { hardErrors, warnings, processedPages }
// processedPages carries effectiveIndexStatus (forced noindex on soft issues).
function validateAll({ loaded, manifestEntries, manifestMeta, websiteDir }) {
  const hardErrors = [];
  const warnings = [];

  // 1. Parse errors are immediately hard.
  for (const item of loaded) {
    if (item.parseError) {
      hardErrors.push(`${item.file}: invalid JSON — ${item.parseError.message}`);
    }
  }
  const okItems = loaded.filter((i) => !i.parseError);

  // 2. Required fields + basic shape per page.
  for (const item of okItems) {
    const { page, file, expectedPageType } = item;
    const label = `${file}`;

    if (!page || typeof page !== 'object') {
      hardErrors.push(`${label}: page JSON must be an object`);
      continue;
    }
    for (const field of REQUIRED_STRING_FIELDS) {
      if (!page[field] || typeof page[field] !== 'string' || !page[field].trim()) {
        hardErrors.push(`${label}: missing required field "${field}"`);
      }
    }
    if (page.pageType && !PAGE_TYPES[page.pageType]) {
      hardErrors.push(`${label}: unknown pageType "${page.pageType}"`);
    }
    if (page.pageType && expectedPageType && page.pageType !== expectedPageType) {
      hardErrors.push(
        `${label}: pageType "${page.pageType}" does not match its directory "${expectedPageType}"`
      );
    }
    if (page.slug && !SLUG_RE.test(page.slug)) {
      hardErrors.push(`${label}: slug "${page.slug}" must be lowercase kebab-case`);
    }
    if (page.indexStatus && !['index', 'noindex'].includes(page.indexStatus)) {
      hardErrors.push(`${label}: indexStatus must be "index" or "noindex"`);
    }
    if (page.title && page.title.length > 70) {
      hardErrors.push(`${label}: title exceeds 70 chars (${page.title.length})`);
    }
    if (page.description && page.description.length > 170) {
      hardErrors.push(`${label}: description exceeds 170 chars (${page.description.length})`);
    }
    if (!Array.isArray(page.sections) || page.sections.length === 0) {
      hardErrors.push(`${label}: sections must be a non-empty array`);
    } else {
      page.sections.forEach((s, i) => {
        if (!s || !s.heading || !s.html) {
          hardErrors.push(`${label}: sections[${i}] must have heading and html`);
        }
      });
    }
    if (!page.cta || !page.cta.heading || !page.cta.body || !page.cta.label) {
      hardErrors.push(`${label}: cta must have heading, body and label`);
    }
    if (!Array.isArray(page.relatedPages) || page.relatedPages.length < 3) {
      hardErrors.push(`${label}: relatedPages must have at least 3 entries`);
    } else {
      page.relatedPages.forEach((r, i) => {
        if (!r || !r.href || !r.label) {
          hardErrors.push(`${label}: relatedPages[${i}] must have href and label`);
        } else {
          if (r.href.includes('.html')) {
            hardErrors.push(`${label}: relatedPages[${i}] href "${r.href}" must not contain .html`);
          }
          if (!r.href.startsWith('/')) {
            hardErrors.push(
              `${label}: relatedPages[${i}] href "${r.href}" must be root-absolute (start with "/")`
            );
          }
        }
      });
    }
    if (page.sources) {
      if (!Array.isArray(page.sources)) {
        hardErrors.push(`${label}: sources must be an array`);
      } else {
        page.sources.forEach((s, i) => {
          if (!s || !s.title || !isHttpUrl(s.url)) {
            hardErrors.push(`${label}: sources[${i}] must have title and an http(s) url`);
          }
        });
      }
    }
    if (page.faq) {
      if (!Array.isArray(page.faq)) {
        hardErrors.push(`${label}: faq must be an array`);
      } else {
        page.faq.forEach((f, i) => {
          if (!f || !f.q || !f.a) {
            hardErrors.push(`${label}: faq[${i}] must have q and a`);
          }
        });
      }
    }
    if (page.comparisonTable) {
      const t = page.comparisonTable;
      if (!Array.isArray(t.columns) || !Array.isArray(t.rows)) {
        hardErrors.push(`${label}: comparisonTable must have columns and rows arrays`);
      } else {
        t.rows.forEach((row, i) => {
          if (!Array.isArray(row) || row.length !== t.columns.length) {
            hardErrors.push(
              `${label}: comparisonTable.rows[${i}] length must match columns length`
            );
          }
        });
      }
    }
    if (page.productFit) {
      const pf = page.productFit;
      if (!pf.heading || !pf.html) {
        hardErrors.push(`${label}: productFit must have heading and html`);
      }
      if (pf.screenshot) {
        if (!pf.screenshot.src || !pf.screenshot.alt) {
          hardErrors.push(`${label}: productFit.screenshot must have src and alt`);
        } else if (!/^website\/assets\/shots\/[\w-]+\.png$/.test(pf.screenshot.src)) {
          hardErrors.push(
            `${label}: productFit.screenshot.src "${pf.screenshot.src}" must match website/assets/shots/<name>.png`
          );
        } else {
          const abs = path.join(path.dirname(websiteDir), pf.screenshot.src);
          const exists = fs.existsSync(abs);
          pf.screenshot._exists = exists;
          pf.screenshot._absPath = abs;
          if (!exists) {
            warnings.push(`${label}: WARN productFit.screenshot file missing (${pf.screenshot.src}) — forcing noindex`);
            page._softIssue = true;
          }
        }
      }
    }
  }

  if (hardErrors.length) {
    return { hardErrors, warnings, processedPages: [] };
  }

  // 3. Soft checks: directAnswer length, faq answer length.
  for (const item of okItems) {
    const { page, file } = item;
    const wc = wordCount(page.directAnswer);
    if (wc < 40 || wc > 110) {
      warnings.push(`${file}: WARN directAnswer is ${wc} words (want 40-110) — forcing noindex`);
      page._softIssue = true;
    }
    if (Array.isArray(page.faq)) {
      page.faq.forEach((f, i) => {
        const fwc = wordCount(f.a);
        if (fwc > 120) {
          warnings.push(`${file}: WARN faq[${i}] answer is ${fwc} words (max 120) — forcing noindex`);
          page._softIssue = true;
        }
      });
    }
  }

  // 4. Build the internal-link resolution set (manifest + generated pages + hubs).
  const validInternalPaths = new Set(['/']);
  for (const entry of manifestEntries) validInternalPaths.add(entry.url);
  for (const t of Object.keys(PAGE_TYPES)) validInternalPaths.add(hubUrlPath(t));
  for (const item of okItems) validInternalPaths.add(pageUrlPath(item.page));

  for (const item of okItems) {
    const { page, file } = item;
    if (!Array.isArray(page.relatedPages)) continue;
    page.relatedPages.forEach((r, i) => {
      if (!r || !r.href) return;
      if (!validInternalPaths.has(r.href)) {
        hardErrors.push(
          `${file}: relatedPages[${i}] href "${r.href}" does not resolve to a generated page or manifest entry`
        );
      }
    });
  }

  // 5. Uniqueness of title / h1 / description / slug across everything.
  const seenTitles = new Map();
  const seenH1s = new Map();
  const seenDescriptions = new Map();
  const seenSlugs = new Map();

  const checkUnique = (map, value, label, kind) => {
    if (!value) return;
    const key = value.trim();
    if (seen(map, key)) {
      hardErrors.push(
        `${label}: duplicate ${kind} "${key.slice(0, 80)}" also used by ${map.get(key)}`
      );
    } else {
      map.set(key, label);
    }
  };
  const seen = (map, key) => map.has(key);

  for (const entry of manifestMeta) {
    checkUnique(seenTitles, entry.title, entry.url, 'title');
    checkUnique(seenH1s, entry.h1, entry.url, 'h1');
    checkUnique(seenDescriptions, entry.description, entry.url, 'description');
  }
  for (const item of okItems) {
    const { page, file } = item;
    const fullTitle = `${page.title} | Kinrows`;
    checkUnique(seenTitles, fullTitle, file, 'title');
    checkUnique(seenH1s, page.h1, file, 'h1');
    checkUnique(seenDescriptions, page.description, file, 'description');
    checkUnique(seenSlugs, page.slug, file, 'slug');
  }

  const processedPages = okItems.map((item) => {
    const page = item.page;
    page.effectiveIndexStatus = page._softIssue ? 'noindex' : page.indexStatus;
    return page;
  });

  return { hardErrors, warnings, processedPages };
}

module.exports = { validateAll };
