'use strict';

const { escapeHtml, SITE_BASE, PAGE_TYPES, pageUrlPath, hubUrlPath, absUrl } = require('./util');
const { readPngSize } = require('./png');

const FONT_LINKS = [
  '<link rel="preconnect" href="https://fonts.googleapis.com" />',
  '<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />',
  '<link href="https://fonts.googleapis.com/css2?family=Fraunces:ital,opsz,wght@0,9..144,400;0,9..144,500;0,9..144,600;1,9..144,400&family=Inter:wght@400;450;500;600&display=swap" rel="stylesheet" />',
].join('\n');

const ANALYTICS_SNIPPET =
  "<script>window.permagentCollectUrl='/api/permagent-analytics/collect';</script>\n" +
  '<script src="/analytics.js" defer></script>';

function jsonLdScript(obj) {
  const json = JSON.stringify(obj, null, 2);
  // Defensive: this must always be valid JSON-LD.
  JSON.parse(json);
  return `<script type="application/ld+json">\n${json}\n</script>`;
}

function breadcrumbJsonLd(items) {
  return {
    '@context': 'https://schema.org',
    '@type': 'BreadcrumbList',
    itemListElement: items.map((it, i) => ({
      '@type': 'ListItem',
      position: i + 1,
      name: it.name,
      item: it.url,
    })),
  };
}

function faqJsonLd(faq) {
  return {
    '@context': 'https://schema.org',
    '@type': 'FAQPage',
    mainEntity: faq.map((f) => ({
      '@type': 'Question',
      name: f.q,
      acceptedAnswer: { '@type': 'Answer', text: f.a },
    })),
  };
}

function articleJsonLd(page, url) {
  return {
    '@context': 'https://schema.org',
    '@type': 'Article',
    headline: page.title,
    description: page.description,
    image: `${SITE_BASE}/assets/og-image.jpg?v=3`,
    datePublished: page.datePublished,
    dateModified: page.lastReviewed,
    inLanguage: 'en',
    url,
    mainEntityOfPage: { '@type': 'WebPage', '@id': url },
    author: { '@type': 'Organization', name: 'Kinrows', url: `${SITE_BASE}/` },
    publisher: {
      '@type': 'Organization',
      name: 'Kinrows',
      logo: { '@type': 'ImageObject', url: `${SITE_BASE}/assets/brand/app-icon-512.png` },
    },
    speakable: { '@type': 'SpeakableSpecification', cssSelector: ['h1', '.lead'] },
  };
}

function itemListJsonLd(page, url) {
  const rows = page.comparisonTable.rows;
  return {
    '@context': 'https://schema.org',
    '@type': 'ItemList',
    name: page.title,
    description: page.description,
    itemListOrder: 'https://schema.org/ItemListUnordered',
    url,
    itemListElement: rows.map((row, i) => ({
      '@type': 'ListItem',
      position: i + 1,
      name: String(row[0]),
    })),
  };
}

function renderHead({ title, description, canonicalPath, indexStatus, jsonldBlocks, ogType }) {
  const url = absUrl(canonicalPath);
  const robots = indexStatus === 'index' ? 'index,follow' : 'noindex,follow';
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<script>document.documentElement.classList.add('js')</script>
<title>${escapeHtml(title)}</title>
<meta name="description" content="${escapeHtml(description)}" />
<meta name="theme-color" content="#0F3D37" />
<meta name="robots" content="${robots}" />
<link rel="canonical" href="${escapeHtml(url)}" />

<meta property="og:title" content="${escapeHtml(title)}" />
<meta property="og:description" content="${escapeHtml(description)}" />
<meta property="og:type" content="${ogType || 'website'}" />
<meta property="og:url" content="${escapeHtml(url)}" />
<meta property="og:image" content="${SITE_BASE}/assets/og-image.jpg?v=3" />
<meta name="twitter:card" content="summary_large_image" />
<meta name="twitter:title" content="${escapeHtml(title)}" />
<meta name="twitter:description" content="${escapeHtml(description)}" />
<meta name="twitter:image" content="${SITE_BASE}/assets/og-image.jpg?v=3" />

<link rel="icon" href="/favicon.ico?v=3" sizes="any" />
<link rel="icon" type="image/png" sizes="32x32" href="/assets/brand/favicon-32.png?v=3" />
<link rel="icon" type="image/png" sizes="192x192" href="/assets/brand/favicon-192.png?v=3" />
<link rel="apple-touch-icon" sizes="180x180" href="/assets/brand/apple-touch-icon.png?v=3" />
<link rel="manifest" href="/site.webmanifest" />

${FONT_LINKS}
<link rel="stylesheet" href="/assets/style.css?v=202609092032" />

${jsonldBlocks.join('\n')}
${ANALYTICS_SNIPPET}
</head>`;
}

function renderNav() {
  return `<svg width="0" height="0" style="position:absolute" aria-hidden="true" focusable="false">
  <defs>
    <symbol id="i-menu" viewBox="0 0 24 24"><path d="M4 7h16M4 12h16M4 17h16"/></symbol>
    <symbol id="i-close" viewBox="0 0 24 24"><path d="M6 6l12 12M18 6 6 18"/></symbol>
  </defs>
</svg>

<header class="nav" id="nav">
  <div class="nav-inner">
    <a class="brand" href="/#top" aria-label="Kinrows home">
      <img class="brand-mark" src="/assets/brand/logos/kinrows-boat-mark.png" alt="" width="47" height="34" />
      <span class="brand-name">Kinrows</span></a>
    <nav class="nav-links" id="primary-nav" aria-label="Primary">
      <a href="/#plan">The app</a>
      <a href="/#everything">Everything inside</a>
      <a href="/compare">Compare</a>
      <a href="/blog/">Blog</a>
      <a href="/#assist">Concierge</a>
    </nav>
    <a href="/#notify" class="btn btn-pill">Join the waitlist</a>
    <button class="nav-toggle" type="button" aria-label="Open menu" aria-expanded="false" aria-controls="primary-nav">
      <svg class="ic ic-menu" aria-hidden="true"><use href="#i-menu"/></svg>
      <svg class="ic ic-close" aria-hidden="true"><use href="#i-close"/></svg>
    </button>
  </div>
</header>`;
}

function renderFooter() {
  return `<footer class="footer">
  <div class="container footer-inner">
    <div class="footer-brand">
      <a class="brand" href="/#top"><img class="brand-lockup" src="/assets/brand/logos/kinrows-lockup.png" alt="Kinrows — kin that rows together" width="200" height="72" /></a>
      <p class="footer-tag">One calm place for the whole household.</p>
    </div>
    <nav class="footer-cols" aria-label="Footer">
      <div><p class="fc-head">App</p><a href="/#plan">The app</a><a href="/#everything">Everything inside</a><a href="/#assist">Concierge</a></div>
      <div><p class="fc-head">Explore</p><a href="/compare">Compare</a><a href="/blog/">Blog</a><a href="/#notify">Join the waitlist</a></div>
      <div><p class="fc-head">Legal</p><a href="/privacy">Privacy Policy</a><a href="/terms">Terms of Use</a></div>
    </nav>
  </div>
  <div class="container footer-bottom">
    <span>© 2026 Atlas Atlantic. Made for families.</span>
    <span>iPhone · iOS 18+ · September 2026</span>
  </div>
</footer>

<script src="/assets/app.js"></script>
</body>
</html>`;
}

function renderNotifyForm(source, label) {
  return `<form class="notify-form" data-source="${escapeHtml(source)}" aria-label="Join the waitlist">
        <input type="email" name="email" placeholder="you@email.com" aria-label="Email address" autocomplete="email" inputmode="email" required />
        <button type="submit" class="btn btn-primary">${escapeHtml(label)}</button>
      </form>
      <p class="cta-fine">Free on iPhone · iOS 18+ · Concierge optional</p>`;
}

function renderComparisonTable(table) {
  if (!table) return '';
  const cellHtml = (cell) => {
    const raw = String(cell);
    const lower = raw.trim().toLowerCase();
    if (lower === 'yes') return `<span class="cmp-yes">Yes</span>`;
    if (lower === 'no') return `<span class="cmp-no">—</span>`;
    return escapeHtml(raw);
  };
  const head = table.columns
    .map((c, i) => `<th scope="col"${i === 1 ? ' class="col-us"' : ''}>${escapeHtml(c)}</th>`)
    .join('');
  const rows = table.rows
    .map((row) => {
      const [first, ...rest] = row;
      const cells = rest
        .map((c, i) => `<td${i === 0 ? ' class="col-us"' : ''}>${cellHtml(c)}</td>`)
        .join('');
      return `<tr><th scope="row">${escapeHtml(first)}</th>${cells}</tr>`;
    })
    .join('\n                ');
  return `<section>
          <h2>${escapeHtml(table.caption || 'At a glance')}</h2>
          <div class="cmp-wrap">
            <table class="cmp-table">
              <thead><tr>${head}</tr></thead>
              <tbody>
                ${rows}
              </tbody>
            </table>
          </div>
        </section>`;
}

function renderProductFit(productFit, websiteDir) {
  if (!productFit) return '';
  let imgHtml = '';
  if (productFit.screenshot && productFit.screenshot._exists) {
    const { width, height } = readPngSize(productFit.screenshot._absPath);
    const src = productFit.screenshot.src.replace(/^website\//, '/');
    imgHtml = `<img class="app-shot" src="${escapeHtml(src)}" alt="${escapeHtml(
      productFit.screenshot.alt || ''
    )}" width="${width}" height="${height}" loading="lazy" decoding="async">`;
  }
  return `<h2>${escapeHtml(productFit.heading)}</h2>
${productFit.html}
${imgHtml}`;
}

function renderFaq(faq) {
  if (!faq || !faq.length) return '';
  const items = faq
    .map(
      (f) => `<h3>${escapeHtml(f.q)}</h3>\n<p>${escapeHtml(f.a)}</p>`
    )
    .join('\n');
  return `<h2>Frequently asked questions</h2>\n${items}`;
}

function renderRelated(relatedPages) {
  const items = relatedPages
    .map((r) => `<a href="${escapeHtml(r.href)}">${escapeHtml(r.label)}</a>`)
    .join('\n        ');
  return `<div class="legal-foot-links">
        ${items}
      </div>`;
}

function renderSources(sources) {
  if (!sources || !sources.length) return '';
  const items = sources
    .map((s) => `<li><a href="${escapeHtml(s.url)}" rel="nofollow noopener" target="_blank">${escapeHtml(s.title)}</a></li>`)
    .join('\n');
  return `<h2>Sources</h2>\n<ul>\n${items}\n</ul>`;
}

function renderPageHtml(page, ctx) {
  const cfg = PAGE_TYPES[page.pageType];
  const url = absUrl(pageUrlPath(page));
  const hubUrl = absUrl(hubUrlPath(page.pageType));
  const title = `${page.title} | Kinrows`;

  const jsonldBlocks = [];
  jsonldBlocks.push(
    jsonLdScript(
      breadcrumbJsonLd([
        { name: 'Home', url: `${ctx.siteBase}/` },
        { name: cfg.hubTitle, url: hubUrl },
        { name: page.h1, url },
      ])
    )
  );
  if (page.faq && page.faq.length) {
    jsonldBlocks.push(jsonLdScript(faqJsonLd(page.faq)));
  }
  if (cfg.ldType === 'Article') {
    jsonldBlocks.push(jsonLdScript(articleJsonLd(page, url)));
  }
  if (page.pageType === 'alternative' && page.comparisonTable) {
    jsonldBlocks.push(jsonLdScript(itemListJsonLd(page, url)));
  }

  const head = renderHead({
    title,
    description: page.description,
    canonicalPath: pageUrlPath(page),
    indexStatus: page.effectiveIndexStatus,
    jsonldBlocks,
    ogType: cfg.ldType === 'Article' ? 'article' : 'website',
  });

  const sections = page.sections
    .map((s) => `<h2>${escapeHtml(s.heading)}</h2>\n${s.html}`)
    .join('\n\n');

  const keyTakeaway = page.keyTakeaway
    ? `<p class="lb-row lead" style="padding:12px 16px;border-radius:12px"><strong>Key takeaway:</strong> ${escapeHtml(
        page.keyTakeaway
      )}</p>`
    : '';

  const lastReviewed = `<p class="article-meta">Last reviewed <time datetime="${escapeHtml(
    page.lastReviewed
  )}">${escapeHtml(page.lastReviewed)}</time></p>`;

  const comparisonTable = renderComparisonTable(page.comparisonTable);
  const productFit = page.productFit ? renderProductFit(page.productFit, ctx.websiteDir) : '';
  const faq = renderFaq(page.faq);
  const related = renderRelated(page.relatedPages);
  const sources = renderSources(page.sources);

  return `${head}
<body>

${renderNav()}

<main id="top">
  <section class="legal-hero">
    <div class="legal-wrap">
      <p class="eyebrow eyebrow-accent" style="--ac:var(--ocean)">${escapeHtml(page.eyebrow)}</p>
      <h1>${escapeHtml(page.h1)}</h1>
    </div>
  </section>

  <section class="legal-body">
    <div class="legal-wrap">
      <div class="legal-prose">

<p class="lead">${escapeHtml(page.directAnswer)}</p>
${keyTakeaway}
${lastReviewed}

${sections}

${comparisonTable}

${productFit}

${faq}

${sources}
      </div>

      <aside class="post-cta">
        <h3>${escapeHtml(page.cta.heading)}</h3>
        <p>${escapeHtml(page.cta.body)}</p>
        ${renderNotifyForm(`seo:${page.pageType}:${page.slug}`, page.cta.label)}
      </aside>

      ${related}
    </div>
  </section>
</main>

${renderFooter()}`;
}

function renderHubHtml(pageType, indexablePages, ctx) {
  const cfg = PAGE_TYPES[pageType];
  const url = absUrl(hubUrlPath(pageType));
  const title = `${cfg.hubTitle} | Kinrows`;
  const description = ctx.hubDescription;

  const jsonldBlocks = [
    jsonLdScript(
      breadcrumbJsonLd([
        { name: 'Home', url: `${ctx.siteBase}/` },
        { name: cfg.hubTitle, url },
      ])
    ),
  ];

  const head = renderHead({
    title,
    description,
    canonicalPath: hubUrlPath(pageType),
    indexStatus: 'index',
    jsonldBlocks,
    ogType: 'website',
  });

  const cards = indexablePages
    .map(
      (p) => `<article class="blog-card">
          <a href="${escapeHtml(pageUrlPath(p))}" style="display:block">
            <p class="bc-meta">${escapeHtml(cfg.hubEyebrow)}</p>
            <h2>${escapeHtml(p.h1)}</h2>
            <p>${escapeHtml(p.description)}</p>
            <span class="bc-more">Read more →</span>
          </a>
        </article>`
    )
    .join('\n\n        ');

  return `${head}
<body>

${renderNav()}

<main id="top">
  <section class="legal-hero">
    <div class="legal-wrap">
      <p class="eyebrow eyebrow-accent" style="--ac:var(--sage)">${escapeHtml(cfg.hubEyebrow)}</p>
      <h1>${escapeHtml(ctx.hubH1)}</h1>
      <p class="muted">${escapeHtml(ctx.hubIntro)}</p>
    </div>
  </section>

  <section class="legal-body">
    <div class="legal-wrap">
      <div class="blog-list">

        ${cards}

      </div>
    </div>
  </section>
</main>

${renderFooter()}`;
}

module.exports = {
  renderPageHtml,
  renderHubHtml,
  jsonLdScript,
  breadcrumbJsonLd,
  faqJsonLd,
  articleJsonLd,
  itemListJsonLd,
};
