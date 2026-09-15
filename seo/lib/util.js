'use strict';

const SITE_BASE = 'https://kinrows.com';

// pageType -> where generated pages/hubs live, relative to the website/ root.
const PAGE_TYPES = {
  howto: { dir: 'how-to', hubTitle: 'How-to guides', hubEyebrow: 'How-to', ldType: 'Article' },
  alternative: { dir: 'alternatives', hubTitle: 'Alternatives', hubEyebrow: 'Alternatives', ldType: null },
  compare: { dir: 'compare', hubTitle: 'Compare', hubEyebrow: 'Compare', ldType: null },
  persona: { dir: 'for', hubTitle: 'For your family', hubEyebrow: 'For you', ldType: 'Article' },
  question: { dir: 'questions', hubTitle: 'Questions', hubEyebrow: 'Questions', ldType: 'Article' },
};

const SLUG_RE = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

function escapeHtml(str) {
  return String(str == null ? '' : str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function wordCount(str) {
  const s = String(str || '').trim();
  if (!s) return 0;
  return s.split(/\s+/).filter(Boolean).length;
}

function isHttpUrl(u) {
  return typeof u === 'string' && /^https?:\/\//i.test(u);
}

function pageUrlPath(page) {
  const cfg = PAGE_TYPES[page.pageType];
  return `/${cfg.dir}/${page.slug}`;
}

function pageOutputFile(page) {
  const cfg = PAGE_TYPES[page.pageType];
  return `${cfg.dir}/${page.slug}.html`;
}

function hubUrlPath(pageType) {
  const cfg = PAGE_TYPES[pageType];
  return `/${cfg.dir}/`;
}

function hubOutputFile(pageType) {
  const cfg = PAGE_TYPES[pageType];
  return `${cfg.dir}/index.html`;
}

function absUrl(pathname) {
  if (pathname === '/') return `${SITE_BASE}/`;
  return `${SITE_BASE}${pathname}`;
}

module.exports = {
  SITE_BASE,
  PAGE_TYPES,
  SLUG_RE,
  escapeHtml,
  wordCount,
  isHttpUrl,
  pageUrlPath,
  pageOutputFile,
  hubUrlPath,
  hubOutputFile,
  absUrl,
};
