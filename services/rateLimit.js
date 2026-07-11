// Tiny in-memory sliding-window rate limiter (per-process).
// Enough to stop a single client from looping an expensive endpoint; not a
// distributed limiter. keyFn derives the bucket key (e.g. the user id).

// keyFn may be sync or async (e.g. when the bucket key needs a DB lookup such as
// the caller's household). maxFn, if given, derives the per-request limit (e.g. a
// tier-dependent daily cap) and overrides the static `max`. Errors deriving either
// fail open rather than blocking.
// Disabled under `NODE_ENV=test` so the suite (which hammers endpoints from one
// IP) isn't throttled; no test depends on rate-limit behavior.
const RATE_LIMIT_OFF = process.env.NODE_ENV === 'test';

function createRateLimiter({ windowMs = 60000, max = 30, keyFn, maxFn }) {
  const hits = new Map(); // key -> [timestamps]
  return async function rateLimit(req, res, next) {
    if (RATE_LIMIT_OFF) return next();
    let key, limit = max;
    try {
      key = await keyFn(req);
      if (maxFn) limit = await maxFn(req);
    } catch { return next(); }
    const now = Date.now();
    const recent = (hits.get(key) || []).filter(t => now - t < windowMs);
    if (recent.length >= limit) {
      return res.status(429).json({ error: 'Too many requests, please slow down.' });
    }
    recent.push(now);
    hits.set(key, recent);
    if (recent.length === 1) {
      // Opportunistically drop keys whose windows have fully aged out.
      for (const [k, ts] of hits) if (ts.length && now - ts[ts.length - 1] >= windowMs) hits.delete(k);
    }
    next();
  };
}

module.exports = { createRateLimiter };
