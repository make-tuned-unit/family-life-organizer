// Permagent drain contract: the daemon serde-decodes camelCase JSON and
// rejects SQLite's 0/1 integers as isBot. A decode failure is logged as
// "malformed drain response" and looks like the drain URL fell off in the app.
const { test, before, after } = require('node:test');
const assert = require('node:assert');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const PORT = 3989;
const BASE = `http://127.0.0.1:${PORT}`;
const KEY = 'test-drain-key-not-for-prod';
let server;
let tmpDir;

async function waitForHealth(timeoutMs = 15000) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    try {
      const res = await fetch(BASE + '/healthz');
      if (res.ok) return;
    } catch {}
    await new Promise(r => setTimeout(r, 200));
  }
  throw new Error('server did not become healthy');
}

before(async () => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'fl-analytics-'));
  server = spawn('node', ['dashboard.js'], {
    cwd: path.join(__dirname, '..'),
    env: {
      ...process.env,
      PORT: String(PORT),
      FAMILY_DB_DIR: tmpDir,
      SESSION_SECRET: 'test-secret',
      NODE_ENV: 'test',
      ANTHROPIC_API_KEY: '',
      PERMAGENT_ANALYTICS_KEY: KEY,
      PERMAGENT_ANALYTICS_SALT: 'test-salt',
    },
    stdio: 'ignore',
  });
  await waitForHealth();
});

after(() => {
  if (server) server.kill('SIGKILL');
  if (tmpDir) fs.rmSync(tmpDir, { recursive: true, force: true });
});

test('analytics: marketing HTML carries the collect path for Permagent verify', async () => {
  const home = await (await fetch(BASE + '/')).text();
  assert.match(home, /\/api\/permagent-analytics\/collect/, 'home page names the collect path');
  const blog = await (await fetch(BASE + '/blog/how-to-sleep-train-a-baby.html')).text();
  assert.match(blog, /\/api\/permagent-analytics\/collect/, 'blog pages are not left on the static fallback');
});

test('analytics: drain rejects a missing or wrong key', async () => {
  const missing = await fetch(BASE + '/api/permagent-analytics/drain');
  assert.equal(missing.status, 401);
  const wrong = await fetch(BASE + '/api/permagent-analytics/drain', {
    headers: { 'x-permagent-key': 'nope' },
  });
  assert.equal(wrong.status, 401);
});

test('analytics: empty drain still returns the v41 envelope', async () => {
  const res = await fetch(BASE + '/api/permagent-analytics/drain?since=0&limit=500', {
    headers: { 'x-permagent-key': KEY },
  });
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.deepEqual(body.events, []);
  assert.equal(body.latestId, null);
  assert.equal(body.firstAvailableId, null);
});

test('analytics: drain envelope uses real booleans so Permagent can decode it', async () => {
  const collect = await fetch(BASE + '/api/permagent-analytics/collect', {
    method: 'POST',
    headers: { 'Content-Type': 'text/plain', 'User-Agent': 'Mozilla/5.0 test-browser' },
    body: JSON.stringify({ k: 'pv', p: '/pricing?utm_source=test', r: null, n: null, d: null, s: 'sess1' }),
  });
  assert.equal(collect.status, 202);

  const res = await fetch(BASE + '/api/permagent-analytics/drain?since=0&limit=10', {
    headers: { 'x-permagent-key': KEY },
  });
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.ok(Array.isArray(body.events), 'envelope has events[]');
  assert.equal(typeof body.latestId, 'number');
  assert.equal(typeof body.firstAvailableId, 'number');
  assert.ok(body.events.length >= 1);
  const ev = body.events[0];
  assert.equal(typeof ev.isBot, 'boolean', 'isBot must not be 0/1 — serde will reject integers');
  assert.equal(typeof ev.id, 'number');
  assert.ok(typeof ev.at === 'string' && ev.at.includes('T'), 'at is ISO-8601');
  assert.equal(ev.kind, 'pageview');
});

test('analytics: custom events drain with a name and flat properties', async () => {
  const collect = await fetch(BASE + '/api/permagent-analytics/collect', {
    method: 'POST',
    headers: { 'Content-Type': 'text/plain', 'User-Agent': 'Mozilla/5.0 test-browser' },
    body: JSON.stringify({
      k: 'ev',
      p: '/subscribe.html',
      r: null,
      n: 'sale_plan_click',
      d: { product_id: 'com.kinrows.app.concierge.lite.monthly', period: 'monthly', nested: { drop: 1 } },
      s: 'sess-sale',
    }),
  });
  assert.equal(collect.status, 202);

  const res = await fetch(BASE + '/api/permagent-analytics/drain?since=0&limit=50', {
    headers: { 'x-permagent-key': KEY },
  });
  const body = await res.json();
  const ev = body.events.find((e) => e.name === 'sale_plan_click');
  assert.ok(ev, 'sale_plan_click drained');
  assert.equal(ev.kind, 'event');
  assert.equal(ev.properties.product_id, 'com.kinrows.app.concierge.lite.monthly');
  assert.equal(ev.properties.period, 'monthly');
  assert.equal(ev.properties.nested, undefined);
});

test('stripeSaleEvent maps Checkout, invoice, and cancel webhooks', () => {
  const permagent = require('../services/permagent');
  const complete = permagent.stripeSaleEvent(
    {
      type: 'checkout.session.completed',
      data: { object: {
        livemode: false,
        currency: 'cad',
        amount_total: 9999,
        metadata: { kinrows_product_id: 'com.kinrows.app.concierge.premium.yearly', kinrows_source: 'app' },
      } },
    },
    { applied: true, productId: 'com.kinrows.app.concierge.premium.yearly', status: 'active', tier: 'premium' },
  );
  assert.equal(complete.name, 'sale_checkout_complete');
  assert.equal(complete.properties.source, 'app');
  assert.equal(complete.properties.amount_cents, 9999);
  assert.equal(complete.properties.tier, 'premium');
  assert.equal(complete.properties.period, 'yearly');

  const paid = permagent.stripeSaleEvent(
    { type: 'invoice.paid', data: { object: { currency: 'usd', amount_paid: 499, billing_reason: 'subscription_cycle' } } },
    { applied: true, productId: 'com.kinrows.app.concierge.lite.monthly', status: 'active', tier: 'lite' },
  );
  assert.equal(paid.name, 'sale_invoice_paid');
  assert.equal(paid.properties.billing_reason, 'subscription_cycle');

  const failed = permagent.stripeSaleEvent(
    { type: 'invoice.payment_failed', data: { object: {} } },
    { applied: true, productId: 'com.kinrows.app.concierge.lite.monthly', status: 'expired', tier: 'lite' },
  );
  assert.equal(failed.name, 'sale_payment_failed');

  const canceled = permagent.stripeSaleEvent(
    { type: 'customer.subscription.deleted', data: { object: {} } },
    { applied: true, productId: 'com.kinrows.app.concierge.premium.monthly', status: 'expired', tier: 'premium' },
  );
  assert.equal(canceled.name, 'sale_subscription_canceled');

  assert.equal(permagent.stripeSaleEvent({ type: 'ping' }, { applied: false }), null);
});
