'use strict';

const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');

const { run, BuildError } = require('../seo/build.js');

const FIXTURES_DIR = path.join(__dirname, 'fixtures', 'seo');
const FIXTURE_MANIFEST = path.join(FIXTURES_DIR, 'manifest.json');

let tmpRoot;

function freshWebsiteDir() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'seo-pages-test-'));
  const websiteDir = path.join(dir, 'website');
  fs.mkdirSync(websiteDir, { recursive: true });
  fs.cpSync(path.join(FIXTURES_DIR, 'website'), websiteDir, { recursive: true });
  return websiteDir;
}

before(() => {
  tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'seo-pages-test-root-'));
});

after(() => {
  fs.rmSync(tmpRoot, { recursive: true, force: true });
});

test('builds all five fixture page types with no hard errors', () => {
  const websiteDir = freshWebsiteDir();
  const result = run({
    pagesDir: path.join(FIXTURES_DIR, 'pages'),
    websiteDir,
    manifestPath: FIXTURE_MANIFEST,
    write: true,
  });
  assert.equal(result.pages.length, 5);
  assert.equal(result.warnings.length, 0);
  assert.equal(result.hubOutputs.length, 5);
});

test('rendered howto page has canonical, collect-path snippet, and speakable Article JSON-LD', () => {
  const websiteDir = freshWebsiteDir();
  const result = run({
    pagesDir: path.join(FIXTURES_DIR, 'pages'),
    websiteDir,
    manifestPath: FIXTURE_MANIFEST,
    write: true,
  });
  const out = result.pageOutputs.find((o) => o.path === 'how-to/sample-howto.html');
  assert.ok(out, 'howto page should be rendered');
  const html = out.html;

  assert.match(html, /<link rel="canonical" href="https:\/\/kinrows\.com\/how-to\/sample-howto" \/>/);
  assert.ok(
    html.includes('/api/permagent-analytics/collect'),
    'must include the analytics collect path literal'
  );
  assert.ok(html.includes('<script src="/analytics.js" defer></script>'));

  // Every JSON-LD block must parse as valid JSON.
  const blocks = [...html.matchAll(/<script type="application\/ld\+json">\n([\s\S]*?)\n<\/script>/g)];
  assert.ok(blocks.length >= 2, 'expects at least breadcrumb + one more JSON-LD block');
  const parsed = blocks.map((m) => JSON.parse(m[1]));

  const breadcrumb = parsed.find((p) => p['@type'] === 'BreadcrumbList');
  assert.ok(breadcrumb, 'BreadcrumbList JSON-LD present');
  assert.equal(breadcrumb.itemListElement.length, 3);
  assert.equal(breadcrumb.itemListElement[0].name, 'Home');
  assert.equal(breadcrumb.itemListElement[0].item, 'https://kinrows.com/');

  const faqLd = parsed.find((p) => p['@type'] === 'FAQPage');
  assert.ok(faqLd, 'FAQPage JSON-LD present and parses');
  assert.ok(faqLd.mainEntity.length >= 1);

  const article = parsed.find((p) => p['@type'] === 'Article');
  assert.ok(article, 'Article JSON-LD present for howto pages');
  assert.deepEqual(article.speakable.cssSelector, ['h1', '.lead']);

  // Screenshot dimensions read from the actual fixture PNG (100x200).
  assert.match(html, /<img class="app-shot" src="\/assets\/shots\/sample\.png"[^>]*width="100" height="200"/);
});

test('alternative page emits ItemList JSON-LD from its comparison table', () => {
  const websiteDir = freshWebsiteDir();
  const result = run({
    pagesDir: path.join(FIXTURES_DIR, 'pages'),
    websiteDir,
    manifestPath: FIXTURE_MANIFEST,
    write: true,
  });
  const out = result.pageOutputs.find((o) => o.path === 'alternatives/sample-alternative.html');
  assert.ok(out);
  const blocks = [...out.html.matchAll(/<script type="application\/ld\+json">\n([\s\S]*?)\n<\/script>/g)].map(
    (m) => JSON.parse(m[1])
  );
  const itemList = blocks.find((b) => b['@type'] === 'ItemList');
  assert.ok(itemList, 'ItemList JSON-LD present for alternative page with a comparisonTable');
  assert.equal(itemList.itemListElement[0].name, 'Calendar');
});

test('a page with a soft issue (too-short directAnswer) still builds but is forced to noindex with a WARN', () => {
  const websiteDir = freshWebsiteDir();
  const result = run({
    pagesDir: path.join(FIXTURES_DIR, 'pages-soft'),
    websiteDir,
    manifestPath: FIXTURE_MANIFEST,
    write: true,
  });
  assert.equal(result.pages.length, 1);
  assert.ok(result.warnings.some((w) => /directAnswer/.test(w)), 'should warn about directAnswer length');

  const out = result.pageOutputs.find((o) => o.path === 'how-to/soft-issue.html');
  assert.ok(out);
  assert.match(out.html, /<meta name="robots" content="noindex,follow" \/>/);

  // A noindex page must not appear in the sitemap.
  assert.ok(!result.sitemapXml.includes('/how-to/soft-issue'), 'noindex page must be excluded from the sitemap');
});

test('a duplicate title across two pages aborts the build with a hard error', () => {
  const websiteDir = freshWebsiteDir();
  assert.throws(
    () =>
      run({
        pagesDir: path.join(FIXTURES_DIR, 'pages-dup'),
        websiteDir,
        manifestPath: FIXTURE_MANIFEST,
        write: true,
      }),
    (err) => {
      assert.ok(err instanceof BuildError, 'should throw a BuildError');
      assert.ok(
        err.errors.some((e) => /duplicate title/i.test(e)),
        `expected a duplicate-title error, got: ${err.errors.join(' | ')}`
      );
      return true;
    }
  );
  // Nothing should have been written for the aborted build.
  assert.ok(!fs.existsSync(path.join(websiteDir, 'how-to', 'dup-a.html')));
});

test('sitemap.xml includes the indexable generated page and the hub pages', () => {
  const websiteDir = freshWebsiteDir();
  const result = run({
    pagesDir: path.join(FIXTURES_DIR, 'pages'),
    websiteDir,
    manifestPath: FIXTURE_MANIFEST,
    write: true,
  });
  assert.ok(result.sitemapXml.includes('<loc>https://kinrows.com/how-to/sample-howto</loc>'));
  assert.ok(result.sitemapXml.includes('<loc>https://kinrows.com/how-to/</loc>'));
  assert.ok(result.sitemapXml.includes('<loc>https://kinrows.com/alternatives/sample-alternative</loc>'));
  assert.ok(result.sitemapXml.includes('<loc>https://kinrows.com/</loc>'), 'hand-written manifest urls carried over');

  const writtenSitemap = fs.readFileSync(path.join(websiteDir, 'sitemap.xml'), 'utf8');
  assert.equal(writtenSitemap, result.sitemapXml);
});

test('hub pages carry their own unique BreadcrumbList and no .html internal links', () => {
  const websiteDir = freshWebsiteDir();
  const result = run({
    pagesDir: path.join(FIXTURES_DIR, 'pages'),
    websiteDir,
    manifestPath: FIXTURE_MANIFEST,
    write: true,
  });
  const hub = result.hubOutputs.find((o) => o.path === 'how-to/index.html');
  assert.ok(hub);
  assert.match(hub.html, /<link rel="canonical" href="https:\/\/kinrows\.com\/how-to\/" \/>/);
  assert.ok(!/href="[^"]*\.html"/.test(hub.html), 'hub page must not link internally with .html');
  const blocks = [...hub.html.matchAll(/<script type="application\/ld\+json">\n([\s\S]*?)\n<\/script>/g)].map((m) =>
    JSON.parse(m[1])
  );
  const breadcrumb = blocks.find((b) => b['@type'] === 'BreadcrumbList');
  assert.ok(breadcrumb);
  assert.equal(breadcrumb.itemListElement.length, 2);
});

test('--check style run (write: false) validates without writing any files', () => {
  const websiteDir = freshWebsiteDir();
  const result = run({
    pagesDir: path.join(FIXTURES_DIR, 'pages'),
    websiteDir,
    manifestPath: FIXTURE_MANIFEST,
    check: true,
  });
  assert.equal(result.pages.length, 5);
  assert.ok(!fs.existsSync(path.join(websiteDir, 'how-to', 'sample-howto.html')));
  assert.ok(!fs.existsSync(path.join(websiteDir, 'sitemap.xml')));
});
