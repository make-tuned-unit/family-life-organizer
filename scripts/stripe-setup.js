#!/usr/bin/env node
// Idempotent Stripe catalog bootstrap for Kinrows Concierge.
// Creates two Products (Lite, Premium) each with monthly + yearly Prices,
// using the StoreKit product id as the Price lookup_key so checkout can
// resolve them without hard-coding price ids.
//
// Usage: STRIPE_SECRET_KEY=sk_test_… node scripts/stripe-setup.js
// Writes/updates local .env (gitignored) with keys + price ids + webhook secret.

const fs = require('fs');
const path = require('path');
const stripe = require('../services/stripe');

(function loadDotEnv() {
  const envPath = path.join(__dirname, '..', '.env');
  let text;
  try { text = fs.readFileSync(envPath, 'utf8'); } catch { return; }
  for (const raw of text.split('\n')) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const eq = line.indexOf('=');
    if (eq < 1) continue;
    const key = line.slice(0, eq).trim();
    if (!/^[A-Z_][A-Z0-9_]*$/.test(key) || process.env[key] != null) continue;
    let val = line.slice(eq + 1).trim();
    if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
      val = val.slice(1, -1);
    }
    process.env[key] = val;
  }
})();

const CATALOG = [
  {
    name: 'Kinrows Concierge Lite',
    description: 'AI Concierge for your household — up to 10 chats a day. One subscription covers everyone at home.',
    tier: 'lite',
    prices: [
      { productId: 'com.kinrows.app.concierge.lite.monthly', unit_amount: 499, interval: 'month' },
      { productId: 'com.kinrows.app.concierge.lite.yearly', unit_amount: 4999, interval: 'year' },
    ],
  },
  {
    name: 'Kinrows Concierge Premium',
    description: 'AI Concierge for your household — up to 40 chats a day. One subscription covers everyone at home.',
    tier: 'premium',
    prices: [
      { productId: 'com.kinrows.app.concierge.premium.monthly', unit_amount: 999, interval: 'month' },
      { productId: 'com.kinrows.app.concierge.premium.yearly', unit_amount: 9999, interval: 'year' },
    ],
  },
];

const WEBHOOK_URL = (process.env.APP_API_URL || 'https://family-life-organizer-production.up.railway.app')
  .replace(/\/$/, '') + '/api/subscription/stripe';
const WEBHOOK_EVENTS = [
  'checkout.session.completed',
  'checkout.session.async_payment_succeeded',
  'customer.subscription.updated',
  'customer.subscription.deleted',
  'invoice.paid',
  'invoice.payment_failed',
];

function upsertEnv(filePath, updates) {
  let text = '';
  try { text = fs.readFileSync(filePath, 'utf8'); } catch { /* new file */ }
  const keys = new Set();
  const lines = text ? text.split('\n') : [];
  const out = lines.map((line) => {
    const m = line.match(/^([A-Z_][A-Z0-9_]*)=/);
    if (!m || !(m[1] in updates)) return line;
    keys.add(m[1]);
    return `${m[1]}=${updates[m[1]]}`;
  });
  for (const [k, v] of Object.entries(updates)) {
    if (!keys.has(k)) out.push(`${k}=${v}`);
  }
  const body = out.join('\n').replace(/\n*$/, '\n');
  fs.writeFileSync(filePath, body, { mode: 0o600 });
}

async function findProductByName(name) {
  const list = await stripe.stripeRequest('GET', '/products', { active: true, limit: 100 });
  return (list.data || []).find((p) => p.name === name) || null;
}

async function ensureProduct(spec) {
  let product = await findProductByName(spec.name);
  if (!product) {
    product = await stripe.stripeRequest('POST', '/products', {
      name: spec.name,
      description: spec.description,
      tax_code: 'txcd_10103001',
      metadata: { kinrows_tier: spec.tier },
    });
    console.log(`created product ${spec.name} (${product.id})`);
  } else {
    console.log(`reusing product ${spec.name} (${product.id})`);
    if (product.tax_code !== 'txcd_10103001') {
      await stripe.stripeRequest('POST', `/products/${product.id}`, { tax_code: 'txcd_10103001' });
      console.log(`  set tax_code txcd_10103001 on ${spec.name}`);
    }
  }
  const priceIds = {};
  for (const p of spec.prices) {
    const found = await stripe.stripeRequest('GET', '/prices', {
      'lookup_keys[0]': p.productId,
      limit: 1,
    });
    let price = found.data?.[0];
    if (!price) {
      price = await stripe.stripeRequest('POST', '/prices', {
        product: product.id,
        currency: 'usd',
        unit_amount: p.unit_amount,
        currency_options: stripe.currencyOptionsForAmount(p.unit_amount),
        recurring: { interval: p.interval },
        lookup_key: p.productId,
        nickname: `${spec.tier} ${p.interval}ly`,
        metadata: { kinrows_product_id: p.productId, kinrows_tier: spec.tier },
      });
      console.log(`  created price ${p.productId} (${price.id})`);
    } else {
      console.log(`  reusing price ${p.productId} (${price.id})`);
      try {
        await stripe.stripeRequest('POST', `/prices/${price.id}`, {
          currency_options: stripe.currencyOptionsForAmount(p.unit_amount),
        });
        console.log(`  set CAD/EUR presentment on ${p.productId}`);
      } catch (err) {
        console.error(`  currency_options skipped for ${p.productId}:`, err.message);
      }
    }
    priceIds[p.productId] = price.id;
  }
  return priceIds;
}

function applePayDomains() {
  const hosts = new Set(['kinrows.com', 'www.kinrows.com']);
  try {
    const u = new URL((process.env.SITE_URL || 'https://kinrows.com').replace(/\/$/, ''));
    if (u.hostname && u.hostname !== 'localhost') hosts.add(u.hostname);
  } catch { /* ignore */ }
  return [...hosts];
}

async function ensurePaymentMethodDomains() {
  const hosts = applePayDomains();
  let existing = [];
  try {
    const list = await stripe.stripeRequest('GET', '/payment_method_domains', { limit: 100 });
    existing = list.data || [];
  } catch (err) {
    console.error('payment method domains list skipped:', err.message);
    return;
  }
  const have = new Set(existing.map((d) => d.domain_name));
  for (const domain_name of hosts) {
    const row = existing.find((d) => d.domain_name === domain_name);
    if (have.has(domain_name) && row) {
      console.log(`reusing payment method domain ${row.id} (${domain_name}) apple_pay=${row.apple_pay?.status || '?'}`);
      continue;
    }
    try {
      const created = await stripe.stripeRequest('POST', '/payment_method_domains', { domain_name });
      console.log(`registered payment method domain ${created.id} (${domain_name}) apple_pay=${created.apple_pay?.status || '?'}`);
    } catch (err) {
      console.error(`payment method domain ${domain_name} skipped:`, err.message);
    }
  }
}

async function ensureWebhook() {
  const list = await stripe.stripeRequest('GET', '/webhook_endpoints', { limit: 100 });
  const existing = (list.data || []).find((w) => w.url === WEBHOOK_URL && w.status === 'enabled');
  if (existing) {
    console.log(`reusing webhook endpoint ${existing.id} → ${WEBHOOK_URL}`);
    console.log('(secret is only returned on create — leaving STRIPE_WEBHOOK_SECRET unchanged if already set)');
    return existing.secret || null;
  }
  const created = await stripe.stripeRequest('POST', '/webhook_endpoints', {
    url: WEBHOOK_URL,
    enabled_events: WEBHOOK_EVENTS,
    description: 'Kinrows Concierge household entitlements',
  });
  console.log(`created webhook endpoint ${created.id} → ${WEBHOOK_URL}`);
  return created.secret || null;
}

async function main() {
  if (!process.env.STRIPE_SECRET_KEY) {
    console.error('STRIPE_SECRET_KEY is required');
    process.exit(1);
  }
  const priceIds = {};
  for (const spec of CATALOG) Object.assign(priceIds, await ensureProduct(spec));
  try {
    await ensurePaymentMethodDomains();
  } catch (err) {
    console.error('Apple Pay domain registration skipped:', err.message);
  }
  let webhookSecret = null;
  try {
    webhookSecret = await ensureWebhook();
  } catch (err) {
    console.error('webhook setup skipped:', err.message);
  }

  const envPath = path.join(__dirname, '..', '.env');
  const updates = {
    STRIPE_SECRET_KEY: process.env.STRIPE_SECRET_KEY,
    STRIPE_PRICE_LITE_MONTHLY: priceIds['com.kinrows.app.concierge.lite.monthly'] || '',
    STRIPE_PRICE_LITE_YEARLY: priceIds['com.kinrows.app.concierge.lite.yearly'] || '',
    STRIPE_PRICE_PREMIUM_MONTHLY: priceIds['com.kinrows.app.concierge.premium.monthly'] || '',
    STRIPE_PRICE_PREMIUM_YEARLY: priceIds['com.kinrows.app.concierge.premium.yearly'] || '',
  };
  if (process.env.STRIPE_PUBLISHABLE_KEY) {
    updates.STRIPE_PUBLISHABLE_KEY = process.env.STRIPE_PUBLISHABLE_KEY;
  }
  if (webhookSecret) updates.STRIPE_WEBHOOK_SECRET = webhookSecret;
  upsertEnv(envPath, updates);
  console.log('updated .env (gitignored) with Stripe keys and price ids');
  console.log('catalog ready:');
  for (const [k, v] of Object.entries(priceIds)) console.log(`  ${k} → ${v}`);
}

main().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
