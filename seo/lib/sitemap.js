'use strict';

const { SITE_BASE, PAGE_TYPES, pageUrlPath, hubUrlPath } = require('./util');

function urlEntry(loc, lastmod, changefreq, priority) {
  return `  <url>\n    <loc>${SITE_BASE}${loc}</loc>\n    <lastmod>${lastmod}</lastmod>\n    <changefreq>${changefreq}</changefreq>\n    <priority>${priority}</priority>\n  </url>`;
}

// manifestEntries: [{ url, lastmod, changefreq, priority }]
// indexablePages: processed page objects with effectiveIndexStatus === 'index'
// hubs: [{ pageType, lastmod }]
function buildSitemapXml(manifestEntries, indexablePages, hubs) {
  const entries = [];
  for (const m of manifestEntries) {
    entries.push(urlEntry(m.url, m.lastmod, m.changefreq, m.priority));
  }
  for (const hub of hubs) {
    entries.push(urlEntry(hubUrlPath(hub.pageType), hub.lastmod, 'weekly', '0.6'));
  }
  for (const page of indexablePages) {
    if (page.effectiveIndexStatus !== 'index') continue;
    entries.push(
      urlEntry(pageUrlPath(page), page.lastReviewed, 'monthly', priorityFor(page.pageType))
    );
  }
  return `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${entries.join(
    '\n'
  )}\n</urlset>`;
}

function priorityFor(pageType) {
  switch (pageType) {
    case 'compare':
      return '0.7';
    case 'alternative':
      return '0.6';
    default:
      return '0.6';
  }
}

module.exports = { buildSitemapXml };
