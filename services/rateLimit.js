// Tiny in-memory sliding-window rate limiter (per-process).
// Enough to stop a single client from looping an expensive endpoint; not a
// distributed limiter. keyFn derives the bucket key (e.g. the user id).

// keyFn may be sync or async (e.g. when the bucket key needs a DB lookup such as
// the caller's household). maxFn, if given, derives the per-request limit (e.g. a
// tier-dependent daily cap) and overrides the static `max`. If deriving the key
// or limit fails (e.g. a transient DB error) the limiter does NOT fail open — it
// falls back to a coarse per-user/per-IP bucket at the static `max`, since a key
// lookup failing is exactly when an expensive endpoint is already under load.
// Disabled under `NODE_ENV=test` so the suite (which hammers endpoints from one
// IP) isn't throttled; no test depends on rate-limit behavior.
const RATE_LIMIT_OFF = process.env.NODE_ENV === 'test';

function createRateLimiter({ windowMs = 60000, max = 30, keyFn, maxFn, extraFn, force }) {
  const hits = new Map(); // key -> [timestamps]
  return async function rateLimit(req, res, next) {
    if (RATE_LIMIT_OFF && !force) return next();
    let key, limit = max;
    try {
      key = await keyFn(req);
    } catch {
      key = `fallback:${req.session?.user?.id || req.ip || 'anon'}`;
    }
    if (maxFn) {
      try { limit = await maxFn(req); } catch { limit = max; }
    }
    const now = Date.now();
    const recent = (hits.get(key) || []).filter(t => now - t < windowMs);
    if (recent.length >= limit) {
      const retryAfter = Math.max(1, Math.ceil(((recent[0] || now) + windowMs - now) / 1000));
      if (typeof res.set === 'function') res.set('Retry-After', String(retryAfter));
      let extra = {};
      if (extraFn) {
        try { extra = (await extraFn(req, { limit, used: recent.length, retryAfter, windowMs })) || {}; } catch { /* ignore */ }
      }
      return res.status(429).json({
        error: extra.error || 'Too many requests, please slow down.',
        code: extra.code || 'rate_limited',
        limit,
        retry_after: retryAfter,
        ...extra,
      });
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
