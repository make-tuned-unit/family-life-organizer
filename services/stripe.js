// Stripe Billing for the Concierge web-subscription flow.
// Talks to the Stripe API over HTTPS (no SDK) so we don't add a dependency.
// Entitlements land in the same `subscriptions` table StoreKit uses.

const crypto = require('crypto');

const API = 'https://api.stripe.com/v1';
const STRIPE_VERSION = '2026-07-29.dahlia';
const TXN_PREFIX = 'stripe:';

const PRICE_ENV = {
  'com.kinrows.app.concierge.lite.monthly':    'STRIPE_PRICE_LITE_MONTHLY',
  'com.kinrows.app.concierge.lite.yearly':     'STRIPE_PRICE_LITE_YEARLY',
  'com.kinrows.app.concierge.premium.monthly': 'STRIPE_PRICE_PREMIUM_MONTHLY',
  'com.kinrows.app.concierge.premium.yearly':  'STRIPE_PRICE_PREMIUM_YEARLY',
};

function isConfigured() {
  return !!process.env.STRIPE_SECRET_KEY;
}

function txnId(stripeSubscriptionId) {
  return `${TXN_PREFIX}${stripeSubscriptionId}`;
}

function isStripeTxn(originalTransactionId) {
  return String(originalTransactionId || '').startsWith(TXN_PREFIX);
}

function stripeSubscriptionIdFromTxn(originalTransactionId) {
  const s = String(originalTransactionId || '');
  return isStripeTxn(s) ? s.slice(TXN_PREFIX.length) : null;
}

function flatten(obj, prefix, out) {
  for (const [k, v] of Object.entries(obj)) {
    const key = prefix ? `${prefix}[${k}]` : k;
    if (v == null) continue;
    if (Array.isArray(v)) {
      v.forEach((item, i) => {
        if (item && typeof item === 'object') flatten(item, `${key}[${i}]`, out);
        else out.push([`${key}[${i}]`, String(item)]);
      });
    } else if (typeof v === 'object') {
      flatten(v, key, out);
    } else if (typeof v === 'boolean') {
      out.push([key, v ? 'true' : 'false']);
    } else {
      out.push([key, String(v)]);
    }
  }
  return out;
}

async function stripeRequest(method, path, params) {
  const key = process.env.STRIPE_SECRET_KEY;
  if (!key) throw new Error('STRIPE_SECRET_KEY is not set');
  const url = path.startsWith('http') ? path : `${API}${path}`;
  const headers = {
    Authorization: `Bearer ${key}`,
    'Stripe-Version': STRIPE_VERSION,
  };
  let body;
  if (method !== 'GET' && params) {
    headers['Content-Type'] = 'application/x-www-form-urlencoded';
    body = flatten(params, '', []).map(([k, v]) =>
      `${encodeURIComponent(k)}=${encodeURIComponent(v)}`).join('&');
  }
  const getUrl = method === 'GET' && params
    ? `${url}?${flatten(params, '', []).map(([k, v]) =>
        `${encodeURIComponent(k)}=${encodeURIComponent(v)}`).join('&')}`
    : url;
  const res = await fetch(method === 'GET' ? getUrl : url, { method, headers, body });
  const data = await res.json();
  if (!res.ok) {
    const msg = data?.error?.message || `Stripe ${method} ${path} failed (${res.status})`;
    const err = new Error(msg);
    err.status = res.status;
    err.stripe = data?.error || null;
    throw err;
  }
  return data;
}

// Resolve a Kinrows product id to a Stripe Price id: env override, then lookup_key.
async function priceIdForProduct(productId) {
  if (!PRICE_ENV[productId]) return null;
  const fromEnv = process.env[PRICE_ENV[productId]];
  if (fromEnv) return fromEnv;
  const list = await stripeRequest('GET', '/prices', {
    'lookup_keys[0]': productId,
    active: true,
    limit: 1,
  });
  return list.data?.[0]?.id || null;
}

async function productIdForPrice(price) {
  if (!price) return null;
  if (price.lookup_key && PRICE_ENV[price.lookup_key]) return price.lookup_key;
  if (price.metadata?.kinrows_product_id && PRICE_ENV[price.metadata.kinrows_product_id]) {
    return price.metadata.kinrows_product_id;
  }
  if (typeof price === 'string') {
    const p = await stripeRequest('GET', `/prices/${price}`);
    return productIdForPrice(p);
  }
  return null;
}

function periodEndUnix(sub) {
  const n = Number(sub?.current_period_end || sub?.items?.data?.[0]?.current_period_end || 0);
  return n > 0 ? n : null;
}

function statusFromStripe(sub) {
  const s = sub?.status;
  if (s === 'canceled' || s === 'unpaid' || s === 'incomplete_expired') return 'expired';
  if (s === 'incomplete') return 'expired';
  // active / trialing / past_due (dunning) stay entitled until Stripe gives up.
  return 'active';
}

function environmentFromLivemode(livemode) {
  return livemode ? 'Stripe' : 'StripeTest';
}

function allowTestStripe() {
  return process.env.STRIPE_ALLOW_TEST === '1' || process.env.NODE_ENV !== 'production';
}

function randomSuffix(n = 8) {
  const letters = 'abcdefghijklmnopqrstuvwxyz';
  let s = '';
  for (const b of crypto.randomBytes(n)) s += letters[b % 26];
  return s;
}

async function createCheckoutSession({
  productId, userId, groupId, customerId, customerEmail, successUrl, cancelUrl,
}) {
  const price = await priceIdForProduct(productId);
  if (!price) throw Object.assign(new Error('Unknown or unpriced product'), { status: 400 });
  const meta = {
    kinrows_user_id: String(userId),
    kinrows_group_id: String(groupId),
    kinrows_product_id: productId,
  };
  const params = {
    mode: 'subscription',
    line_items: [{ price, quantity: 1 }],
    success_url: successUrl,
    cancel_url: cancelUrl,
    client_reference_id: String(groupId),
    metadata: meta,
    subscription_data: { metadata: meta },
    allow_promotion_codes: true,
    billing_address_collection: 'auto',
    integration_identifier: `kinrowsweb${randomSuffix()}`,
    // This account has Managed Payments on by default, which requires a product
    // tax_code + tax registration. Keep Checkout working until Stripe Tax is
    // actually registered; flip this on then (and set automatic_tax).
    managed_payments: { enabled: false },
  };
  if (customerId) params.customer = customerId;
  else if (customerEmail) params.customer_email = customerEmail;
  return stripeRequest('POST', '/checkout/sessions', params);
}

async function createPortalSession({ customerId, returnUrl }) {
  return stripeRequest('POST', '/billing_portal/sessions', {
    customer: customerId,
    return_url: returnUrl,
  });
}

async function retrieveSubscription(id) {
  return stripeRequest('GET', `/subscriptions/${id}`);
}

function parseStripeSignatureHeader(header) {
  const out = { t: null, v1: [] };
  if (!header) return out;
  for (const part of String(header).split(',')) {
    const i = part.indexOf('=');
    if (i < 0) continue;
    const k = part.slice(0, i).trim();
    const v = part.slice(i + 1).trim();
    if (k === 't') out.t = v;
    else if (k === 'v1') out.v1.push(v);
  }
  return out;
}

// Constant-time compare of Stripe's v1 HMAC against the signed payload.
function verifyWebhookSignature(rawBody, sigHeader, secret, nowMs = Date.now()) {
  if (!secret || rawBody == null || !sigHeader) return false;
  const { t, v1 } = parseStripeSignatureHeader(sigHeader);
  if (!t || !v1.length) return false;
  const ts = Number(t);
  if (!Number.isFinite(ts)) return false;
  if (Math.abs(nowMs / 1000 - ts) > 300) return false; // 5-minute tolerance
  const payload = Buffer.isBuffer(rawBody) ? rawBody.toString('utf8') : String(rawBody);
  const expected = crypto.createHmac('sha256', secret).update(`${t}.${payload}`).digest('hex');
  const expectedBuf = Buffer.from(expected, 'hex');
  for (const sig of v1) {
    try {
      const got = Buffer.from(sig, 'hex');
      if (got.length === expectedBuf.length && crypto.timingSafeEqual(got, expectedBuf)) return true;
    } catch { /* malformed hex */ }
  }
  return false;
}

function signWebhookPayload(rawBody, secret, ts = Math.floor(Date.now() / 1000)) {
  const payload = Buffer.isBuffer(rawBody) ? rawBody.toString('utf8') : String(rawBody);
  const v1 = crypto.createHmac('sha256', secret).update(`${ts}.${payload}`).digest('hex');
  return `t=${ts},v1=${v1}`;
}

module.exports = {
  API,
  STRIPE_VERSION,
  TXN_PREFIX,
  PRICE_ENV,
  isConfigured,
  txnId,
  isStripeTxn,
  stripeSubscriptionIdFromTxn,
  stripeRequest,
  priceIdForProduct,
  productIdForPrice,
  periodEndUnix,
  statusFromStripe,
  environmentFromLivemode,
  allowTestStripe,
  createCheckoutSession,
  createPortalSession,
  retrieveSubscription,
  verifyWebhookSignature,
  signWebhookPayload,
};
