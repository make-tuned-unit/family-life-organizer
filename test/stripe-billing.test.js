// Stripe Concierge web billing: catalog, checkout gates, webhook signature,
// and household entitlement from a signed event (no live Stripe calls).

const { test, before, after } = require('node:test');
const assert = require('node:assert');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');

const PORT = 3985;
const BASE = `http://127.0.0.1:${PORT}`;
const WHSEC = 'whsec_test_kinrows_' + crypto.randomBytes(8).toString('hex');
let server, tmpDir;

const stripe = require('../services/stripe');
const subscription = require('../services/subscription');

function makeClient() {
  let cookie = '';
  return async (method, pathname, body, headers = {}) => {
    const res = await fetch(BASE + pathname, {
      method,
      headers: { 'Content-Type': 'application/json', ...(cookie ? { Cookie: cookie } : {}), ...headers },
      body: body ? JSON.stringify(body) : undefined,
      redirect: 'manual',
    });
    const sc = res.headers.get('set-cookie');
    if (sc) cookie = sc.split(';')[0];
    let json = null; try { json = await res.json(); } catch {}
    return { status: res.status, body: json };
  };
}

async function waitForHealth(t = 15000) {
  const s = Date.now();
  while (Date.now() - s < t) {
    try { if ((await fetch(BASE + '/healthz')).ok) return; } catch {}
    await new Promise(r => setTimeout(r, 200));
  }
  throw new Error('server did not become healthy');
}

function fakeSub({ groupId, userId, productId, status = 'active', livemode = false }) {
  const now = Math.floor(Date.now() / 1000);
  return {
    id: 'sub_test_' + crypto.randomBytes(6).toString('hex'),
    status,
    livemode,
    current_period_end: now + 30 * 24 * 3600,
    metadata: {
      kinrows_group_id: String(groupId),
      kinrows_user_id: String(userId),
      kinrows_product_id: productId,
    },
    items: { data: [{ price: { lookup_key: productId, metadata: { kinrows_product_id: productId } } }] },
  };
}

before(async () => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'fl-stripe-'));
  server = spawn('node', ['dashboard.js'], {
    cwd: path.join(__dirname, '..'),
    env: {
      ...process.env,
      PORT: String(PORT),
      FAMILY_DB_DIR: tmpDir,
      SESSION_SECRET: 'test',
      NODE_ENV: 'test',
      ANTHROPIC_API_KEY: '',
      STRIPE_SECRET_KEY: '',
      STRIPE_WEBHOOK_SECRET: WHSEC,
      STRIPE_ALLOW_TEST: '1',
    },
    stdio: 'ignore',
  });
  await waitForHealth();
});
after(() => { if (server) server.kill('SIGKILL'); if (tmpDir) fs.rmSync(tmpDir, { recursive: true, force: true }); });

test('webhook signature accepts a matching HMAC and rejects a bad one', () => {
  const body = '{"id":"evt_1","type":"ping"}';
  const header = stripe.signWebhookPayload(body, WHSEC);
  assert.equal(stripe.verifyWebhookSignature(body, header, WHSEC), true);
  assert.equal(stripe.verifyWebhookSignature(body, header, 'whsec_other'), false);
  assert.equal(stripe.verifyWebhookSignature(body + 'x', header, WHSEC), false);
  assert.equal(stripe.verifyWebhookSignature(body, 't=1,v1=00', WHSEC), false);
});

test('catalog is public and lists the four Concierge plans', async () => {
  const res = await fetch(BASE + '/api/subscription/catalog');
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.stripe, false);
  assert.equal(body.currency, 'cad');
  assert.equal(body.plans.length, 4);
  assert.equal(body.caps.lite, 10);
  assert.equal(body.caps.premium, 40);
  assert.ok(body.plans.every(p => p.product_id.startsWith('com.kinrows.app.concierge.')));
  assert.ok(body.plans.every(p => p.currency === 'cad'));
  assert.equal(body.plans.find(p => p.tier === 'lite').chats, 10);
  assert.equal(body.plans.find(p => p.tier === 'premium').chats, 40);
});

test('presentment currency follows country, Accept-Language, then CAD', () => {
  assert.equal(subscription.presentmentCurrencyFromHints({ country: 'CA' }), 'cad');
  assert.equal(subscription.presentmentCurrencyFromHints({ country: 'US' }), 'usd');
  assert.equal(subscription.presentmentCurrencyFromHints({ country: 'FR' }), 'eur');
  assert.equal(subscription.presentmentCurrencyFromHints({ country: 'GB' }), 'cad');
  assert.equal(subscription.presentmentCurrencyFromHints({ acceptLanguage: 'en-US,en;q=0.9' }), 'usd');
  assert.equal(subscription.presentmentCurrencyFromHints({ explicit: 'eur', country: 'US' }), 'eur');
  assert.equal(subscription.presentmentCurrencyFromHints({}), 'cad');
});

test('catalog honors ?currency= and geo country headers', async () => {
  const eur = await fetch(BASE + '/api/subscription/catalog?currency=eur');
  assert.equal(eur.status, 200);
  const eurBody = await eur.json();
  assert.equal(eurBody.currency, 'eur');
  assert.ok(eurBody.plans.every(p => p.currency === 'eur'));

  const us = await fetch(BASE + '/api/subscription/catalog', { headers: { 'CF-IPCountry': 'US' } });
  assert.equal((await us.json()).currency, 'usd');
});

test('Apple Pay domain association file is served', async () => {
  const res = await fetch(BASE + '/.well-known/apple-developer-merchantid-domain-association');
  assert.equal(res.status, 200);
  const body = await res.text();
  assert.ok(body.length > 100);
  assert.match(res.headers.get('content-type') || '', /octet-stream|text\/plain/i);
});

test('checkout requires auth, a known plan, and a configured Stripe key', async () => {
  const anon = makeClient();
  assert.equal((await anon('POST', '/api/subscription/checkout', { product_id: 'com.kinrows.app.concierge.lite.monthly' })).status, 401);

  const ada = makeClient();
  const reg = await ada('POST', '/api/auth/register', { username: 'stripe_ada', password: 'password123', name: 'Ada Stripe' });
  assert.equal(reg.status, 200);

  const unknown = await ada('POST', '/api/subscription/checkout', { product_id: 'not-a-plan' });
  assert.equal(unknown.status, 400);

  const unconfigured = await ada('POST', '/api/subscription/checkout', {
    product_id: 'com.kinrows.app.concierge.premium.yearly',
  });
  assert.equal(unconfigured.status, 503);
});

test('signed webhook unlocks the household; unsigned is refused', async () => {
  const ada = makeClient();
  await ada('POST', '/api/auth/register', { username: 'stripe_ben', password: 'password123', name: 'Ben Stripe' });
  const me = await ada('GET', '/api/auth/me');
  const group = (me.body.groups || []).find(g => g.group_type === 'household') || me.body.groups[0];
  assert.ok(group && group.id);
  const userId = me.body.user.id;

  const before = await ada('GET', '/api/subscription/status');
  assert.equal(before.body.premium, false);

  const sub = fakeSub({
    groupId: group.id,
    userId,
    productId: 'com.kinrows.app.concierge.lite.monthly',
  });
  const event = {
    id: 'evt_test_1',
    type: 'customer.subscription.updated',
    data: { object: sub },
  };
  const raw = JSON.stringify(event);

  const bad = await fetch(BASE + '/api/subscription/stripe', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Stripe-Signature': 't=1,v1=deadbeef' },
    body: raw,
  });
  assert.equal(bad.status, 400);

  const ok = await fetch(BASE + '/api/subscription/stripe', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Stripe-Signature': stripe.signWebhookPayload(raw, WHSEC),
    },
    body: raw,
  });
  assert.equal(ok.status, 200);
  const applied = await ok.json();
  assert.equal(applied.applied, true);
  assert.equal(applied.status, 'active');

  const after = await ada('GET', '/api/subscription/status');
  assert.equal(after.body.premium, true);
  assert.equal(after.body.tier, 'lite');
  assert.equal(after.body.source, 'stripe');
  assert.equal(after.body.stripe_managed, true);
  assert.equal(after.body.chats_per_day, 10);

  const again = await fetch(BASE + '/api/subscription/stripe', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Stripe-Signature': stripe.signWebhookPayload(raw, WHSEC),
    },
    body: raw,
  });
  assert.equal(again.status, 200);
  const dup = await again.json();
  assert.equal(dup.duplicate, true);
});

test('applyStripeSubscription refuses an unbound event and maps cancellation', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fl-stripe-unit-'));
  process.env.FAMILY_DB_DIR = dir;
  delete require.cache[require.resolve('../database.js')];
  const FamilyDB = require('../database.js');
  const db = new FamilyDB();
  await db.initSchema();
  await new Promise(r => setTimeout(r, 400));

  const unbound = await subscription.applyStripeSubscription(db, {
    id: 'sub_unbound',
    status: 'active',
    livemode: false,
    current_period_end: Math.floor(Date.now() / 1000) + 86400,
    metadata: {},
    items: { data: [{ price: { lookup_key: 'com.kinrows.app.concierge.premium.monthly' } }] },
  });
  assert.equal(unbound.applied, false);
  assert.equal(unbound.reason, 'unbound');

  const u = await new Promise((resolve, reject) => {
    db.db.run("INSERT INTO users (username, name, password_hash) VALUES ('c_t', 'C', 'x')", function (err) {
      err ? reject(err) : resolve(this.lastID);
    });
  });
  const g = await new Promise((resolve, reject) => {
    db.db.run("INSERT INTO groups (name, group_type, invite_code, created_by) VALUES ('G', 'household', 'STRIPE1', ?)", [u], function (err) {
      err ? reject(err) : resolve(this.lastID);
    });
  });
  await new Promise((resolve, reject) => {
    db.db.run('INSERT INTO group_members (group_id, user_id, role) VALUES (?, ?, ?)', [g, u, 'admin'], (err) => err ? reject(err) : resolve());
  });

  const granted = await subscription.applyStripeSubscription(db, fakeSub({
    groupId: g, userId: u, productId: 'com.kinrows.app.concierge.premium.yearly',
  }));
  assert.equal(granted.applied, true);
  const entitled = await subscription.getStatus(db, u);
  assert.equal(entitled.premium, true);
  assert.equal(entitled.tier, 'premium');

  const canceled = fakeSub({
    groupId: g, userId: u, productId: 'com.kinrows.app.concierge.premium.yearly', status: 'canceled',
  });
  canceled.id = granted.originalTransactionId.replace('stripe:', '');
  const revoked = await subscription.applyStripeSubscription(db, canceled);
  assert.equal(revoked.status, 'expired');
  const after = await subscription.getStatus(db, u);
  assert.equal(after.premium, false);

  db.close();
  fs.rmSync(dir, { recursive: true, force: true });
});

test('active household picks premium over a later-expiring lite row', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fl-stripe-tier-'));
  process.env.FAMILY_DB_DIR = dir;
  delete require.cache[require.resolve('../database.js')];
  const FamilyDB = require('../database.js');
  const db = new FamilyDB();
  await db.initSchema();
  await new Promise(r => setTimeout(r, 400));

  const u = await new Promise((resolve, reject) => {
    db.db.run("INSERT INTO users (username, name, password_hash) VALUES ('c_tier', 'T', 'x')", function (err) {
      err ? reject(err) : resolve(this.lastID);
    });
  });
  const g = await new Promise((resolve, reject) => {
    db.db.run("INSERT INTO groups (name, group_type, invite_code, created_by) VALUES ('G', 'household', 'TIEROK1', ?)", [u], function (err) {
      err ? reject(err) : resolve(this.lastID);
    });
  });
  await new Promise((resolve, reject) => {
    db.db.run('INSERT INTO group_members (group_id, user_id, role) VALUES (?, ?, ?)', [g, u, 'admin'], (err) => err ? reject(err) : resolve());
  });

  const far = new Date(Date.now() + 90 * 24 * 3600 * 1000).toISOString().slice(0, 19).replace('T', ' ');
  const near = new Date(Date.now() + 10 * 24 * 3600 * 1000).toISOString().slice(0, 19).replace('T', ' ');
  await db.upsertSubscription({
    group_id: g, user_id: u,
    product_id: 'com.kinrows.app.concierge.lite.yearly',
    original_transaction_id: 'stripe:sub_lite_later',
    expires_at: far, environment: 'StripeTest', status: 'active',
  });
  await db.upsertSubscription({
    group_id: g, user_id: u,
    product_id: 'com.kinrows.app.concierge.premium.monthly',
    original_transaction_id: 'stripe:sub_prem_sooner',
    expires_at: near, environment: 'StripeTest', status: 'active',
  });

  const status = await subscription.getStatus(db, u);
  assert.equal(status.tier, 'premium');
  assert.equal(status.chats_per_day, 40);

  db.close();
  fs.rmSync(dir, { recursive: true, force: true });
});

test('Checkout Session payload includes conversion fields and session_id success url', () => {
  const params = stripe.buildCheckoutParams({
    price: 'price_lite_m',
    productId: 'com.kinrows.app.concierge.lite.monthly',
    userId: 9,
    groupId: 4,
    customerEmail: 'ada@example.com',
    successUrl: 'https://kinrows.com/subscribe.html?success=1&session_id={CHECKOUT_SESSION_ID}',
    cancelUrl: 'https://kinrows.com/subscribe.html?canceled=1',
  });
  assert.equal(params.mode, 'subscription');
  assert.equal(params.allow_promotion_codes, true);
  assert.equal(params.locale, 'auto');
  assert.equal(params.billing_address_collection, 'required');
  assert.equal(params.adaptive_pricing.enabled, true);
  assert.equal(params.currency, undefined);
  assert.equal(params.excluded_payment_method_types, undefined);
  assert.equal(params.payment_method_types, undefined);
  assert.equal(params.customer_email, 'ada@example.com');
  assert.match(params.success_url, /session_id=\{CHECKOUT_SESSION_ID\}/);
  assert.match(params.custom_text.submit.message, /household/);
  assert.equal(params.line_items[0].price, 'price_lite_m');
  assert.equal(params.subscription_data.metadata.kinrows_group_id, '4');
  assert.equal(params.managed_payments.enabled, false);

  const cad = stripe.buildCheckoutParams({
    price: 'price_lite_m',
    productId: 'com.kinrows.app.concierge.lite.monthly',
    userId: 9,
    groupId: 4,
    successUrl: 'https://kinrows.com/subscribe.html?success=1',
    cancelUrl: 'https://kinrows.com/subscribe.html?canceled=1',
    currency: 'cad',
  });
  assert.equal(cad.currency, 'cad');
  const gbp = stripe.buildCheckoutParams({
    price: 'price_lite_m',
    productId: 'com.kinrows.app.concierge.lite.monthly',
    userId: 9,
    groupId: 4,
    successUrl: 'https://kinrows.com/subscribe.html?success=1',
    cancelUrl: 'https://kinrows.com/subscribe.html?canceled=1',
    currency: 'gbp',
  });
  assert.equal(gbp.currency, undefined);
});
