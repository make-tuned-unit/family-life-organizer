#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const { PAGE_TYPES, pageOutputFile, hubOutputFile, SITE_BASE } = require('./lib/util');
const { readHeadMeta } = require('./lib/head-meta');
const { validateAll } = require('./lib/validate');
const { renderPageHtml, renderHubHtml } = require('./lib/render');
const { buildSitemapXml } = require('./lib/sitemap');

const DEFAULT_PAGES_DIR = path.join(__dirname, 'pages');
const DEFAULT_WEBSITE_DIR = path.join(__dirname, '..', 'website');
const DEFAULT_MANIFEST_PATH = path.join(__dirname, 'site-manifest.json');

const HUB_COPY = {
  howto: {
    description:
      'Step-by-step, plain-English guides for running a family household — from chores to calendars to the mental load.',
    h1: 'How-to guides for running a household',
    intro: 'Practical, step-by-step guides for the everyday logistics of family life.',
  },
  alternative: {
    description:
      'Honest alternatives to the family organizer apps you already know — what each one does well, and where Kinrows fits.',
    h1: 'Alternatives to popular family apps',
    intro: 'Looking for an alternative to your current family app? Here is how the options compare.',
  },
  compare: {
    description:
      'Head-to-head comparisons between Kinrows and other family organizer apps, so you can pick the right one for your household.',
    h1: 'Compare Kinrows with other family apps',
    intro: 'Straight, side-by-side comparisons to help you pick the right family organizer.',
  },
  persona: {
    description:
      'Kinrows for your kind of household — guidance for the specific situations real families are juggling.',
    h1: 'Kinrows for your family',
    intro: 'Different households need different things. Here is Kinrows for yours.',
  },
  question: {
    description:
      'Quick, honest answers to the questions families ask most about organizing home life together.',
    h1: 'Questions families ask us',
    intro: 'Short, straight answers to the questions we hear most.',
  },
};

class BuildError extends Error {
  constructor(errors) {
    super(`SEO build failed with ${errors.length} error(s):\n` + errors.map((e) => `  - ${e}`).join('\n'));
    this.errors = errors;
  }
}

function loadManifest(manifestPath) {
  const raw = fs.readFileSync(manifestPath, 'utf8');
  return JSON.parse(raw);
}

function loadManifestMeta(manifestEntries, websiteDir) {
  const errors = [];
  const meta = manifestEntries.map((entry) => {
    const abs = path.join(websiteDir, entry.file);
    try {
      const m = readHeadMeta(abs);
      return { url: entry.url, ...m };
    } catch (e) {
      errors.push(`manifest entry "${entry.url}": could not read ${entry.file} — ${e.message}`);
      return { url: entry.url, title: '', description: '', h1: '' };
    }
  });
  return { meta, errors };
}

function loadPages(pagesDir) {
  const loaded = [];
  for (const pageType of Object.keys(PAGE_TYPES)) {
    const dir = path.join(pagesDir, pageType);
    if (!fs.existsSync(dir)) continue;
    const files = fs.readdirSync(dir).filter((f) => f.endsWith('.json'));
    for (const f of files) {
      const rel = `${pageType}/${f}`;
      const abs = path.join(dir, f);
      const raw = fs.readFileSync(abs, 'utf8');
      try {
        const page = JSON.parse(raw);
        loaded.push({ page, file: rel, expectedPageType: pageType, parseError: null });
      } catch (e) {
        loaded.push({ page: null, file: rel, expectedPageType: pageType, parseError: e });
      }
    }
  }
  return loaded;
}

function groupByType(pages) {
  const byType = {};
  for (const t of Object.keys(PAGE_TYPES)) byType[t] = [];
  for (const p of pages) byType[p.pageType].push(p);
  for (const t of Object.keys(byType)) {
    byType[t].sort((a, b) => a.slug.localeCompare(b.slug));
  }
  return byType;
}

function hubLastmod(pagesOfType) {
  const indexable = pagesOfType.filter((p) => p.effectiveIndexStatus === 'index');
  if (!indexable.length) return new Date().toISOString().slice(0, 10);
  return indexable.reduce((max, p) => (p.lastReviewed > max ? p.lastReviewed : max), indexable[0].lastReviewed);
}

// Core build. Options are all injectable so tests can point at fixtures.
function run(options = {}) {
  const pagesDir = options.pagesDir || DEFAULT_PAGES_DIR;
  const websiteDir = options.websiteDir || DEFAULT_WEBSITE_DIR;
  const manifestPath = options.manifestPath || DEFAULT_MANIFEST_PATH;
  const sitemapPath = options.sitemapPath || path.join(websiteDir, 'sitemap.xml');
  const siteBase = options.siteBase || SITE_BASE;
  const check = !!options.check;
  const dryRun = !!options.dryRun;
  const write = options.write !== undefined ? options.write : !check && !dryRun;

  const manifestEntries = loadManifest(manifestPath);
  const { meta: manifestMeta, errors: manifestErrors } = loadManifestMeta(manifestEntries, websiteDir);
  const loaded = loadPages(pagesDir);

  const { hardErrors: validationErrors, warnings, processedPages } = validateAll({
    loaded,
    manifestEntries,
    manifestMeta,
    websiteDir,
  });

  const hardErrors = manifestErrors.concat(validationErrors);
  if (hardErrors.length) {
    throw new BuildError(hardErrors);
  }

  const byType = groupByType(processedPages);

  const pageOutputs = [];
  for (const page of processedPages) {
    const html = renderPageHtml(page, { siteBase, websiteDir });
    pageOutputs.push({ path: pageOutputFile(page), html, page });
  }

  const hubOutputs = [];
  const hubs = [];
  for (const pageType of Object.keys(PAGE_TYPES)) {
    const all = byType[pageType];
    const indexable = all.filter((p) => p.effectiveIndexStatus === 'index');
    const copy = HUB_COPY[pageType];
    const html = renderHubHtml(pageType, indexable, {
      siteBase,
      hubDescription: copy.description,
      hubH1: copy.h1,
      hubIntro: copy.intro,
    });
    hubOutputs.push({ path: hubOutputFile(pageType), html });
    hubs.push({ pageType, lastmod: hubLastmod(all) });
  }

  const sitemapXml = buildSitemapXml(manifestEntries, processedPages, hubs);

  const result = {
    pages: processedPages,
    warnings,
    pageOutputs,
    hubOutputs,
    sitemapXml,
    sitemapPath,
    websiteDir,
  };

  if (dryRun) {
    for (const out of pageOutputs.concat(hubOutputs)) {
      const abs = path.join(websiteDir, out.path);
      const existed = fs.existsSync(abs);
      const changed = existed && fs.readFileSync(abs, 'utf8') !== out.html;
      const status = !existed ? 'NEW' : changed ? 'CHANGED' : 'UNCHANGED';
      // eslint-disable-next-line no-console
      console.log(`[dry-run] ${status}  website/${out.path}`);
    }
    const sitemapExisted = fs.existsSync(sitemapPath);
    const sitemapChanged = sitemapExisted && fs.readFileSync(sitemapPath, 'utf8') !== sitemapXml;
    // eslint-disable-next-line no-console
    console.log(
      `[dry-run] ${!sitemapExisted ? 'NEW' : sitemapChanged ? 'CHANGED' : 'UNCHANGED'}  ${path.relative(
        process.cwd(),
        sitemapPath
      )}`
    );
  }

  if (write) {
    for (const out of pageOutputs.concat(hubOutputs)) {
      const abs = path.join(websiteDir, out.path);
      fs.mkdirSync(path.dirname(abs), { recursive: true });
      fs.writeFileSync(abs, out.html, 'utf8');
    }
    fs.mkdirSync(path.dirname(sitemapPath), { recursive: true });
    fs.writeFileSync(sitemapPath, sitemapXml, 'utf8');
  }

  return result;
}

function main() {
  const args = process.argv.slice(2);
  const check = args.includes('--check');
  const dryRun = args.includes('--dry-run');
  try {
    const result = run({ check, dryRun });
    if (result.warnings.length) {
      // eslint-disable-next-line no-console
      console.log(result.warnings.map((w) => `WARN ${w}`).join('\n'));
    }
    const verb = check ? 'validated' : dryRun ? 'checked (dry run)' : 'built';
    // eslint-disable-next-line no-console
    console.log(
      `SEO ${verb}: ${result.pages.length} page(s), ${result.hubOutputs.length} hub(s)${
        result.warnings.length ? `, ${result.warnings.length} warning(s)` : ''
      }.`
    );
    process.exit(0);
  } catch (e) {
    if (e instanceof BuildError) {
      // eslint-disable-next-line no-console
      console.error(e.message);
    } else {
      // eslint-disable-next-line no-console
      console.error(`SEO build failed: ${e.stack || e.message}`);
    }
    process.exit(1);
  }
}

if (require.main === module) {
  main();
}

module.exports = {
  run,
  BuildError,
  loadManifest,
  loadManifestMeta,
  loadPages,
  groupByType,
  HUB_COPY,
  DEFAULT_PAGES_DIR,
  DEFAULT_WEBSITE_DIR,
  DEFAULT_MANIFEST_PATH,
};
