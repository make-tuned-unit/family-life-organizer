// Concierge premium subscriptions.
// Entitlement is resolved per HOUSEHOLD: any active subscription attached to a
// user's household group unlocks premium for everyone in that group.

const { verifyTransaction } = require('./appleVerify');

const BUNDLE_ID = process.env.APNS_BUNDLE_ID || 'com.mylauft.kinrows';
const PRODUCT_ID = process.env.CONCIERGE_PRODUCT_ID || 'com.mylauft.kinrows.concierge.monthly';

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

  // Only our concierge product grants entitlement — never any other IAP.
  if (payload.productId !== PRODUCT_ID) {
    throw new Error(`Unexpected product: ${payload.productId}`);
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

// Whether the user's household currently has premium.
async function isHouseholdPremium(db, userId) {
  const groupId = await db.getUserHouseholdId(userId);
  const sub = await db.getActiveSubscriptionForGroup(groupId);
  return !!sub;
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
  return {
    premium: !!sub,
    product_id: sub ? sub.product_id : null,
    expires_at: sub ? sub.expires_at : null,
  };
}

module.exports = { verifyAndStore, verifyAndApplyNotification, getStatus, isHouseholdPremium, grantCompForGroup, revokeCompForGroup, ensureCompPremium, PRODUCT_ID, BUNDLE_ID };
