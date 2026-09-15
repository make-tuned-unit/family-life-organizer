#!/usr/bin/env node
/**
 * SEO / content conversion report.
 *
 * Reads the same permagent_analytics_events + waitlist tables the site writes
 * to (see dashboard.js POST /api/permagent-analytics/collect and POST
 * /api/waitlist) and prints, for a trailing window of days:
 *   - pageviews by path
 *   - waitlist signups by source, and by landing_path
 *   - conversions per 1,000 pageviews, grouped by page class (home, roundup,
 *     blog, how-to, alternatives, compare, for, questions, other)
 *   - top referrers, with a separate bucket for AI answer engines
 *     (ChatGPT, Perplexity, Claude, Copilot, Gemini, Bing, You.com,
 *     DuckDuckGo AI chat)
 *
 * Bot traffic (is_bot=1) is excluded from every count — the site explicitly
 * welcomes AI/LLM crawlers (see website/robots.txt) so they show up a lot,
 * but they never convert and would dwarf the real numbers.
 *
 * Usage:
 *   node scripts/seo-report.js [--days 30] [--db /path/to/family.db]
 */

const fs = require('fs');
const path = require('path');
const sqlite3 = require('sqlite3');

function argValue(flag, fallback) {
  const i = process.argv.indexOf(flag);
  if (i === -1 || i === process.argv.length - 1) return fallback;
  return process.argv[i + 1];
}

const DAYS = Math.max(1, parseInt(argValue('--days', '30'), 10) || 30);

// Resolve the DB path the same way database.js does, unless --db overrides it.
function defaultDbPath() {
  const dir = process.env.FAMILY_DB_DIR
    ? process.env.FAMILY_DB_DIR
    : process.env.RENDER_DISK_PATH
    ? '/opt/render/project/src/vault/family-life'
    : path.join(process.env.HOME || '/tmp', '.openclaw/workspace/vault/family-life');
  return path.join(dir, 'family.db');
}

const DB_PATH = argValue('--db', defaultDbPath());

if (!fs.existsSync(DB_PATH)) {
  console.error(`[seo-report] database not found at ${DB_PATH}`);
  process.exit(1);
}

const db = new sqlite3.Database(DB_PATH, sqlite3.OPEN_READONLY);
const all = (sql, params = []) => new Promise((resolve, reject) => {
  db.all(sql, params, (err, rows) => (err ? reject(err) : resolve(rows)));
});

// ── Page classification ─────────────────────────────────────────────────────
const PAGE_CLASSES = ['home', 'roundup', 'blog', 'how-to', 'alternatives', 'compare', 'for', 'questions', 'other'];
function pageClass(p) {
  const s = String(p || '');
  if (s === '/' || s === '') return 'home';
  if (/^\/best-/.test(s)) return 'roundup';
  if (/^\/blog\/?/.test(s)) return 'blog';
  if (/^\/how-to\/?/.test(s)) return 'how-to';
  if (/^\/alternatives\/?/.test(s)) return 'alternatives';
  if (/^\/compare\/?/.test(s)) return 'compare';
  if (/^\/for\/?/.test(s)) return 'for';
  if (/^\/questions\/?/.test(s)) return 'questions';
  return 'other';
}

// ── AI answer-engine referrers ──────────────────────────────────────────────
const AI_ENGINE_HOSTS = [
  'chatgpt.com', 'chat.openai.com', 'perplexity.ai', 'claude.ai',
  'copilot.microsoft.com', 'gemini.google.com', 'bing.com', 'you.com',
];
function referrerHost(ref) {
  try { return new URL(ref).hostname.replace(/^www\./, ''); } catch { return null; }
}
function isAiEngineReferrer(ref) {
  const host = referrerHost(ref);
  if (!host) return false;
  if (AI_ENGINE_HOSTS.some((h) => host === h || host.endsWith(`.${h}`))) return true;
  if (host.endsWith('duckduckgo.com')) {
    try { return new URL(ref).pathname.startsWith('/aichat'); } catch { return false; }
  }
  return false;
}

// ── Plain-text table printer (no deps) ──────────────────────────────────────
function printTable(headers, rows) {
  const widths = headers.map((h, i) => Math.max(
    String(h).length,
    ...rows.map((r) => String(r[i] ?? '').length),
  ));
  const line = (cells) => cells.map((c, i) => String(c).padEnd(widths[i])).join('  ');
  console.log(line(headers));
  console.log(widths.map((w) => '-'.repeat(w)).join('  '));
  for (const r of rows) console.log(line(r));
  if (!rows.length) console.log('(none)');
}
function heading(title) {
  console.log(`\n=== ${title} ===`);
}

(async () => {
  const since = `-${DAYS} days`;

  heading(`SEO report — last ${DAYS} day(s) — ${DB_PATH}`);

  // Pageviews by path
  const pageviews = await all(
    `SELECT path, COUNT(*) AS c FROM permagent_analytics_events
     WHERE kind = 'pageview' AND is_bot = 0 AND created_at >= datetime('now', ?)
     GROUP BY path ORDER BY c DESC LIMIT 50`,
    [since],
  );
  heading('Pageviews by path (top 50, non-bot)');
  printTable(['path', 'pageviews'], pageviews.map((r) => [r.path || '(none)', r.c]));

  // Waitlist signups by source
  const bySource = await all(
    `SELECT COALESCE(source, '(none)') AS source, COUNT(*) AS c FROM waitlist
     WHERE created_at >= datetime('now', ?) GROUP BY source ORDER BY c DESC`,
    [since],
  );
  heading('Waitlist signups by source');
  printTable(['source', 'signups'], bySource.map((r) => [r.source, r.c]));

  // Waitlist signups by landing_path
  const byLanding = await all(
    `SELECT COALESCE(landing_path, '(unknown)') AS landing_path, COUNT(*) AS c FROM waitlist
     WHERE created_at >= datetime('now', ?) GROUP BY landing_path ORDER BY c DESC LIMIT 50`,
    [since],
  );
  heading('Waitlist signups by landing page (top 50)');
  printTable(['landing_path', 'signups'], byLanding.map((r) => [r.landing_path, r.c]));

  // Conversions per 1,000 pageviews, by page class
  const classPageviews = new Map(PAGE_CLASSES.map((c) => [c, 0]));
  for (const r of pageviews) classPageviews.set(pageClass(r.path), (classPageviews.get(pageClass(r.path)) || 0) + r.c);
  const landingRows = await all(
    `SELECT landing_path, COUNT(*) AS c FROM waitlist
     WHERE created_at >= datetime('now', ?) GROUP BY landing_path`,
    [since],
  );
  const classSignups = new Map(PAGE_CLASSES.map((c) => [c, 0]));
  for (const r of landingRows) classSignups.set(pageClass(r.landing_path), (classSignups.get(pageClass(r.landing_path)) || 0) + r.c);
  heading('Conversion rate by page class (waitlist signups per 1,000 pageviews)');
  printTable(
    ['class', 'pageviews', 'signups', 'per_1000_pv'],
    PAGE_CLASSES.map((c) => {
      const pv = classPageviews.get(c) || 0;
      const sg = classSignups.get(c) || 0;
      const rate = pv > 0 ? ((sg / pv) * 1000).toFixed(2) : '—';
      return [c, pv, sg, rate];
    }),
  );

  // Top referrers, with a separate AI-answer-engine bucket
  const referrers = await all(
    `SELECT referrer, COUNT(*) AS c FROM permagent_analytics_events
     WHERE kind = 'pageview' AND is_bot = 0 AND referrer IS NOT NULL AND referrer != ''
       AND created_at >= datetime('now', ?)
     GROUP BY referrer ORDER BY c DESC LIMIT 500`,
    [since],
  );
  const hostCounts = new Map();
  let aiTotal = 0;
  const aiHostCounts = new Map();
  for (const r of referrers) {
    const host = referrerHost(r.referrer) || r.referrer;
    hostCounts.set(host, (hostCounts.get(host) || 0) + r.c);
    if (isAiEngineReferrer(r.referrer)) {
      aiTotal += r.c;
      aiHostCounts.set(host, (aiHostCounts.get(host) || 0) + r.c);
    }
  }
  const topHosts = [...hostCounts.entries()].sort((a, b) => b[1] - a[1]).slice(0, 30);
  heading('Top referrers (top 30, non-bot)');
  printTable(['referrer host', 'pageviews'], topHosts.map(([h, c]) => [h, c]));

  heading(`AI answer engines (total: ${aiTotal})`);
  const topAi = [...aiHostCounts.entries()].sort((a, b) => b[1] - a[1]);
  printTable(['ai engine host', 'pageviews'], topAi.map(([h, c]) => [h, c]));

  db.close();
})().catch((err) => {
  console.error('[seo-report] error:', err.message);
  process.exit(1);
});
