// Tiny in-memory sliding-window rate limiter (per-process).
// Enough to stop a single client from looping an expensive endpoint; not a
// distributed limiter. keyFn derives the bucket key (e.g. the user id).

function createRateLimiter({ windowMs = 60000, max = 30, keyFn }) {
  const hits = new Map(); // key -> [timestamps]
  return function rateLimit(req, res, next) {
    const key = keyFn(req);
    const now = Date.now();
    const recent = (hits.get(key) || []).filter(t => now - t < windowMs);
    if (recent.length >= max) {
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
