// Billing confirmation emails for Stripe events (no live Resend).

const { test } = require('node:test');
const assert = require('node:assert');
const billing = require('../services/billingEmail');
const subscription = require('../services/subscription');

test('started / failed / canceled templates name the tier and include a billing URL', () => {
  const started = billing.subscriptionStartedEmail({
    name: 'Ada Lovelace', tier: 'lite', period: 'yearly', chats: 10,
  });
  assert.match(started.subject, /Lite/i);
  assert.match(started.html, /10 chats/);
  assert.match(started.html, /subscribe\.html/);
  assert.match(started.text, /Lite/);

  const failed = billing.paymentFailedEmail({ name: 'Ada', tier: 'premium' });
  assert.match(failed.subject, /renew/i);
  assert.match(failed.html, /Premium/);
  assert.match(failed.html, /subscribe\.html/);

  const canceled = billing.subscriptionCanceledEmail({
    name: 'Ada', tier: 'premium', accessUntil: '2026-09-01',
  });
  assert.match(canceled.html, /2026-09-01/);
  assert.match(canceled.text, /canceled/i);
});

test('notifyStripeEvent sends confirmation once for checkout.session.completed', async () => {
  const sent = [];
  const db = {
    getUserById: async () => ({ id: 1, name: 'Ada', email: 'ada@example.com' }),
  };
  const result = {
    applied: true,
    userId: 1,
    productId: 'com.kinrows.app.concierge.premium.monthly',
    tier: 'premium',
  };
  const out = await billing.notifyStripeEvent(
    db,
    { type: 'checkout.session.completed' },
    result,
    async (msg) => { sent.push(msg); return { ok: true, id: 'msg_1' }; },
  );
  assert.equal(out.sent, true);
  assert.equal(out.kind, 'started');
  assert.equal(sent.length, 1);
  assert.equal(sent[0].to, 'ada@example.com');
  assert.match(sent[0].subject, /Premium/);
  assert.equal(subscription.chatsForProduct(result.productId), 40);

  const ignored = await billing.notifyStripeEvent(
    db,
    { type: 'invoice.paid' },
    result,
    async (msg) => { sent.push(msg); return { ok: true, id: 'msg_2' }; },
  );
  assert.equal(ignored.sent, false);
  assert.equal(sent.length, 1);

  const failed = await billing.notifyStripeEvent(
    db,
    { type: 'invoice.payment_failed' },
    result,
    async (msg) => { sent.push(msg); return { ok: true, id: 'msg_3' }; },
  );
  assert.equal(failed.kind, 'failed');
  assert.equal(sent.length, 2);
});
