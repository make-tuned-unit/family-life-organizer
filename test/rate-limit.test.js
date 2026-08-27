// Concierge daily-cap limiter: Lite 10 / Premium 40 with a structured 429.

const { test } = require('node:test');
const assert = require('node:assert');
const { createRateLimiter } = require('../services/rateLimit');
const { TIER_DAILY_CAP, chatsForTier } = require('../services/subscription');

function mockRes() {
  return {
    statusCode: 200,
    body: null,
    headers: {},
    set(k, v) { this.headers[k] = v; },
    status(c) { this.statusCode = c; return this; },
    json(b) { this.body = b; return this; },
  };
}

test('tier caps are 10 lite / 40 premium', () => {
  assert.equal(TIER_DAILY_CAP.lite, 10);
  assert.equal(TIER_DAILY_CAP.premium, 40);
  assert.equal(chatsForTier('lite'), 10);
  assert.equal(chatsForTier('premium'), 40);
  assert.equal(chatsForTier(null), 0);
});

test('daily cap 429 includes tier, limit, Retry-After, and upgrade hint for Lite', async () => {
  const limiter = createRateLimiter({
    windowMs: 60_000,
    max: 2,
    force: true,
    keyFn: async () => 'hh:1',
    maxFn: async () => 2,
    extraFn: async (_req, { limit, retryAfter }) => ({
      code: 'daily_cap',
      tier: 'lite',
      limit,
      upgrade: true,
      error: `You've used today's ${limit} Lite chats. Upgrade to Premium for ${TIER_DAILY_CAP.premium} a day, or try again tomorrow.`,
      retry_after: retryAfter,
    }),
  });
  const req = {};
  const next = () => {};
  const r1 = mockRes(); await limiter(req, r1, next);
  const r2 = mockRes(); await limiter(req, r2, next);
  assert.equal(r1.statusCode, 200);
  assert.equal(r2.statusCode, 200);
  const r3 = mockRes(); await limiter(req, r3, next);
  assert.equal(r3.statusCode, 429);
  assert.equal(r3.body.code, 'daily_cap');
  assert.equal(r3.body.tier, 'lite');
  assert.equal(r3.body.limit, 2);
  assert.equal(r3.body.upgrade, true);
  assert.match(r3.body.error, /2 Lite chats/);
  assert.match(r3.body.error, /40 a day/);
  assert.ok(Number(r3.headers['Retry-After']) >= 1);
});
