// Concierge premium subscriptions.
// Entitlement is resolved per HOUSEHOLD: any active subscription attached to a
// user's household group unlocks premium for everyone in that group.

const { verifyTransaction } = require('./appleVerify');
const stripe = require('./stripe');

const BUNDLE_ID = process.env.APNS_BUNDLE_ID || 'com.kinrows.app';

// Concierge product catalog. Two tiers (lite/premium) × two billing periods.
// Tier drives the daily chat allowance (see dashboard TIER_DAILY_CAP); both tiers
// get the free daily brief and the full feature set — they differ only by volume.
// The legacy single-tier product maps to premium so existing subs don't regress.
const PRODUCTS = {
  'com.kinrows.app.concierge.lite.monthly':    { tier: 'lite',    period: 'monthly' },
  'com.kinrows.app.concierge.lite.yearly':     { tier: 'lite',    period: 'yearly'  },
  'com.kinrows.app.concierge.premium.monthly': { tier: 'premium', period: 'monthly' },
  'com.kinrows.app.concierge.premium.yearly':  { tier: 'premium', period: 'yearly'  },
  // Sold under the previous bundle ID (com.mylauft.kinrows). Nothing new can
  // arrive on these, but a transaction from before the move must still resolve
  // to its tier — Apple sends whatever product ID was actually purchased, and
  // dropping these would silently downgrade a paying household. The last is the
  // pre-tier single product, which has always mapped to premium.
  'com.mylauft.kinrows.concierge.lite.monthly':    { tier: 'lite',    period: 'monthly' },
  'com.mylauft.kinrows.concierge.lite.yearly':     { tier: 'lite',    period: 'yearly'  },
  'com.mylauft.kinrows.concierge.premium.monthly': { tier: 'premium', period: 'monthly' },
  'com.mylauft.kinrows.concierge.premium.yearly':  { tier: 'premium', period: 'yearly'  },
  'com.mylauft.kinrows.concierge.monthly':         { tier: 'premium', period: 'monthly' },
};
// Display catalog for the website paywall (USD). Yearly = two months free.
const CATALOG = [
  { product_id: 'com.kinrows.app.concierge.lite.monthly',    tier: 'lite',    period: 'monthly', amount_cents: 499,  chats: 10 },
  { product_id: 'com.kinrows.app.concierge.lite.yearly',     tier: 'lite',    period: 'yearly',  amount_cents: 4999, chats: 10 },
  { product_id: 'com.kinrows.app.concierge.premium.monthly', tier: 'premium', period: 'monthly', amount_cents: 999,  chats: 40 },
  { product_id: 'com.kinrows.app.concierge.premium.yearly',  tier: 'premium', period: 'yearly',  amount_cents: 9999, chats: 40 },
];

// Daily concierge-chat allowance per household. Lite and Premium share every
// feature; they differ only by this cap (enforced in dashboard.js).
const TIER_DAILY_CAP = { lite: 10, premium: 40 };

function chatsForTier(tier) {
  return TIER_DAILY_CAP[tier] || 0;
}

function chatsForProduct(productId) {
  const row = CATALOG.find((p) => p.product_id === productId);
  if (row) return row.chats;
  return chatsForTier(tierForProduct(productId));
}

// Product used for comped (non-billed) entitlements — grants the premium tier.
const COMP_PRODUCT_ID = 'com.kinrows.app.concierge.premium.monthly';
// Back-compat export for any caller still referencing a single product id.
const PRODUCT_ID = process.env.CONCIERGE_PRODUCT_ID || COMP_PRODUCT_ID;

function tierForProduct(productId) {
  return PRODUCTS[productId] ? PRODUCTS[productId].tier : null;
}

// Convert StoreKit epoch-ms to SQLite CURRENT_TIMESTAMP-comparable UTC string.
function toSqlDate(ms) {
  const n = Number(ms);
  if (!ms || Number.isNaN(n)) return null;
  return new Date(n).toISOString().replace('T', ' ').slice(0, 19);
}

// Verify a signed transaction from the client and store the entitlement
// against the user's household. Returns the resulting status.
async function verifyAndStore(db, userId, signedTransaction) {
  const payload = verifyTransaction(signedTransaction, { bundleId: BUNDLE_ID });

  // Only a known concierge product grants entitlement — never any other IAP.
  if (!PRODUCTS[payload.productId]) {
    throw new Error(`Unexpected product: ${payload.productId}`);
  }

  // A Sandbox-signed transaction is free to mint and must not unlock entitlement
  // on the production server. Sandbox is accepted only when explicitly enabled
  // (dev / TestFlight builds set STOREKIT_ALLOW_SANDBOX=1); production rejects it.
  const allowSandbox = process.env.STOREKIT_ALLOW_SANDBOX === '1' || process.env.NODE_ENV !== 'production';
  if (payload.environment && payload.environment !== 'Production' && !allowSandbox) {
    throw new Error(`Refusing ${payload.environment} transaction on production`);
  }

  // Entitlement is per-household; an ungrouped user can't unlock a shared tier.
  const groupId = await db.getUserHouseholdId(userId);
  if (!groupId) throw new Error('User must belong to a household to subscribe');

  // Refunded/revoked transactions must not grant access.
  const status = payload.revocationDate ? 'revoked' : 'active';

  await db.upsertSubscription({
    group_id: groupId,
    user_id: userId,
    product_id: payload.productId,
    original_transaction_id: String(payload.originalTransactionId),
    expires_at: toSqlDate(payload.expiresDate),
    environment: payload.environment,
    status,
  });

  return getStatus(db, userId);
}

// Comp ("on the house") premium — a non-billed entitlement we grant the family
// directly, no App Store transaction involved. Keyed to a sentinel transaction
// id per household so it's idempotent and untouched by Apple notifications.
const COMP_TXN_PREFIX = 'comp-group-';
const COMP_EXPIRES = '2099-12-31 23:59:59';

async function grantCompForGroup(db, groupId, userId) {
  if (!groupId) return false;
  await db.upsertSubscription({
    group_id: groupId,
    user_id: userId,
    product_id: PRODUCT_ID,
    original_transaction_id: `${COMP_TXN_PREFIX}${groupId}`,
    expires_at: COMP_EXPIRES,
    environment: 'Comp',
    status: 'active',
  });
  return true;
}

// Revoke a previously-granted comp entitlement for a household.
async function revokeCompForGroup(db, groupId) {
  if (!groupId) return false;
  await db.updateSubscriptionStatus(`${COMP_TXN_PREFIX}${groupId}`, 'revoked', null);
  return true;
}

// Boot-time seeder. Set COMP_PREMIUM_ALL=1 to comp every household, or
// COMP_PREMIUM_USERNAMES="jesse,sophie,ariel" to comp specific people's
// households. Safe no-op when neither is set. Idempotent.
async function ensureCompPremium(db) {
  if (process.env.COMP_PREMIUM_ALL === '1') {
    const groups = await db.getHouseholdGroupsWithMember();
    for (const g of groups) {
      await grantCompForGroup(db, g.group_id, g.user_id);
      console.log(`[comp] premium → household ${g.group_id}`);
    }
    return;
  }
  const raw = process.env.COMP_PREMIUM_USERNAMES;
  if (!raw) return;
  const names = raw.split(',').map(s => s.trim()).filter(Boolean);
  const seen = new Set();
  for (const name of names) {
    const user = await db.getUserByUsername(name);
    if (!user) { console.log(`[comp] no user "${name}" — skipped`); continue; }
    const groupId = await db.getUserHouseholdId(user.id);
    if (!groupId) { console.log(`[comp] "${name}" has no household — skipped`); continue; }
    if (seen.has(groupId)) continue;
    seen.add(groupId);
    await grantCompForGroup(db, groupId, user.id);
    console.log(`[comp] premium → household ${groupId} (via ${name})`);
  }
}

// Whether the user's household currently has ANY paid tier (lite or premium).
async function isHouseholdPremium(db, userId) {
  const groupId = await db.getUserHouseholdId(userId);
  const sub = await db.getActiveSubscriptionForGroup(groupId);
  return !!sub;
}

// The household's active tier ('premium' | 'lite' | null). Drives the chat cap.
async function getHouseholdTier(db, userId) {
  const groupId = await db.getUserHouseholdId(userId);
  const sub = await db.getActiveSubscriptionForGroup(groupId);
  return sub ? tierForProduct(sub.product_id) : null;
}

// Handle an App Store Server Notification (v2): verify Apple's signed payload,
// then make the subscription status server-authoritative (renewals, refunds,
// revocations, expirations) by original_transaction_id.
async function verifyAndApplyNotification(db, signedPayload) {
  const payload = verifyTransaction(signedPayload); // authenticate the notification
  const data = payload.data || {};
  if (data.bundleId && data.bundleId !== BUNDLE_ID) {
    throw new Error('Notification bundle id does not match');
  }
  if (!data.signedTransactionInfo) return { applied: false };

  const txn = verifyTransaction(data.signedTransactionInfo, { bundleId: BUNDLE_ID });
  const type = payload.notificationType;

  // Drive status from the transaction's own fields (a refund/revoke carries a
  // revocationDate); treat REVOKE/EXPIRED as explicit signals.
  let status;
  if (type === 'REVOKE' || txn.revocationDate) {
    status = 'revoked';
  } else if (type === 'EXPIRED') {
    status = 'expired';
  } else {
    status = (txn.expiresDate && Number(txn.expiresDate) > Date.now()) ? 'active' : 'expired';
  }

  await db.updateSubscriptionStatus(txn.originalTransactionId, status, toSqlDate(txn.expiresDate));
  return { applied: true, type, status };
}

async function getStatus(db, userId) {
  const groupId = await db.getUserHouseholdId(userId);
  const sub = await db.getActiveSubscriptionForGroup(groupId);
  const stripeManaged = !!(sub && stripe.isStripeTxn(sub.original_transaction_id));
  const tier = sub ? tierForProduct(sub.product_id) : null;
  return {
    premium: !!sub,
    tier,
    product_id: sub ? sub.product_id : null,
    expires_at: sub ? sub.expires_at : null,
    source: sub ? (stripeManaged ? 'stripe' : (String(sub.environment || '').startsWith('Comp') ? 'comp' : 'apple')) : null,
    stripe_managed: stripeManaged,
    chats_per_day: sub ? chatsForProduct(sub.product_id) : 0,
  };
}

function toSqlDateFromUnix(seconds) {
  const n = Number(seconds);
  if (!n || Number.isNaN(n)) return null;
  return toSqlDate(n * 1000);
}

// Persist a Stripe Subscription onto the household entitlement row.
// `groupId`/`userId`/`productId` come from Checkout metadata (or an existing row).
async function applyStripeSubscription(db, stripeSub, extras = {}) {
  if (!stripeSub || !stripeSub.id) return { applied: false, reason: 'no_subscription' };
  if (stripeSub.livemode === false && !stripe.allowTestStripe()) {
    throw new Error('Refusing Stripe test-mode subscription on production');
  }

  const originalTransactionId = stripe.txnId(stripeSub.id);
  const existing = await db.getSubscriptionByOriginalTransactionId(originalTransactionId);

  const groupId = Number(stripeSub.metadata?.kinrows_group_id || extras.groupId || existing?.group_id);
  const userId = Number(stripeSub.metadata?.kinrows_user_id || extras.userId || existing?.user_id);
  if (!Number.isInteger(groupId) || groupId <= 0 || !Number.isInteger(userId) || userId <= 0) {
    return { applied: false, reason: 'unbound' };
  }

  const price = stripeSub.items?.data?.[0]?.price;
  const productId = await stripe.productIdForPrice(price)
    || extras.productId
    || stripeSub.metadata?.kinrows_product_id
    || existing?.product_id;
  if (!PRODUCTS[productId]) {
    return { applied: false, reason: 'unknown_product' };
  }

  const status = stripe.statusFromStripe(stripeSub);
  const expiresAt = toSqlDateFromUnix(stripe.periodEndUnix(stripeSub))
    || (status === 'active' ? toSqlDate(Date.now() + 35 * 24 * 60 * 60 * 1000) : existing?.expires_at);

  await db.upsertSubscription({
    group_id: groupId,
    user_id: userId,
    product_id: productId,
    original_transaction_id: originalTransactionId,
    expires_at: expiresAt,
    environment: stripe.environmentFromLivemode(stripeSub.livemode),
    status,
  });

  return {
    applied: true,
    status,
    groupId,
    userId,
    productId,
    originalTransactionId,
    tier: tierForProduct(productId),
    expiresAt,
  };
}

async function applyStripeEvent(db, event) {
  const type = event?.type;
  const obj = event?.data?.object;
  if (!type || !obj) return { applied: false, reason: 'malformed' };

  if (type === 'checkout.session.completed' || type === 'checkout.session.async_payment_succeeded') {
    if (obj.mode && obj.mode !== 'subscription') return { applied: false, reason: 'not_subscription' };
    const subRef = obj.subscription;
    if (!subRef) return { applied: false, reason: 'no_subscription' };
    const stripeSub = typeof subRef === 'object' ? subRef : await stripe.retrieveSubscription(subRef);
    return applyStripeSubscription(db, stripeSub, {
      groupId: obj.client_reference_id || obj.metadata?.kinrows_group_id,
      userId: obj.metadata?.kinrows_user_id,
      productId: obj.metadata?.kinrows_product_id,
    });
  }

  if (type === 'customer.subscription.updated' || type === 'customer.subscription.deleted') {
    return applyStripeSubscription(db, obj);
  }

  if (type === 'invoice.paid' || type === 'invoice.payment_failed') {
    const subRef = obj.subscription || obj.parent?.subscription_details?.subscription;
    if (!subRef) return { applied: false, reason: 'no_subscription' };
    const stripeSub = typeof subRef === 'object' ? subRef : await stripe.retrieveSubscription(subRef);
    return applyStripeSubscription(db, stripeSub);
  }

  return { applied: false, reason: 'ignored' };
}

async function stripeCustomerIdForGroup(db, groupId) {
  const row = await db.getLatestStripeSubscriptionForGroup(groupId);
  if (!row) return null;
  const subId = stripe.stripeSubscriptionIdFromTxn(row.original_transaction_id);
  if (!subId) return null;
  const sub = await stripe.retrieveSubscription(subId);
  return typeof sub.customer === 'string' ? sub.customer : sub.customer?.id || null;
}

module.exports = {
  verifyAndStore, verifyAndApplyNotification, getStatus, isHouseholdPremium, getHouseholdTier,
  tierForProduct, grantCompForGroup, revokeCompForGroup, ensureCompPremium,
  applyStripeSubscription, applyStripeEvent, stripeCustomerIdForGroup,
  PRODUCTS, PRODUCT_ID, BUNDLE_ID, CATALOG, TIER_DAILY_CAP, chatsForTier, chatsForProduct,
};
