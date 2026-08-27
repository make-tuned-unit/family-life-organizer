/**
 * Permagent conversion events.
 *
 * Marketing pageviews already flow through POST /api/permagent-analytics/collect.
 * Money events (Checkout start/complete, invoices, cancel, StoreKit, app return)
 * must be written server-side — Safari Checkout and the iPhone app never run
 * analytics.js. Names are stable `sale_*` strings so the drain can build a funnel.
 *
 * Properties are flat scalars only (same caps as the collect endpoint). No email,
 * user id, household id, or Stripe customer id.
 */

const { PRODUCTS } = require('./subscription');
const stripe = require('./stripe');

const MAX_NAME = 128;
const MAX_PATH = 512;
const MAX_KEYS = 32;
const MAX_VAL = 256;
const MAX_PROPS_BYTES = 4096;

function isBotUserAgent(ua) {
  const s = String(ua || '').toLowerCase();
  return !s || /bot|crawler|spider|headless|curl|python-requests|facebookexternalhit/.test(s);
}

function flattenProperties(d) {
  if (!d || typeof d !== 'object' || Array.isArray(d)) return null;
  const flat = {};
  const keys = Object.keys(d);
  for (let i = 0; i < Math.min(keys.length, MAX_KEYS); i++) {
    const key = keys[i];
    const val = d[key];
    if (val === null || val === undefined) continue;
    if (typeof val === 'object') continue;
    if (typeof val === 'boolean' || typeof val === 'number') {
      if (typeof val === 'number' && !Number.isFinite(val)) continue;
      flat[key] = val;
    } else {
      const str = String(val).slice(0, MAX_VAL);
      if (str) flat[key] = str;
    }
  }
  const propStr = JSON.stringify(flat);
  if (propStr.length <= MAX_PROPS_BYTES) return Object.keys(flat).length ? flat : null;
  const truncated = {};
  let totalSize = 0;
  for (const [key, val] of Object.entries(flat)) {
    const valStr = JSON.stringify(val);
    if (totalSize + valStr.length + key.length + 4 > MAX_PROPS_BYTES) break;
    truncated[key] = val;
    totalSize += valStr.length + key.length + 4;
  }
  return Object.keys(truncated).length ? truncated : null;
}

function planBits(productId) {
  const spec = PRODUCTS[productId] || {};
  const out = {};
  if (productId) out.product_id = String(productId).slice(0, MAX_VAL);
  if (spec.tier) out.tier = spec.tier;
  if (spec.period) out.period = spec.period;
  return out;
}

function extrasFromReq(req) {
  if (!req || typeof req.get !== 'function') return { isBot: false };
  const country = req.get('cf-ipcountry') || req.get('x-vercel-ip-country')
    || req.get('cloudfront-viewer-country') || req.get('x-country-code') || null;
  return {
    isBot: isBotUserAgent(req.get('user-agent')),
    country: country ? String(country).slice(0, 8) : null,
  };
}

/**
 * Record one event. Never throws. Pass the request's FamilyDB when you have one;
 * otherwise this opens a short-lived connection.
 */
function track(db, { name, path, properties, sessionId, isBot, country } = {}) {
  const eventName = String(name || '').slice(0, MAX_NAME);
  if (!eventName) return Promise.resolve(null);
  const row = {
    kind: 'event',
    path: String(path || '/subscribe.html').slice(0, MAX_PATH),
    referrer: null,
    name: eventName,
    visitorHash: null,
    properties: flattenProperties(properties),
    isBot: !!isBot,
    sessionId: sessionId ? String(sessionId).slice(0, 64) : null,
    utmSource: null,
    utmMedium: null,
    utmCampaign: null,
    country: country ? String(country).slice(0, 8) : null,
  };
  const write = async (d) => d.recordAnalyticsEvent(row);
  if (db && typeof db.recordAnalyticsEvent === 'function') {
    return write(db).catch((err) => {
      console.error('[permagent]', err && err.message ? err.message : err);
      return null;
    });
  }
  let FamilyDB;
  try { FamilyDB = require('../database.js'); } catch {
    return Promise.resolve(null);
  }
  const own = new FamilyDB();
  return write(own).catch((err) => {
    console.error('[permagent]', err && err.message ? err.message : err);
    return null;
  }).finally(() => { try { own.close(); } catch { /* shared conn */ } });
}

function trackSale(db, name, properties, { path, req } = {}) {
  const extra = extrasFromReq(req);
  return track(db, {
    name,
    path: path || '/subscribe.html',
    properties,
    isBot: extra.isBot,
    country: extra.country,
  });
}

function amountCents(obj) {
  const n = Number(obj?.amount_total ?? obj?.amount_paid ?? obj?.amount_due);
  return Number.isFinite(n) ? n : undefined;
}

/**
 * Map a Stripe webhook (plus applyStripeEvent result) to one sale_* event.
 * Returns null when the event is not a conversion/billing signal.
 */
function stripeSaleEvent(event, result) {
  const type = event?.type;
  const obj = event?.data?.object || {};
  const productId = result?.productId || obj.metadata?.kinrows_product_id || null;
  const base = {
    ...planBits(productId),
    status: result?.status || undefined,
    livemode: obj.livemode === true,
    source: obj.metadata?.kinrows_source || undefined,
  };
  if (type === 'checkout.session.completed' || type === 'checkout.session.async_payment_succeeded') {
    return {
      name: 'sale_checkout_complete',
      path: '/api/subscription/stripe',
      properties: {
        ...base,
        source: obj.metadata?.kinrows_source || 'web',
        currency: obj.currency || undefined,
        amount_cents: amountCents(obj),
      },
    };
  }
  if (type === 'invoice.paid') {
    return {
      name: 'sale_invoice_paid',
      path: '/api/subscription/stripe',
      properties: {
        ...base,
        currency: obj.currency || undefined,
        amount_cents: amountCents(obj),
        billing_reason: obj.billing_reason || undefined,
      },
    };
  }
  if (type === 'invoice.payment_failed') {
    return {
      name: 'sale_payment_failed',
      path: '/api/subscription/stripe',
      properties: {
        ...base,
        currency: obj.currency || undefined,
        amount_cents: amountCents(obj),
        billing_reason: obj.billing_reason || undefined,
      },
    };
  }
  if (type === 'customer.subscription.deleted') {
    return {
      name: 'sale_subscription_canceled',
      path: '/api/subscription/stripe',
      properties: base,
    };
  }
  if (type === 'customer.subscription.updated') {
    const status = result?.status || stripe.statusFromStripe(obj);
    if (status === 'expired' || status === 'revoked') {
      return {
        name: 'sale_subscription_canceled',
        path: '/api/subscription/stripe',
        properties: { ...base, status },
      };
    }
    return {
      name: 'sale_subscription_updated',
      path: '/api/subscription/stripe',
      properties: { ...base, status },
    };
  }
  return null;
}

module.exports = {
  track,
  trackSale,
  stripeSaleEvent,
  planBits,
  flattenProperties,
  isBotUserAgent,
  extrasFromReq,
};
