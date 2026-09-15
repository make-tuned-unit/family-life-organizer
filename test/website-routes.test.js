// Clean marketing URLs: the generic resolver in dashboard.js replaces the old
// per-page app.get pairs. Covers clean-URL 200s, legacy .html 301s, the
// branded 404, and that /api and other authenticated routes are unaffected.

const { test, before, after } = require('node:test');
const assert = require('node:assert');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const sqlite3 = require('sqlite3');

const PORT = 3982;
const BASE = `http://127.0.0.1:${PORT}`;
let server, tmpDir;

async function waitForHealth(t = 15000) {
  const s = Date.now();
  while (Date.now() - s < t) {
    try { if ((await fetch(BASE + '/healthz')).ok) return; } catch {}
    await new Promise((r) => setTimeout(r, 200));
  }
  throw new Error('server did not become healthy');
}

before(async () => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'fl-website-routes-'));
  server = spawn('node', ['dashboard.js'], {
    cwd: path.join(__dirname, '..'),
    env: {
      ...process.env,
      PORT: String(PORT),
      FAMILY_DB_DIR: tmpDir,
      SESSION_SECRET: 'test-secret',
      NODE_ENV: 'test',
      ANTHROPIC_API_KEY: '',
      RESEND_API_KEY: '',
    },
    stdio: 'ignore',
  });
  await waitForHealth();
});

after(() => {
  if (server) server.kill('SIGKILL');
  if (tmpDir) fs.rmSync(tmpDir, { recursive: true, force: true });
});

test('clean URL serves the page with CSP and the analytics collect string', async () => {
  const res = await fetch(BASE + '/compare', { redirect: 'manual' });
  assert.equal(res.status, 200);
  assert.ok(res.headers.get('content-security-policy'), 'CSP header present');
  const html = await res.text();
  assert.match(html, /\/api\/permagent-analytics\/collect/);
});

test('legacy .html URL 301s to the clean URL, preserving query string', async () => {
  const res = await fetch(BASE + '/compare.html?utm_source=test', { redirect: 'manual' });
  assert.equal(res.status, 301);
  assert.equal(res.headers.get('location'), '/compare?utm_source=test');
});

test('/index.html 301s to /', async () => {
  const res = await fetch(BASE + '/index.html', { redirect: 'manual' });
  assert.equal(res.status, 301);
  assert.equal(res.headers.get('location'), '/');
});

test('/blog/<slug>.html 301s to the clean blog URL', async () => {
  const res = await fetch(BASE + '/blog/how-to-sleep-train-a-baby.html', { redirect: 'manual' });
  assert.equal(res.status, 301);
  assert.equal(res.headers.get('location'), '/blog/how-to-sleep-train-a-baby');

  const clean = await fetch(BASE + '/blog/how-to-sleep-train-a-baby', { redirect: 'manual' });
  assert.equal(clean.status, 200);
});

test('/blog (no trailing slash) 301s to /blog/, which serves 200', async () => {
  const res = await fetch(BASE + '/blog', { redirect: 'manual' });
  assert.equal(res.status, 301);
  assert.equal(res.headers.get('location'), '/blog/');

  const index = await fetch(BASE + '/blog/', { redirect: 'manual' });
  assert.equal(index.status, 200);
});

test('unknown path returns the branded 404 page', async () => {
  const res = await fetch(BASE + '/this-page-does-not-exist', { redirect: 'manual' });
  assert.equal(res.status, 404);
  const html = await res.text();
  assert.match(html, /Kinrows/);
  assert.match(html, /noindex/);
});

test('/api/waitlist/status still reaches the API (unaffected by the resolver)', async () => {
  const res = await fetch(BASE + '/api/waitlist/status?ref_code=zz', { redirect: 'manual' });
  assert.equal(res.status, 400);
});

test('/app and /login are not shadowed by the clean-URL resolver', async () => {
  const app = await fetch(BASE + '/app', { redirect: 'manual' });
  assert.notEqual(app.status, 404);
  const login = await fetch(BASE + '/login', { redirect: 'manual' });
  assert.equal(login.status, 200);
});

test('path traversal attempts are rejected with 404, not a file', async () => {
  const res = await fetch(BASE + '/..%2f..%2fetc%2fpasswd', { redirect: 'manual' });
  assert.equal(res.status, 404);
});

test('POST /api/waitlist with a landing path stores landing_path', async () => {
  const res = await fetch(BASE + '/api/waitlist', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'landing-test@example.com', source: 'site', landing: '/how-to/x' }),
  });
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.success, true);

  const dbPath = path.join(tmpDir, 'family.db');
  const row = await new Promise((resolve, reject) => {
    const db = new sqlite3.Database(dbPath, sqlite3.OPEN_READONLY);
    db.get('SELECT landing_path FROM waitlist WHERE email = ?', ['landing-test@example.com'], (err, r) => {
      db.close();
      err ? reject(err) : resolve(r);
    });
  });
  assert.equal(row.landing_path, '/how-to/x');
});
