(function loadDotEnv() {
  if (process.env.NODE_ENV === 'test') return;
  const envPath = require('path').join(__dirname, '.env');
  let text;
  try { text = require('fs').readFileSync(envPath, 'utf8'); } catch { return; }
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

process.env.TZ = process.env.TZ || 'America/Halifax';

const express = require('express');
const session = require('express-session');
const helmet = require('helmet');
const SQLiteStore = require('connect-sqlite3')(session);
const bodyParser = require('body-parser');
const bcrypt = require('bcryptjs');
const path = require('path');
const fs = require('fs');
const FamilyDB = require('./database');
const jobs = require('./services/jobs');
const ai = require('./services/anthropic');
const { buildSnapshot } = require('./services/conciergeContext');
const { generateBrief, runDailyBriefSweep } = require('./services/conciergeBrief');
const { handleChat, handleChatStream } = require('./services/conciergeChat');
const subscription = require('./services/subscription');
const stripeBilling = require('./services/stripe');
const developerApi = require('./services/developerApi');
const { runProactiveSweep } = require('./services/conciergeNudge');
const { announceRivalryCompletion } = require('./services/rivalryAnnounce');
const { createRateLimiter } = require('./services/rateLimit');
const email = require('./services/email');
const { runOnboardingEmailSweep } = require('./services/onboardingEmail');
const householdInvite = require('./services/householdInvite');
const appleSignIn = require('./services/appleSignIn');
const crypto = require('crypto');
const zlib = require('zlib');

const IS_PROD = process.env.NODE_ENV === 'production';

// Session signing key. MUST be provided via env in production — a committed/static
// secret lets anyone forge session cookies for any user. Fail fast rather than
// silently fall back to a known value in prod.
const SESSION_SECRET = process.env.SESSION_SECRET;
if (IS_PROD && !SESSION_SECRET) {
  console.error('FATAL: SESSION_SECRET must be set in production.');
  process.exit(1);
}
if (!SESSION_SECRET) {
  console.warn('⚠️  SESSION_SECRET not set — using an ephemeral dev key (sessions reset on restart).');
}
// Ephemeral random key in dev when unset (still better than a committed constant).
const RESOLVED_SESSION_SECRET = SESSION_SECRET || require('crypto').randomBytes(32).toString('hex');

// A real (cost-12) bcrypt hash of a random value, used to equalize login timing
// when the supplied username doesn't exist (anti–user-enumeration). Never matches.
const DUMMY_BCRYPT_HASH = '$2b$12$w84BxL/MRATPauz/o3aSHOL.GRebIAjAMNDXftZxWFzHoU1yo6TW6';

// Per-user rate limit for the (AI-backed, costly) concierge endpoints.
const conciergeLimiter = createRateLimiter({ windowMs: 60000, max: 30, keyFn: req => req.session?.user?.id ?? clientIp(req) });
// Daily ceiling on the (expensive, tool-looping) chat endpoint to bound API cost
// even if the per-minute limit is paced. Each message can fan out to several
// Claude calls, so cap messages/user/day.
// Per-tier daily chat allowance per HOUSEHOLD (one sub covers the whole household, so
// the cap bounds the household's combined spend, not each member's). Lite = 10/day,
// Premium = 40/day. Null tier (no active sub) defaults to the lite cap, but
// requirePremium blocks those callers anyway, so it's only a backstop.
const TIER_DAILY_CAP = { premium: 40, lite: 10 };

// Resolve {household key, tier} for a request, memoized briefly to avoid a DB hit on
// every call (household membership and tier change rarely). Falls back to a per-user
// key if the household can't be resolved. Cache is invalidated on subscription verify.
const _householdEntitlementCache = new Map(); // userId -> { gid, tier, ts }
const HOUSEHOLD_KEY_TTL_MS = 5 * 60 * 1000;
async function resolveHouseholdEntitlement(req) {
  const uid = req.session?.user?.id;
  if (!uid) return { key: clientIp(req), tier: null };
  const cached = _householdEntitlementCache.get(uid);
  if (cached && Date.now() - cached.ts < HOUSEHOLD_KEY_TTL_MS) {
    return { key: cached.gid ? `hh:${cached.gid}` : `u:${uid}`, tier: cached.tier };
  }
  const db = new FamilyDB();
  try {
    const gid = await db.getUserHouseholdId(uid);
    const tier = gid ? await subscription.getHouseholdTier(db, uid) : null;
    _householdEntitlementCache.set(uid, { gid, tier, ts: Date.now() });
    return { key: gid ? `hh:${gid}` : `u:${uid}`, tier };
  } catch {
    return { key: `u:${uid}`, tier: null };
  } finally {
    db.close();
  }
}
async function householdRateKey(req) { return (await resolveHouseholdEntitlement(req)).key; }
async function householdDailyMax(req) {
  const { tier } = await resolveHouseholdEntitlement(req); // second call this request hits the cache
  return TIER_DAILY_CAP[tier] ?? TIER_DAILY_CAP.lite;
}

// Tier-aware daily cap, bounded per HOUSEHOLD (was a flat 200/user = ~6000/mo, dangerous).
const conciergeChatDailyLimiter = createRateLimiter({ windowMs: 24 * 60 * 60 * 1000, keyFn: householdRateKey, maxFn: householdDailyMax });

// Daily cap for the other Anthropic-calling endpoints (cook suggestions,
// receipt vision scans). Generous for real use, but stops an authenticated
// loop from running up the API bill — these had no cap at all before.
const aiDailyLimiter = createRateLimiter({ windowMs: 24 * 60 * 60 * 1000, max: 60, keyFn: req => `ai:${req.session?.user?.id ?? clientIp(req)}` });

// IP-keyed limiter for the unauthenticated, brute-forceable auth endpoints.
// Use req.ip (derived by Express under `trust proxy: 1` from the RIGHTMOST
// proxy-appended X-Forwarded-For entry) — never the raw leftmost XFF value,
// which the client controls and could rotate to bypass the limiter.
const clientIp = (req) => req.ip || 'unknown';
// 20/min/IP: headroom for the multi-step 2FA flow (login → email → verify) and
// a family behind one NAT, while still throttling brute force (bcrypt cost 12
// adds ~250ms/attempt server-side on top).
const loginLimiter = createRateLimiter({ windowMs: 60000, max: 20, keyFn: clientIp });
const registerLimiter = createRateLimiter({ windowMs: 60 * 60 * 1000, max: 5, keyFn: clientIp });
const reportLimiter = createRateLimiter({ windowMs: 60 * 60 * 1000, max: 20, keyFn: req => req.session?.user?.id ?? clientIp(req) });

// Regenerate the session to a fresh id and persist the authenticated user on it.
// Prevents session fixation (an attacker-planted pre-auth session id surviving login).
function establishSession(req, user) {
  return new Promise((resolve, reject) => {
    req.session.regenerate((err) => {
      if (err) return reject(err);
      req.session.user = user;
      req.session.save((err2) => err2 ? reject(err2) : resolve());
    });
  });
}

// ── Email two-factor login ───────────────────────────────────────────────────
// OFF by default so deploying this code can't lock out an older app build that
// has no 2FA UI. Flip on (AUTH_2FA_ENABLED=1) only once the 2FA-capable build is
// installed and RESEND_API_KEY is set. Then it's required for everyone.
const TWO_FA_ENABLED = process.env.AUTH_2FA_ENABLED === '1';
if (TWO_FA_ENABLED && IS_PROD && !process.env.RESEND_API_KEY) {
  console.error('FATAL: AUTH_2FA_ENABLED=1 but RESEND_API_KEY is not set — no code email can be sent, which locks every user out of login.');
  process.exit(1);
}
const TWO_FA_TTL_MS = 10 * 60 * 1000;   // code/challenge lifetime
const TWO_FA_MAX_ATTEMPTS = 5;          // wrong-code guesses before a challenge dies
// TEST ONLY: echo the code in the JSON response so automated tests can complete
// the flow without an inbox. Never enable in production.
const TWO_FA_ECHO = process.env.AUTH_2FA_ECHO_CODE === '1';
if (TWO_FA_ECHO && IS_PROD) {
  console.error('FATAL: AUTH_2FA_ECHO_CODE must never be set in production — it leaks every OTP in the login response.');
  process.exit(1);
}
const echoCode = (code) => (TWO_FA_ECHO ? { dev_code: code } : {});

function genCode() {
  return String(crypto.randomInt(0, 1_000_000)).padStart(6, '0');
}
function hashCode(code) {
  return crypto.createHash('sha256').update(String(code)).digest('hex');
}
function codeMatches(code, hash) {
  if (!hash) return false;
  const a = Buffer.from(hashCode(code));
  const b = Buffer.from(hash);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}
function challengeExpiry() {
  return new Date(Date.now() + TWO_FA_TTL_MS).toISOString();
}
function challengeExpired(row) {
  const t = Date.parse(row.expires_at);
  return Number.isNaN(t) || Date.now() > t;
}
function maskEmail(e) {
  if (!e || !e.includes('@')) return '';
  const [u, d] = e.split('@');
  const head = u.slice(0, 1);
  return `${head}${'•'.repeat(Math.max(1, u.length - 1))}@${d}`;
}
// Email the 6-digit code via Resend. Non-fatal: surfaced as a flag to the client.
async function sendLoginCode(to, code) {
  // Code in the subject → visible in the notification banner at a glance.
  const subject = `${code} is your Kinrows code`;
  // Plain-text line phrased "Your Kinrows verification code is NNNNNN" — the exact
  // shape iOS scans for to offer one-tap AutoFill above the keyboard (the app's
  // code field is .oneTimeCode), so the code usually needs no copy/paste at all.
  const text = `Your Kinrows verification code is ${code}\n\nIt expires in 10 minutes. If you didn't try to sign in, ignore this email.`;
  const html = `<div style="font-family:-apple-system,Segoe UI,Roboto,sans-serif;max-width:420px;margin:0 auto;padding:24px;color:#2c2017">
    <h2 style="margin:0 0 8px">Your verification code</h2>
    <p style="color:#5c4a3a;margin:0 0 16px">Your Kinrows verification code is:</p>
    <p style="font-size:34px;font-weight:700;letter-spacing:8px;background:#fffaf0;border:1px solid #ece0c8;border-radius:12px;padding:16px;text-align:center;margin:0;font-family:ui-monospace,SFMono-Regular,Menlo,monospace">${code}</p>
    <p style="color:#8a7460;font-size:13px;margin:16px 0 0">Tap to select the code above to copy it, or let your iPhone fill it in automatically. Expires in 10 minutes. If this wasn't you, ignore this email.</p>
  </div>`;
  return email.sendEmail({ to, subject, text, html });
}

// Short-lived per-user cache for the daily brief (regenerated on ?refresh).
const briefCache = new Map();
const BRIEF_TTL_MS = 30 * 60 * 1000; // 30 min: fewer brief regenerations = fewer AI calls
const _briefRegenInFlight = new Set(); // guards against duplicate background regens per cacheKey

// Regenerate a user's brief off the request thread and update the cache.
// Used for stale-while-revalidate so the HTTP request never blocks on the
// Anthropic call. Errors are logged, not swallowed.
function regenerateBriefInBackground(userId, userName, skipAI, cacheKey) {
  if (_briefRegenInFlight.has(cacheKey)) return;
  _briefRegenInFlight.add(cacheKey);
  (async () => {
    const db = new FamilyDB();
    try {
      const snapshot = await buildSnapshot(db, userId);
      const brief = await generateBrief(snapshot, userName, { skipAI });
      const now = Date.now();
      for (const [k, v] of briefCache) if (now - v.ts >= BRIEF_TTL_MS) briefCache.delete(k);
      briefCache.set(cacheKey, { brief, ts: now });
    } catch (e) {
      console.error('[brief] background regen failed:', e?.message || e);
    } finally {
      db.close();
      _briefRegenInFlight.delete(cacheKey);
    }
  })();
}

const app = express();
const PORT = process.env.PORT || 3456;

// Haversine distance in meters between two lat/lng points
function haversineDistance(lat1, lng1, lat2, lng2) {
  const R = 6371000;
  const toRad = d => d * Math.PI / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a = Math.sin(dLat/2)**2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng/2)**2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
}

// Middleware
// Behind Render/Railway's TLS-terminating proxy: trust X-Forwarded-* so secure
// cookies and req.ip work correctly.
app.set('trust proxy', 1);
app.use(helmet({
  // The API + a few server-rendered pages; CSP is enforced on the static
  // marketing site via its own meta tags. Keep HSTS/no-sniff/frame-guard.
  // The server-rendered /login and /app pages set their own CSP (PAGE_CSP).
  contentSecurityPolicy: false,
}));

// Gzip JSON API bodies when the client asks. Uses Node zlib (no extra
// package). SSE and HTML use res.write/res.send, not res.json, so they stay
// uncompressed. URLSession already sends Accept-Encoding: gzip and inflates.
function gzipJson(req, res, next) {
  if (!/\bgzip\b/i.test(String(req.headers['accept-encoding'] || ''))) return next();
  const originalJson = res.json.bind(res);
  res.json = (body) => {
    if (res.headersSent) return originalJson(body);
    let payload;
    try { payload = JSON.stringify(body); } catch { return originalJson(body); }
    try {
      const buf = zlib.gzipSync(Buffer.from(payload));
      res.setHeader('Content-Type', 'application/json; charset=utf-8');
      res.setHeader('Content-Encoding', 'gzip');
      res.setHeader('Vary', 'Accept-Encoding');
      res.setHeader('Content-Length', String(buf.length));
      return res.end(buf);
    } catch {
      return originalJson(body);
    }
  };
  next();
}
app.use(gzipJson);

// Weak ETag for read-mostly GETs. Hash includes userId so a cached 304 cannot
// be an oracle across accounts. Cache-Control is private + no-cache: store,
// but always revalidate. Auth routes must not use this.
function sendCachedJson(req, res, userId, body) {
  const payload = JSON.stringify(body);
  const etag = `W/"${crypto.createHash('sha1').update(`${userId}\n${payload}`).digest('hex').slice(0, 16)}"`;
  res.setHeader('ETag', etag);
  res.setHeader('Cache-Control', 'private, no-cache');
  const inm = String(req.headers['if-none-match'] || '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
  if (inm.includes(etag)) {
    res.status(304).end();
    return;
  }
  res.json(body);
}

function decodeStoredImage(stored) {
  if (stored == null || stored === '') return null;
  let s = String(stored).trim();
  const marker = 'base64,';
  const idx = s.indexOf(marker);
  if (idx !== -1) s = s.slice(idx + marker.length);
  const buf = Buffer.from(s, 'base64');
  return buf.length ? buf : null;
}

function wantsBinaryImage(req) {
  if (String(req.query.format || '') === 'json') return false;
  const accept = String(req.headers.accept || '');
  if (/\bimage\/(jpeg|jpg|png|\*)\b/i.test(accept)) return true;
  if (/\bapplication\/json\b/i.test(accept) && !/\bimage\//i.test(accept)) return false;
  return true;
}

function sendStoredImage(req, res, stored, jsonKey = 'image') {
  if (stored == null || stored === '') return false;
  if (!wantsBinaryImage(req)) {
    res.setHeader('Cache-Control', 'private, no-cache');
    res.json({ [jsonKey]: stored });
    return true;
  }
  const buf = decodeStoredImage(stored);
  if (!buf) return false;
  const isJpeg = buf[0] === 0xff && buf[1] === 0xd8;
  res.setHeader('Content-Type', isJpeg ? 'image/jpeg' : 'image/png');
  res.setHeader('Cache-Control', 'private, no-cache');
  res.setHeader('Content-Length', String(buf.length));
  res.end(buf);
  return true;
}

// CSP for the server-rendered pages. Their markup relies on inline <script>/
// <style>/handlers, so 'unsafe-inline' stays — but external script loading,
// fetch/XHR exfiltration, and remote image beacons are all blocked, which
// bounds the blast radius of any injected markup.
const PAGE_CSP = [
  "default-src 'self'",
  "script-src 'unsafe-inline'",
  "style-src 'unsafe-inline' https://fonts.googleapis.com",
  "font-src https://fonts.gstatic.com",
  "img-src 'self' data:",
  "connect-src 'self'",
  "object-src 'none'",
  "base-uri 'self'",
  "form-action 'self'",
  "frame-ancestors 'none'",
].join('; ');

// Escape a value for interpolation into server-rendered HTML.
const htmlEsc = (s) => String(s ?? '')
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
// Small default cap to blunt memory-exhaustion via large bodies (the body is
// parsed before auth). Routes that legitimately carry a base64 image opt into a
// larger cap by path. Everything else — including the unauthenticated auth
// endpoints — is held to 1mb.
const jsonSmall = bodyParser.json({ limit: '1mb' });
const jsonLarge = bodyParser.json({ limit: '8mb' });
// Text parser for analytics collect endpoint (sendBeacon sends text/plain)
const textAny = bodyParser.text({ type: '*/*', limit: '1mb' });
const LARGE_BODY_PATHS = [
  /^\/api\/users\/me\/avatar$/,
  /^\/api\/groups\/[^/]+\/avatar$/,
  /^\/api\/receipts(\/(scan|save))?$/,
  /^\/api\/decisions$/,
  /^\/api\/messages$/,
  /^\/api\/milestones(\/\d+)?$/,  // optional base64 photo on create/update
];
app.use((req, res, next) => {
  if (req.method === 'POST' && req.path === '/api/subscription/stripe') {
    return bodyParser.raw({ type: 'application/json', limit: '1mb' })(req, res, next);
  }
  const parser = LARGE_BODY_PATHS.some(re => re.test(req.path)) ? jsonLarge : jsonSmall;
  parser(req, res, next);
});
app.use(bodyParser.urlencoded({ extended: true, limit: '1mb' }));
app.use(session({
  store: new SQLiteStore({ dir: FamilyDB.DB_DIR, db: 'sessions.db', concurrentDB: true }),
  secret: RESOLVED_SESSION_SECRET,
  resave: false,
  saveUninitialized: false,
  cookie: {
    secure: IS_PROD,          // HTTPS-only in production
    httpOnly: true,           // not readable from JS
    sameSite: 'lax',          // blocks cross-site cookie sends (CSRF)
    maxAge: 30 * 24 * 60 * 60 * 1000, // 30 days
  },
}));
// CSP for the public marketing site. Allows script from same origin and inline,
// and permits POST beacons to /api/permagent-analytics/collect.
const WEBSITE_CSP = [
  "default-src 'self'",
  "script-src 'self' 'unsafe-inline'",  // allows both external files and inline
  "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
  "font-src https://fonts.gstatic.com",
  "img-src 'self' data: https:",
  "connect-src 'self'",  // POST to /api/permagent-analytics/collect
  "object-src 'none'",
  "base-uri 'self'",
  "form-action 'self'",
  "frame-ancestors 'none'",
].join('; ');

// Handler to inject analytics snippet into website HTML files.
// express.static uses sendFile, not send/write/end, so we need explicit routes.
function serveWebsiteHtml(filePath) {
  return (req, res) => {
    const fullPath = path.join(__dirname, 'website', filePath);
    fs.readFile(fullPath, 'utf8', (err, html) => {
      if (err) {
        // File not found or read error
        return res.status(404).send('Not found');
      }
      
      // Set CSP header
      res.set('Content-Security-Policy', WEBSITE_CSP);
      
      // The collect path MUST appear in the HTML itself — Permagent's install
      // verifier greps the document, not /analytics.js. Keep this as a safety
      // net for any page that was not committed with the snippet.
      if (!html.includes('/api/permagent-analytics/collect') && html.includes('</head>')) {
        html = html.replace('</head>',
          `<script>window.permagentCollectUrl='/api/permagent-analytics/collect';</script>\n` +
          `<script src="/analytics.js" defer></script>\n</head>`);
      } else if (!html.includes('analytics.js') && html.includes('</head>')) {
        html = html.replace('</head>', `<script src="/analytics.js" defer></script>\n</head>`);
      }
      
      // Set correct content type and send
      res.set('Content-Type', 'text/html; charset=utf-8');
      res.send(html);
    });
  };
}

// Explicit routes for website HTML files (must come BEFORE express.static)
app.get('/', serveWebsiteHtml('index.html'));
app.get('/about', serveWebsiteHtml('index.html')); // /about also serves index.html for SPA routing
app.get('/privacy', serveWebsiteHtml('privacy.html'));
app.get('/privacy.html', serveWebsiteHtml('privacy.html'));
app.get('/terms', serveWebsiteHtml('terms.html'));
app.get('/terms.html', serveWebsiteHtml('terms.html'));
app.get('/support', serveWebsiteHtml('support.html'));
app.get('/support.html', serveWebsiteHtml('support.html'));
app.get('/developers', serveWebsiteHtml('developers.html'));
app.get('/developers.html', serveWebsiteHtml('developers.html'));
app.get('/compare', serveWebsiteHtml('compare.html'));
app.get('/compare.html', serveWebsiteHtml('compare.html'));
app.get('/subscribe', serveWebsiteHtml('subscribe.html'));
app.get('/subscribe.html', serveWebsiteHtml('subscribe.html'));
app.get('/best-chore-app-for-families', serveWebsiteHtml('best-chore-app-for-families.html'));
app.get('/best-chore-app-for-families.html', serveWebsiteHtml('best-chore-app-for-families.html'));
app.get('/best-family-calendar-app', serveWebsiteHtml('best-family-calendar-app.html'));
app.get('/best-family-calendar-app.html', serveWebsiteHtml('best-family-calendar-app.html'));
app.get('/best-family-organizer-apps', serveWebsiteHtml('best-family-organizer-apps.html'));
app.get('/best-family-organizer-apps.html', serveWebsiteHtml('best-family-organizer-apps.html'));
app.get('/best-shared-shopping-list-app', serveWebsiteHtml('best-shared-shopping-list-app.html'));
app.get('/best-shared-shopping-list-app.html', serveWebsiteHtml('best-shared-shopping-list-app.html'));

// Public static assets (CSS, JS, images, etc.) — serve after HTML routes
// so /analytics.js and /assets/* are still available from express.static
app.use(express.static(path.join(__dirname, 'website')));
app.use(express.static(path.join(__dirname, 'public')));

// Liveness/readiness probe (used by the host's health check). Pings the DB.
app.get('/healthz', (req, res) => {
  const db = new FamilyDB();
  db.db.get('SELECT 1', (err) => {
    db.close();
    if (err) return res.status(503).json({ ok: false });
    res.json({ ok: true });
  });
});

// Auth middleware
function requireAuth(req, res, next) {
  if (req.session.user) {
    next();
  } else {
    // Return JSON 401 for API requests, redirect for browser
    const isApi = req.path.startsWith('/api/');
    if (isApi) {
      res.status(401).json({ error: 'Not authenticated' });
    } else {
      res.redirect('/login');
    }
  }
}

// Log the real error server-side; return an opaque 500 to the client so SQL/
// schema/stack details never leak. Used by every route's terminal catch.
function sendServerError(res, err) {
  console.error('[error]', err && err.stack ? err.stack : err);
  if (!res.headersSent) res.status(500).json({ error: 'Internal server error' });
}

// ── Device refresh tokens ────────────────────────────────────────────────────
// Long-lived, revocable credentials so the iOS app never stores the account
// password. Opaque 256-bit values; only SHA-256 hashes are stored server-side
// (same helper as the 2FA codes). Rotated on every token-login; a short grace
// window tolerates a lost rotation response without stranding the device.
const hashAuthToken = hashCode;
const AUTH_TOKEN_GRACE_SECONDS = Number(process.env.AUTH_TOKEN_GRACE_SECONDS ?? 60);

// Place a brand-new user in a household. An invite code that doesn't resolve
// is an error (don't silently mint a second household — that was the Cozi-style
// "I tapped Sign Up instead of Join" trap).
async function assignHousehold(db, user, { invite_code, household_name } = {}) {
  const code = invite_code != null ? String(invite_code).trim().toUpperCase() : '';
  if (code) {
    const household = await db.getGroupByInviteCode(code);
    if (!household) {
      const err = new Error('invite_not_found');
      err.status = 400;
      throw err;
    }
    await db.addGroupMember(household.id, { user_id: user.id, role: 'member', added_by: user.id });
    return { id: household.id, invite_code: household.invite_code };
  }
  const householdName = (household_name && String(household_name).trim()) || `${user.name}'s Home`;
  const created = await db.createGroup({
    name: householdName,
    group_type: 'household',
    created_by: user.id
  });
  await db.addGroupMember(created.id, { user_id: user.id, role: 'admin', added_by: user.id });
  return { id: created.id, invite_code: created.invite_code };
}

async function uniqueAppleUsername(db, appleSub) {
  const base = `apple_${crypto.createHash('sha256').update(appleSub).digest('hex').slice(0, 8)}`;
  if (!(await db.getUserByUsername(base))) return base;
  for (let i = 0; i < 8; i++) {
    const candidate = `${base}${crypto.randomBytes(2).toString('hex')}`;
    if (!(await db.getUserByUsername(candidate))) return candidate;
  }
  throw new Error('Could not allocate a unique username');
}

function sanitizeDisplayName(name) {
  const cleaned = String(name || '').replace(/[\x00-\x1f\x7f]/g, '').trim();
  if (!cleaned) return 'Kinrows member';
  return cleaned.slice(0, 80);
}

function jsonUser(user) {
  return { id: user.id, username: user.username, name: user.name, avatar: user.avatar || null };
}

async function issueAuthToken(db, userId, deviceName) {
  const token = crypto.randomBytes(32).toString('hex');
  // Prune this user's stale rotation tombstones so the table doesn't grow
  // forever (grace only needs recently-rotated rows).
  await dbRun(db, "DELETE FROM auth_tokens WHERE user_id = ? AND revoked = 1 AND (last_used_at IS NULL OR last_used_at < datetime('now','-1 day'))", [userId]);
  await dbRun(db, 'INSERT INTO auth_tokens (user_id, token_hash, device_name) VALUES (?, ?, ?)',
    [userId, hashAuthToken(token), deviceName || null]);
  return token;
}

// Money-ish input ("$1,299.00", 42.1) → finite number, or null. SQLite stores
// strings verbatim and SUM() treats them as 0, silently corrupting budget
// math — every money-bearing route must coerce through here.
function parseMoney(value) {
  const n = Number(String(value).replace(/[$,\s]/g, ''));
  return Number.isFinite(n) ? n : null;
}

// Clamp a client-supplied ?limit into a sane positive range. A raw
// `parseInt(x) || def` lets `limit=-1` through, and SQLite reads LIMIT -1 as
// "no limit" — one request can then dump an entire (photo-bearing) table slice.
function clampLimit(value, def, max = 200) {
  const n = parseInt(value, 10);
  if (!Number.isInteger(n) || n <= 0) return def;
  return Math.min(n, max);
}

// Server-local YYYY-MM-DD. Using UTC (toISOString) rolled "today" forward in the
// evening (Halifax is UTC-3/-4), landing receipts in the wrong day/month and
// mis-filtering "today"'s appointments — inconsistent with getSpendingStats,
// which already uses en-CA local. This is the single source of truth for it.
function todayLocal() {
  return new Date().toLocaleDateString('en-CA');
}

// Server-local HH:MM — the default "now" when a live sleep is started or ended
// without an explicit time.
function nowTimeLocal() {
  return new Date().toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', hour12: false });
}

// Server-local YYYY-MM-DD offset from today by `offsetDays` (may be negative).
function fromLocalDate(offsetDays) {
  return new Date(Date.now() + offsetDays * 86400000).toLocaleDateString('en-CA');
}

// The caller may only act on contacts they created (contacts are owner-scoped).
async function userOwnsContact(db, contactId, userId) {
  return !!(await dbGet(db, 'SELECT 1 FROM contacts WHERE id = ? AND added_by = ?', [contactId, userId]));
}

// Two users are "known" to each other when they share any group membership.
async function usersShareGroup(db, userA, userB) {
  return !!(await dbGet(db, `SELECT 1 FROM group_members a
    JOIN group_members b ON a.group_id = b.group_id
    WHERE a.user_id = ? AND b.user_id = ? LIMIT 1`, [userA, userB]));
}

// A coverage approval must reference a window, and only one belonging to its
// own request (coverage_approvals.window_id is NOT NULL — a missing window
// used to surface as a 500). Returns the window row on success, or null after
// having sent a 4xx.
async function requireWindowInRequest(db, windowId, requestId, res) {
  if (!windowId) {
    res.status(400).json({ error: 'Pick a time window to confirm' });
    return null;
  }
  const win = await dbGet(db, 'SELECT * FROM coverage_windows WHERE id = ? AND request_id = ?',
    [windowId, requestId]);
  if (!win) { res.status(400).json({ error: 'Invalid window for this request' }); return null; }
  return win;
}

// Final approved date/times: honor the helper's values, else default to the
// chosen window's. Guarantees the NOT NULL coverage_approvals columns are set
// (a client omitting them used to 500). Returns null after sending a 400.
// Where human-facing links (the coverage approval page) should point. The
// marketing host fronts the API in production, so links read as kinrows.com
// rather than a Railway hostname; locally they point at this server.
function publicBaseUrl() {
  if (process.env.SITE_URL) return process.env.SITE_URL.replace(/\/$/, '');
  return IS_PROD ? 'https://kinrows.com' : `http://localhost:${PORT}`;
}
function coverageShareUrl(token) { return `${publicBaseUrl()}/c/${token}`; }

function resolveApprovalTimes(win, body, res) {
  const approved_date = normalizeDate(body.approved_date || win.window_date || '');
  const approved_start = body.approved_start || win.start_time;
  const approved_end = body.approved_end || win.end_time;
  if (!approved_date || !approved_start || !approved_end) {
    res.status(400).json({ error: 'A date, start and end time are required' });
    return null;
  }
  return { approved_date, approved_start, approved_end };
}

// The iOS household roster shows group members who aren't contact rows as
// pseudo-contacts with id = -(user_id). Resolve those to a REAL contact row
// owned by the caller (find-or-create by name) so downstream joins (incoming
// coverage, pushes) work, gated on actually sharing a group with the person.
// Returns the resolved positive contact id, or null (a 403 was sent).
async function resolveOwnedContactId(db, rawId, userId, res) {
  const cid = Number(rawId);
  if (!Number.isInteger(cid) || cid === 0) {
    res.status(400).json({ error: 'Invalid contact' });
    return null;
  }
  if (cid > 0) {
    if (!(await userOwnsContact(db, cid, userId))) {
      res.status(403).json({ error: 'You can only use your own contacts' });
      return null;
    }
    return cid;
  }
  const targetUserId = -cid;
  if (!(await usersShareGroup(db, userId, targetUserId))) {
    res.status(403).json({ error: 'You can only ask people in your groups' });
    return null;
  }
  const target = await db.getUserById(targetUserId);
  if (!target) { res.status(403).json({ error: 'Unknown person' }); return null; }
  const existing = await dbGet(db, 'SELECT id FROM contacts WHERE added_by = ? AND LOWER(name) = LOWER(?)',
    [userId, target.name]);
  if (existing) return existing.id;
  const ins = await dbRun(db,
    'INSERT INTO contacts (added_by, name, relationship, avatar_initial) VALUES (?, ?, ?, ?)',
    [userId, target.name, 'household', String(target.name || '?').slice(0, 1).toUpperCase()]);
  return ins.lastID;
}

// Promisified write against the shared connection.
function dbRun(db, sql, params = []) {
  return new Promise((resolve, reject) => {
    db.db.run(sql, params, function (err) { err ? reject(err) : resolve(this); });
  });
}

// Promisified single-row read against the shared connection.
function dbGet(db, sql, params = []) {
  return new Promise((resolve, reject) => {
    db.db.get(sql, params, (err, row) => err ? reject(err) : resolve(row));
  });
}

// Companion to dbGet for the handful of small, targeted UPDATEs that don't
// warrant a FamilyDB method of their own.
function dbRun(db, sql, params = []) {
  return new Promise((resolve, reject) => {
    db.db.run(sql, params, function (err) { err ? reject(err) : resolve(this); });
  });
}

// Authorization guard for household-scoped `:id` routes. Confirms the row in
// `table` belongs to the caller's household before the handler mutates/reads it.
// Sends 404 (missing) or 403 (other household) and returns false on failure.
// Strict: the caller must have a household and the row must match it exactly.
// (The startup backfill sweeps any legacy NULL group_id, so NULL is anomalous
// and denied rather than allowed — preventing a null-row cross-household hole.)
async function requireHouseholdRow(db, table, id, req, res) {
  const userId = req.session.user?.id;
  const row = await dbGet(db, `SELECT group_id FROM ${table} WHERE id = ?`, [id]);
  if (!row) { res.status(404).json({ error: 'Not found' }); return false; }
  // Accept the row if its group is ANY household the caller belongs to (a user may
  // be in more than one — shared-custody teens), and reject clans/other households.
  if (row.group_id == null || !(await db.isHouseholdMember(row.group_id, userId))) {
    res.status(403).json({ error: 'Forbidden' }); return false;
  }
  return true;
}

// Authorization guard for feed routes keyed by post id: the caller must belong
// to the group that owns the post. Sends 404/403 and returns false on failure.
async function requireFeedPostMember(db, postId, req, res) {
  const post = await dbGet(db, 'SELECT group_id FROM feed_posts WHERE id = ?', [postId]);
  if (!post) { res.status(404).json({ error: 'Not found' }); return false; }
  if (!(await db.isGroupMember(post.group_id, req.session.user?.id))) {
    res.status(403).json({ error: 'Not a member of this group' }); return false;
  }
  return true;
}

// Authorization guard for CLAN-SHAREABLE rows (decisions, rivalries) keyed by id:
// the caller must be a member of the row's group. Unlike requireHouseholdRow this
// accepts ANY group the caller belongs to (a clan, not just their household), so
// content shared to a clan is editable by that clan's members — and no one else.
const GROUP_ROW_TABLES = new Set(['decisions', 'rivalries']);
async function requireGroupRow(db, table, id, req, res) {
  if (!GROUP_ROW_TABLES.has(table)) throw new Error(`requireGroupRow: unsupported table ${table}`);
  const row = await dbGet(db, `SELECT group_id FROM ${table} WHERE id = ?`, [id]);
  if (!row) { res.status(404).json({ error: 'Not found' }); return false; }
  if (row.group_id == null || !(await db.isGroupMember(row.group_id, req.session.user?.id))) {
    res.status(403).json({ error: 'Forbidden' }); return false;
  }
  return true;
}

// Authorization guard for destructive/membership group ops. Households are small
// trusted units (partners co-manage), so any household member may manage. Clans
// can be large/loose, so adding/removing members, renaming, or deleting requires
// ADMIN — this is what stops a clan member quietly adding an outsider (who would
// then see the whole clan's content) or kicking the owner.
async function requireGroupManage(db, groupId, req, res) {
  const userId = req.session.user?.id;
  const g = await dbGet(db, 'SELECT group_type FROM groups WHERE id = ?', [groupId]);
  if (!g) { res.status(404).json({ error: 'Group not found' }); return false; }
  const ok = g.group_type === 'household'
    ? await db.isGroupMember(groupId, userId)
    : await db.isGroupAdmin(groupId, userId);
  if (!ok) {
    res.status(403).json({ error: g.group_type === 'household' ? 'Not a member of this household' : 'Admin privileges required for this group' });
    return false;
  }
  return true;
}

// Site-admin gate for /api/admin/* (global, cross-household diagnostics + repair).
// Allowed user ids come from ADMIN_USER_IDS (comma-separated). If unset, NO ONE
// is an admin — the endpoints fail closed rather than leaking every household.
function requireAdmin(req, res, next) {
  const allowed = (process.env.ADMIN_USER_IDS || '').split(',').map(s => s.trim()).filter(Boolean);
  const uid = req.session.user?.id;
  if (uid != null && allowed.includes(String(uid))) return next();
  return res.status(403).json({ error: 'Forbidden' });
}

// Resolve the group_id a new row should be tagged with. If the client supplied
// one, the caller MUST be a member of it (and for household-only features it must
// be a household) — this blocks injecting content into a clan/household the
// caller doesn't belong to. With no supplied id, default to the primary
// household. Returns the resolved id, or null if the supplied group is not
// permitted (caller should respond 403).
async function resolveCreateGroupId(db, userId, requested, { householdOnly = false } = {}) {
  if (requested == null || requested === '') return await db.getUserHouseholdId(userId);
  const gid = parseInt(requested);
  if (!Number.isInteger(gid) || !(await db.isGroupMember(gid, userId))) return null;
  if (householdOnly) {
    const g = await dbGet(db, 'SELECT group_type FROM groups WHERE id = ?', [gid]);
    if (!g || g.group_type !== 'household') return null;
  }
  return gid;
}

// Does this person (people registry / gift_people row) belong to the caller's
// own household? Used to validate person tags on decisions and milestones —
// people are household-scoped even when the tagged item is shared to a clan.
async function personBelongsToCallerHousehold(db, userId, personId) {
  const pid = parseInt(personId);
  if (!Number.isInteger(pid)) return false;
  const hid = await db.getUserHouseholdId(userId);
  if (!hid) return false;
  const row = await dbGet(db, 'SELECT id FROM gift_people WHERE id = ? AND group_id = ?', [pid, hid]);
  return !!row;
}

// May the caller view this user's avatar? Only if they share a household or any
// group (so a clan member sees clan co-members, but strangers don't), or it's
// themselves. Mirrors the per-membership visibility model.
async function canViewUser(db, targetId, viewerId) {
  if (parseInt(targetId) === parseInt(viewerId)) return true;
  const row = await dbGet(db, `SELECT 1 AS ok FROM group_members a
    JOIN group_members b ON a.group_id = b.group_id
    WHERE a.user_id = ? AND b.user_id = ? LIMIT 1`, [viewerId, targetId]);
  return !!row;
}

// Authorization guard for list `:id` routes. A list is visible to its creator
// and to members of the creator's household (mirrors getLists scoping).
async function requireListAccess(db, listId, req, res) {
  const userId = req.session.user?.id;
  const list = await dbGet(db, 'SELECT created_by FROM lists WHERE id = ?', [listId]);
  if (!list) { res.status(404).json({ error: 'Not found' }); return false; }
  if (list.created_by === userId) return true;
  const shared = await dbGet(db, `SELECT 1 AS ok FROM group_members gm2
    JOIN groups g ON g.id = gm2.group_id AND g.group_type = 'household'
    WHERE gm2.user_id = ? AND gm2.group_id IN (SELECT group_id FROM group_members WHERE user_id = ?)`,
    [list.created_by, userId]);
  if (!shared) { res.status(403).json({ error: 'Forbidden' }); return false; }
  return true;
}

// Same, keyed by a list_item id (resolves the parent list first).
async function requireListItemAccess(db, itemId, req, res) {
  const item = await dbGet(db, 'SELECT list_id FROM list_items WHERE id = ?', [itemId]);
  if (!item) { res.status(404).json({ error: 'Not found' }); return false; }
  return requireListAccess(db, item.list_id, req, res);
}

// Authorization guard for itinerary `:id` routes: caller must be the traveler
// or a member of the itinerary's group. Mirrors the inline check on /stays.
async function requireItineraryAccess(db, id, req, res) {
  const itinerary = await db.getItineraryById(id);
  if (!itinerary) { res.status(404).json({ error: 'Not found' }); return false; }
  const userId = req.session.user?.id;
  if (itinerary.traveler_id === userId) return true;
  const groups = await new Promise((resolve, reject) => {
    db.db.all('SELECT group_id FROM group_members WHERE user_id = ?', [userId], (err, rows) => err ? reject(err) : resolve(rows || []));
  });
  const groupIds = groups.map(g => g.group_id);
  if (!itinerary.group_id || !groupIds.includes(itinerary.group_id)) {
    res.status(403).json({ error: 'Forbidden' }); return false;
  }
  return true;
}

// Can the caller attach this entity to an event? Mirrors each entity's own read
// scoping so a user can't link (and thereby reveal the title of) something they
// can't already see. Returns true/false; does NOT write a response.
async function canAttachEntity(db, type, id, userId) {
  if (type === 'list') {
    // Visible to creator or to members of the creator's household(s).
    const row = await dbGet(db, `SELECT 1 AS ok FROM lists l WHERE l.id = ? AND (
        l.created_by = ?
        OR EXISTS (SELECT 1 FROM group_members gm JOIN groups g ON g.id = gm.group_id
                   AND g.group_type = 'household'
                   WHERE gm.user_id = l.created_by AND gm.group_id IN (
                     SELECT group_id FROM group_members WHERE user_id = ?)))`,
      [id, userId, userId]);
    return !!row;
  }
  if (type === 'note') {
    // Owner, or shared (household/group) to a group the caller belongs to.
    const row = await dbGet(db, `SELECT 1 AS ok FROM notes n WHERE n.id = ? AND (
        n.user_id = ?
        OR (n.shared_scope != 'private' AND n.group_id IN (SELECT group_id FROM group_members WHERE user_id = ?)))`,
      [id, userId, userId]);
    return !!row;
  }
  // decision | receipt | trip | itinerary: the caller must be a member of the
  // row's group (a household OR a clan it was shared to — multi-household safe).
  const tables = { decision: 'decisions', receipt: 'receipts', trip: 'trips', itinerary: 'itineraries', task: 'tasks' };
  const table = tables[type];
  if (!table) return false;
  const row = await dbGet(db, `SELECT group_id FROM ${table} WHERE id = ?`, [id]);
  if (!row || row.group_id == null) return false;
  return await db.isGroupMember(row.group_id, userId);
}

// Premium gate: requires an active household subscription. Returns 402 otherwise.
async function requirePremium(req, res, next) {
  const db = new FamilyDB();
  try {
    if (await subscription.isHouseholdPremium(db, req.session.user.id)) {
      next();
    } else {
      res.status(402).json({ error: 'Premium required', premium: false });
    }
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
}

// JSON API registration
app.post('/api/auth/register', registerLimiter, async (req, res) => {
  const db = new FamilyDB();
  try {
    const { username, password, name, invite_code } = req.body;
    if (!username || !password || !name) {
      return res.status(400).json({ error: 'Username, password, and name are required' });
    }
    // Email is optional at signup. It seeds the onboarding drip and can later
    // be verified via the account-email flow to become the 2FA destination.
    let signupEmail = null;
    if (req.body.email != null && String(req.body.email).trim() !== '') {
      signupEmail = String(req.body.email).trim().toLowerCase();
      if (signupEmail.length > 254 || !EMAIL_RE.test(signupEmail)) {
        return res.status(400).json({ error: 'Please enter a valid email address' });
      }
    }
    if (typeof password !== 'string' || password.length < 8) {
      return res.status(400).json({ error: 'Password must be at least 8 characters' });
    }
    // bcrypt silently truncates beyond 72 bytes — reject rather than pretend.
    if (Buffer.byteLength(password, 'utf8') > 72) {
      return res.status(400).json({ error: 'Password must be at most 72 characters' });
    }
    if (password === username) {
      return res.status(400).json({ error: 'Password must not equal the username' });
    }

    // Check if username exists
    const existing = await db.getUserByUsername(username);
    if (existing) {
      return res.status(409).json({ error: 'Username already taken' });
    }

    const inviteCode = invite_code != null ? String(invite_code).trim() : '';
    if (inviteCode && !(await db.getGroupByInviteCode(inviteCode.toUpperCase()))) {
      return res.status(400).json({ error: "That invite code isn't valid" });
    }

    // Hash password and create user
    const password_hash = await bcrypt.hash(password, 12);
    const user = await db.createUser({ username, password_hash, name, email: signupEmail });

    const household = await assignHousehold(db, { id: user.id, name }, {
      invite_code: inviteCode,
      household_name: req.body.household_name,
    });

    // Set session (regenerated to avoid fixation)
    await establishSession(req, { username, name: user.name, id: user.id });
    const refresh_token = await issueAuthToken(db, user.id, req.body.device_name);
    res.json({
      success: true,
      user: { id: user.id, username, name, avatar: null },
      household: { id: household.id, invite_code: household.invite_code },
      refresh_token
    });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Sign in with Apple — native identity token. Apple already did 2FA; we
// establish a session immediately (no email OTP). Replay is blocked by nonce.
app.post('/api/auth/apple', loginLimiter, async (req, res) => {
  const db = new FamilyDB();
  try {
    const identityToken = req.body.identity_token;
    const nonce = req.body.nonce;
    let claims;
    try {
      claims = await appleSignIn.verifyIdentityToken(identityToken, { nonce });
    } catch (err) {
      const clientErrors = new Set([
        'invalid_token', 'bad_iss', 'bad_aud', 'bad_sub', 'expired',
        'not_yet_valid', 'nonce_required', 'bad_nonce', 'bad_alg',
        'unknown_kid', 'bad_signature',
      ]);
      if (clientErrors.has(err.message)) {
        return res.status(401).json({ error: 'Apple sign-in could not be verified' });
      }
      throw err;
    }

    const inviteCode = req.body.invite_code != null ? String(req.body.invite_code).trim() : '';
    if (inviteCode && !(await db.getGroupByInviteCode(inviteCode.toUpperCase()))) {
      return res.status(400).json({ error: "That invite code isn't valid" });
    }

    let user = await db.getUserByAppleId(claims.sub);
    let household = null;
    let isNew = false;

    if (!user && claims.email && claims.emailVerified) {
      const linked = await db.getUserByVerifiedEmail(claims.email);
      if (linked) {
        await db.linkAppleUserId(linked.id, claims.sub, {
          email: claims.email,
          markEmailVerified: true,
        });
        user = await db.getUserById(linked.id);
      }
    }

    if (!user) {
      isNew = true;
      const displayName = sanitizeDisplayName(req.body.name);
      const username = await uniqueAppleUsername(db, claims.sub);
      const password_hash = await bcrypt.hash(crypto.randomBytes(32).toString('hex'), 12);
      const created = await db.createUser({
        username,
        password_hash,
        name: displayName,
        email: claims.email,
        apple_user_id: claims.sub,
        email_verified: !!(claims.email && claims.emailVerified),
        password_login: 0,
      });
      user = { id: created.id, username: created.username, name: created.name, avatar: null };
      household = await assignHousehold(db, user, {
        invite_code: inviteCode,
        household_name: req.body.household_name,
      });
    }

    const sessionUser = await db.getUserById(user.id);
    await establishSession(req, { username: sessionUser.username, name: sessionUser.name, id: sessionUser.id });
    const refresh_token = await issueAuthToken(db, sessionUser.id, req.body.device_name);

    if (!household) {
      const groups = await db.getGroupsByUser(sessionUser.id);
      const hh = (groups || []).find((g) => g.group_type === 'household') || (groups || [])[0];
      household = hh ? { id: hh.id, invite_code: hh.invite_code } : null;
    }

    res.json({
      success: true,
      user: jsonUser(sessionUser),
      household,
      refresh_token,
      created: isNew,
    });
  } catch (err) {
    if (err.status === 400 && err.message === 'invite_not_found') {
      return res.status(400).json({ error: "That invite code isn't valid" });
    }
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// JSON API login — database-backed bcrypt auth only.
app.post('/api/auth/login', loginLimiter, async (req, res) => {
  const db = new FamilyDB();
  try {
    const { username, password } = req.body;

    const dbUser = await db.getUserByUsername(username);
    // Always run a bcrypt compare (against a dummy hash when the user is absent)
    // so response time doesn't reveal whether a username exists.
    const hash = dbUser?.password_hash || DUMMY_BCRYPT_HASH;
    const valid = await bcrypt.compare(String(password || ''), hash);

    if (!dbUser || !valid) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    // Password OK. With 2FA off, establish the session immediately.
    if (!TWO_FA_ENABLED) {
      await establishSession(req, { username: dbUser.username, name: dbUser.name, id: dbUser.id });
      const refresh_token = await issueAuthToken(db, dbUser.id, req.body.device_name);
      return res.json({ success: true, refresh_token, user: { id: dbUser.id, username: dbUser.username, name: dbUser.name, avatar: dbUser.avatar } });
    }

    // 2FA required. Issue a challenge; NO session yet. If the user already has a
    // verified email, send the code now; otherwise they must enroll an email.
    const token = crypto.randomBytes(32).toString('hex');
    if (dbUser.email && dbUser.email_verified) {
      const code = genCode();
      await db.createLoginChallenge({ token, userId: dbUser.id, status: 'code_sent', codeHash: hashCode(code), expiresAt: challengeExpiry() });
      const sent = await sendLoginCode(dbUser.email, code);
      return res.json({ two_factor_required: true, challenge: token, status: 'code_sent', email_hint: maskEmail(dbUser.email), email_sent: sent.ok !== false, ...echoCode(code) });
    }
    await db.createLoginChallenge({ token, userId: dbUser.id, status: 'enroll_email', expiresAt: challengeExpiry() });
    return res.json({ two_factor_required: true, challenge: token, status: 'enroll_email' });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Step 2a (first-time enrollment): set the email a login code should go to.
app.post('/api/auth/login/email', loginLimiter, async (req, res) => {
  const db = new FamilyDB();
  try {
    const { challenge, email: addr } = req.body;
    const ch = challenge && await db.getLoginChallenge(challenge);
    if (!ch || ch.consumed || challengeExpired(ch) || ch.status !== 'enroll_email') {
      return res.status(400).json({ error: 'This sign-in attempt expired. Please start again.' });
    }
    if (typeof addr !== 'string' || !EMAIL_RE.test(addr.trim())) {
      return res.status(400).json({ error: 'Please enter a valid email address' });
    }
    const clean = addr.trim().toLowerCase();
    await db.setUserEmail(ch.user_id, clean);
    const code = genCode();
    await db.updateLoginChallengeCode(challenge, { codeHash: hashCode(code), status: 'code_sent', expiresAt: challengeExpiry() });
    const sent = await sendLoginCode(clean, code);
    res.json({ status: 'code_sent', email_hint: maskEmail(clean), email_sent: sent.ok !== false, ...echoCode(code) });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Step 2b: verify the emailed code and establish the session.
app.post('/api/auth/login/verify', loginLimiter, async (req, res) => {
  const db = new FamilyDB();
  try {
    const { challenge, code } = req.body;
    const ch = challenge && await db.getLoginChallenge(challenge);
    if (!ch || ch.consumed || ch.status !== 'code_sent' || challengeExpired(ch)) {
      return res.status(400).json({ error: 'This code expired. Please request a new one.' });
    }
    if (ch.attempts >= TWO_FA_MAX_ATTEMPTS) {
      await db.consumeLoginChallenge(challenge);
      return res.status(429).json({ error: 'Too many attempts. Please sign in again.' });
    }
    if (!codeMatches(String(code || ''), ch.code_hash)) {
      await db.incrementLoginChallengeAttempts(challenge);
      return res.status(401).json({ error: 'Incorrect code' });
    }
    await db.consumeLoginChallenge(challenge);
    await db.markEmailVerifiedAndEnable(ch.user_id);
    const user = await db.getUserById(ch.user_id);
    await establishSession(req, { username: user.username, name: user.name, id: user.id });
    const refresh_token = await issueAuthToken(db, user.id, req.body.device_name);
    res.json({ success: true, refresh_token, user: { id: user.id, username: user.username, name: user.name, avatar: user.avatar } });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Resend a fresh code for an in-flight challenge.
app.post('/api/auth/login/resend', loginLimiter, async (req, res) => {
  const db = new FamilyDB();
  try {
    const { challenge } = req.body;
    const ch = challenge && await db.getLoginChallenge(challenge);
    if (!ch || ch.consumed || ch.status !== 'code_sent') {
      return res.status(400).json({ error: 'Nothing to resend. Please start again.' });
    }
    const user = await db.getUserById(ch.user_id);
    if (!user?.email) return res.status(400).json({ error: 'No email on file' });
    const code = genCode();
    await db.updateLoginChallengeCode(challenge, { codeHash: hashCode(code), status: 'code_sent', expiresAt: challengeExpiry() });
    const sent = await sendLoginCode(user.email, code);
    res.json({ ok: true, email_hint: maskEmail(user.email), email_sent: sent.ok !== false, ...echoCode(code) });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Silent re-login with a device refresh token (no password on device).
// Bypasses 2FA by design: the token was earned by a full (2FA-complete) login
// on this device. Rotates the token on every success.
app.post('/api/auth/token-login', loginLimiter, async (req, res) => {
  const db = new FamilyDB();
  try {
    const { refresh_token } = req.body;
    if (typeof refresh_token !== 'string' || refresh_token.length < 32) {
      return res.status(400).json({ error: 'refresh_token required' });
    }
    // Live tokens are usable; so is a token ROTATED within the grace window
    // (revoked=1 with a recent last_used_at — logout/change-password revoke
    // without touching last_used_at, so those get no grace). Without grace,
    // a lost rotation response would strand the device: the server rotated
    // but the client never received the replacement.
    const row = await dbGet(db, `SELECT *,
        (revoked = 0 OR (last_used_at IS NOT NULL
          AND last_used_at > datetime('now', ?))) AS usable
      FROM auth_tokens WHERE token_hash = ?`,
      [`-${AUTH_TOKEN_GRACE_SECONDS} seconds`, hashAuthToken(refresh_token)]);
    const user = row?.usable ? await db.getUserById(row.user_id) : null;
    if (!user) {
      return res.status(401).json({ error: 'Invalid token' });
    }
    // Rotate before answering: the presented token dies (after grace), a
    // fresh one replaces it.
    await dbRun(db, 'UPDATE auth_tokens SET revoked = 1, last_used_at = CURRENT_TIMESTAMP WHERE id = ?', [row.id]);
    const fresh = await issueAuthToken(db, user.id, row.device_name);
    await establishSession(req, { username: user.username, name: user.name, id: user.id });
    res.json({ success: true, refresh_token: fresh, user: { id: user.id, username: user.username, name: user.name, avatar: user.avatar } });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Logout: revoke the presented device token and destroy the session.
app.post('/api/auth/logout', async (req, res) => {
  const db = new FamilyDB();
  try {
    const { refresh_token, device_token } = req.body || {};
    if (typeof refresh_token === 'string' && refresh_token.length >= 32) {
      // Hard delete: a logged-out token gets no grace window and no tombstone.
      await dbRun(db, 'DELETE FROM auth_tokens WHERE token_hash = ?', [hashAuthToken(refresh_token)]);
    }
    // Stop pushing to this device — a shared/resold phone must not keep
    // receiving the household's messages and nudges.
    if (typeof device_token === 'string' && device_token) {
      await db.removeDeviceToken(device_token).catch(() => {});
    }
    req.session.destroy(() => res.json({ success: true }));
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Change the authenticated user's password. Requires the current password.
// Permanently delete the signed-in user's account and personal data.
// Re-authentication is required — password and/or a fresh Sign in with Apple
// identity token (Guideline 5.1.1(v); Apple-only accounts have no password).
app.post('/api/account/delete', requireAuth, loginLimiter, async (req, res) => {
  const db = new FamilyDB();
  try {
    const user = await db.getUserById(req.session.user.id);
    const full = user && await db.getUserByUsername(user.username);
    if (!full) return res.status(401).json({ error: 'Not authenticated' });

    const hasPassword = full.password_login !== 0 && full.password_login !== '0';
    const appleLinked = !!full.apple_user_id;
    let passwordOk = false;
    let appleOk = false;

    if (hasPassword && req.body.current_password) {
      passwordOk = await bcrypt.compare(String(req.body.current_password), full.password_hash || DUMMY_BCRYPT_HASH);
    } else if (hasPassword) {
      // Keep a dummy compare on the password path so timing doesn't advertise
      // whether this account has a password when the client omitted one.
      await bcrypt.compare('', full.password_hash || DUMMY_BCRYPT_HASH);
    }

    if (appleLinked && req.body.identity_token) {
      try {
        const claims = await appleSignIn.verifyIdentityToken(req.body.identity_token, {
          nonce: req.body.nonce,
        });
        appleOk = claims.sub === full.apple_user_id;
      } catch {
        appleOk = false;
      }
    }

    if (!passwordOk && !appleOk) {
      const hint = appleLinked && !hasPassword
        ? 'Sign in with Apple to confirm'
        : 'Password is incorrect';
      return res.status(401).json({ error: hint });
    }

    await db.deleteUserAccount(req.session.user.id);
    req.session.destroy(() => res.json({ success: true }));
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Report household UGC (Guideline 1.2). The reporter must already be able to
// see the target — DMs they sent or received, or a feed post in a group they
// belong to. Does not attach the original body to the operator email.
app.post('/api/content/report', requireAuth, reportLimiter, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user.id;
    const type = String(req.body.content_type || req.body.type || '').trim();
    const refId = parseInt(req.body.ref_id, 10);
    const reason = String(req.body.reason || '').trim().slice(0, 200);
    if (!['message', 'feed'].includes(type) || !Number.isInteger(refId) || refId < 1) {
      return res.status(400).json({ error: 'Nothing to report' });
    }
    if (!reason) return res.status(400).json({ error: 'Please choose a reason' });

    if (type === 'message') {
      const row = await dbGet(db, 'SELECT sender_id, recipient_id FROM direct_messages WHERE id = ?', [refId]);
      if (!row) return res.status(404).json({ error: 'Not found' });
      if (row.sender_id !== userId && row.recipient_id !== userId) {
        return res.status(403).json({ error: 'Forbidden' });
      }
    } else {
      const post = await dbGet(db, 'SELECT group_id FROM feed_posts WHERE id = ?', [refId]);
      if (!post) return res.status(404).json({ error: 'Not found' });
      if (post.group_id == null || !(await db.isGroupMember(post.group_id, userId))) {
        return res.status(403).json({ error: 'Forbidden' });
      }
    }

    await dbRun(db, 'INSERT INTO content_reports (reporter_id, content_type, ref_id, reason) VALUES (?, ?, ?, ?)',
      [userId, type, refId, reason]);

    const to = process.env.REPORTS_TO || 'kinrows@atlasatlantic.co';
    email.sendEmail({
      to,
      subject: `Kinrows content report (${type} #${refId})`,
      text: `Reporter user id ${userId} reported ${type} ${refId}. Reason: ${reason}`,
      html: `<p>Reporter user id ${userId} reported <code>${type}</code> ${refId}.</p><p>Reason: ${email.escapeHtml(reason)}</p>`,
    }).catch(() => {});

    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.post('/api/auth/change-password', requireAuth, loginLimiter, async (req, res) => {
  const db = new FamilyDB();
  try {
    const { current_password, new_password } = req.body;
    if (typeof new_password !== 'string' || new_password.length < 8) {
      return res.status(400).json({ error: 'New password must be at least 8 characters' });
    }
    if (Buffer.byteLength(new_password, 'utf8') > 72) {
      return res.status(400).json({ error: 'New password must be at most 72 characters' });
    }
    const user = await db.getUserById(req.session.user.id);
    const full = await db.getUserByUsername(user.username);
    const valid = await bcrypt.compare(String(current_password || ''), full?.password_hash || DUMMY_BCRYPT_HASH);
    if (!valid) return res.status(401).json({ error: 'Current password is incorrect' });
    if (new_password === user.username) {
      return res.status(400).json({ error: 'Password must not equal the username' });
    }
    const password_hash = await bcrypt.hash(new_password, 12);
    await db.updateUserPassword(req.session.user.id, password_hash);
    // Password change = sign out every other device: hard-delete all
    // outstanding tokens (no grace), then hand THIS device a fresh one.
    await dbRun(db, 'DELETE FROM auth_tokens WHERE user_id = ?', [req.session.user.id]);
    const refresh_token = await issueAuthToken(db, req.session.user.id, req.body.device_name);
    res.json({ success: true, refresh_token });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Security status for the Settings screen.
app.get('/api/account/security', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const user = await db.getUserByUsername(req.session.user.username);
    res.json({
      email: user?.email || null,
      email_verified: !!user?.email_verified,
      two_factor_enabled: !!user?.two_factor_enabled,
      has_password: user?.password_login !== 0 && user?.password_login !== '0',
      apple_linked: !!user?.apple_user_id,
    });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Change/confirm the account email (authed). Sends a verification code; the new
// address only becomes the 2FA destination once verified.
app.post('/api/account/email', requireAuth, loginLimiter, async (req, res) => {
  const db = new FamilyDB();
  try {
    const addr = String(req.body.email || '').trim().toLowerCase();
    if (!EMAIL_RE.test(addr)) return res.status(400).json({ error: 'Please enter a valid email address' });
    const userId = req.session.user.id;
    await db.setUserEmail(userId, addr);
    const token = crypto.randomBytes(32).toString('hex');
    const code = genCode();
    await db.createLoginChallenge({ token, userId, status: 'code_sent', codeHash: hashCode(code), expiresAt: challengeExpiry() });
    const sent = await sendLoginCode(addr, code);
    res.json({ challenge: token, email_hint: maskEmail(addr), email_sent: sent.ok !== false, ...echoCode(code) });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.post('/api/account/email/verify', requireAuth, loginLimiter, async (req, res) => {
  const db = new FamilyDB();
  try {
    const { challenge, code } = req.body;
    const ch = challenge && await db.getLoginChallenge(challenge);
    if (!ch || ch.consumed || ch.status !== 'code_sent' || challengeExpired(ch) || ch.user_id !== req.session.user.id) {
      return res.status(400).json({ error: 'This code expired. Please request a new one.' });
    }
    if (ch.attempts >= TWO_FA_MAX_ATTEMPTS) {
      await db.consumeLoginChallenge(challenge);
      return res.status(429).json({ error: 'Too many attempts. Please try again.' });
    }
    if (!codeMatches(String(code || ''), ch.code_hash)) {
      await db.incrementLoginChallengeAttempts(challenge);
      return res.status(401).json({ error: 'Incorrect code' });
    }
    await db.consumeLoginChallenge(challenge);
    await db.markEmailVerifiedAndEnable(req.session.user.id);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Register device token for push notifications
app.post('/api/auth/device-token', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const { token } = req.body;
    if (!token) return res.status(400).json({ error: 'Token required' });
    await db.saveDeviceToken(req.session.user.id, token);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// ── Public marketing waitlist (kinrows.com) ──────────────────────────────────
const waitlistLimiter = createRateLimiter({ windowMs: 60000, max: 8, keyFn: clientIp });
const householdInviteLimiter = createRateLimiter({
  windowMs: 60 * 60 * 1000,
  max: 10,
  keyFn: req => req.session?.user?.id ?? clientIp(req),
});
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

app.post('/api/waitlist', waitlistLimiter, async (req, res) => {
  const db = new FamilyDB();
  try {
    const raw = typeof req.body?.email === 'string' ? req.body.email.trim().toLowerCase() : '';
    if (!raw || raw.length > 254 || !EMAIL_RE.test(raw)) {
      return res.status(400).json({ error: 'Please enter a valid email.' });
    }

    const refInput = typeof req.body?.ref === 'string' ? req.body.ref.trim().slice(0, 20) : null;
    const { created, total, ref_code, position, referrals } = await db.addWaitlistEntry({
      email: raw,
      source: typeof req.body?.source === 'string' ? req.body.source.slice(0, 80) : 'site',
      referrer: (req.get('referer') || '').slice(0, 300) || null,
      user_agent: (req.get('user-agent') || '').slice(0, 300) || null,
      ref: /^[a-f0-9]{6,20}$/.test(refInput || '') ? refInput : null,
    });

    // Respond immediately; email send is best-effort and must not block/fail the signup.
    res.json({ success: true, already: !created, ref_code, position, referrals, total });

    if (created && email.isEmailEnabled()) {
      try {
        await jobs.enqueueWaitlist(db, {
          email: raw,
          total,
          notify: Boolean(email.emailConfig.notify),
        });
      } catch (e) {
        console.error('[waitlist] enqueue failed:', e?.message || e);
      }
    } else if (created) {
      // Don't log the raw email — note the domain only.
      const domain = String(raw || '').split('@')[1] || 'unknown';
      console.warn(`[waitlist] new signup but email disabled (no RESEND_API_KEY): @${domain}`);
    }
  } catch (err) {
    if (!res.headersSent) res.status(500).json({ error: 'Something went wrong. Please try again.' });
    console.error('[waitlist] error:', err.message);
  } finally {
    db.close();
  }
});

// Refresh a signup's referral standing (position + referrals) when they return
// via their share link — so the count reflects friends who joined since.
app.get('/api/waitlist/status', waitlistLimiter, async (req, res) => {
  const db = new FamilyDB();
  try {
    const code = typeof req.query.ref_code === 'string' ? req.query.ref_code.trim() : '';
    if (!/^[a-f0-9]{6,20}$/.test(code)) return res.status(400).json({ error: 'Invalid code' });
    const standing = await db.getWaitlistStanding(code);
    if (!standing.position) return res.status(404).json({ error: 'Not found' });
    res.json({ success: true, ...standing });
  } catch (err) {
    if (!res.headersSent) res.status(500).json({ error: 'Something went wrong.' });
  } finally {
    db.close();
  }
});

// ── Onboarding email unsubscribe (public, token-based) ───────────────────────
// GET renders a tiny confirmation page (the footer link in every onboarding
// email); POST is the RFC 8058 one-click endpoint mail clients hit for the
// List-Unsubscribe header. Both are idempotent; unknown tokens still say
// "done" so the endpoint can't be used to probe which tokens exist.
const unsubscribeLimiter = createRateLimiter({ windowMs: 60000, max: 10, keyFn: clientIp });

async function handleUnsubscribe(token) {
  const db = new FamilyDB();
  try {
    await db.setEmailOptOutByToken(token);
  } finally {
    db.close();
  }
}

app.get('/api/email/unsubscribe', unsubscribeLimiter, async (req, res) => {
  try {
    await handleUnsubscribe(req.query.token);
    res.type('html').send(`<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>Unsubscribed — Kinrows</title>
<style>body{margin:0;background:#fdf5e0;font-family:'Helvetica Neue',Arial,sans-serif;color:#2c2017;display:flex;min-height:100vh;align-items:center;justify-content:center}
.card{background:#fffaf0;border-radius:20px;padding:44px 40px;max-width:420px;margin:16px;text-align:center;box-shadow:0 1px 0 #ece0c8}
h1{font-family:Georgia,serif;font-size:28px;margin:0 0 12px}p{color:#5c4a3a;line-height:1.6;margin:0}</style></head>
<body><div class="card"><h1>You're unsubscribed.</h1>
<p>No more getting-started emails from Kinrows. Account and security emails (like sign-in codes) still reach you.</p></div></body></html>`);
  } catch (err) {
    sendServerError(res, err);
  }
});

app.post('/api/email/unsubscribe', unsubscribeLimiter, async (req, res) => {
  try {
    await handleUnsubscribe(req.query.token || req.body?.token);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  }
});

// Update work address for a user
app.put('/api/users/:id/work-address', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (parseInt(req.params.id) !== req.session.user?.id) {
      return res.status(403).json({ error: 'Forbidden' });
    }
    await db.updateUserWorkAddress(parseInt(req.params.id), req.body);
    res.json({ success: true });
  } catch (err) { sendServerError(res, err); }
  finally { db.close(); }
});

// Get work address for a user (own only)
app.get('/api/users/:id/work-address', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (parseInt(req.params.id) !== req.session.user?.id) {
      return res.status(403).json({ error: 'Forbidden' });
    }
    const data = await db.getUserWorkAddress(parseInt(req.params.id));
    res.json(data || {});
  } catch (err) { sendServerError(res, err); }
  finally { db.close(); }
});

// Report current location
app.post('/api/location', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user.id;
    const { lat, lng } = req.body;

    // Check against saved addresses to determine location name
    const groupId = await db.getUserHouseholdId(userId);
    const addresses = await db.getFamilyAddresses(groupId);
    const user = await db.getUserById(userId);
    let locationName = null;

    // Check home addresses
    for (const addr of addresses) {
      const dist = haversineDistance(lat, lng, addr.lat, addr.lng);
      if (dist <= (addr.radius_meters || 500)) {
        locationName = addr.name;
        break;
      }
    }

    // Check work address
    if (!locationName && user?.work_lat && user?.work_lng) {
      const dist = haversineDistance(lat, lng, user.work_lat, user.work_lng);
      if (dist <= 500) {
        locationName = 'Work';
      }
    }

    await db.updateUserLocation(userId, { lat, lng, location_name: locationName });
    res.json({ success: true, location_name: locationName });
  } catch (err) { sendServerError(res, err); }
  finally { db.close(); }
});

// Get household presence (all members' locations)
app.get('/api/household/presence', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const presence = await db.getHouseholdPresence(req.session.user.id);
    res.json(presence);
  } catch (err) { sendServerError(res, err); }
  finally { db.close(); }
});

// Get current user profile
app.get('/api/auth/me', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    if (!userId) return res.json({ user: req.session.user, groups: [] });
    const user = await db.getUserById(userId);
    const groups = await db.getGroupsByUser(userId);
    res.json({ user, groups });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Profile image upload
app.put('/api/users/me/avatar', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    if (!userId) return res.status(401).json({ error: 'Not authenticated' });
    const { image } = req.body;
    if (!image) return res.status(400).json({ error: 'No image provided' });
    await new Promise((resolve, reject) => {
      db.db.run('UPDATE users SET profile_image = ? WHERE id = ?', [image, userId], (err) => err ? reject(err) : resolve());
    });
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Update own display name
app.put('/api/users/me/name', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    if (!userId) return res.status(401).json({ error: 'Not authenticated' });
    const name = (req.body?.name || '').trim();
    if (!name) return res.status(400).json({ error: 'Name is required' });
    if (name.length > 60) return res.status(400).json({ error: 'Name is too long' });
    await new Promise((resolve, reject) => {
      db.db.run('UPDATE users SET name = ? WHERE id = ?', [name, userId], (err) => err ? reject(err) : resolve());
    });
    if (req.session.user) req.session.user.name = name;
    res.json({ success: true, name });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Opt in/out of the AI Concierge. The daily brief is posted to the household
// feed for opted-in members; the iOS toggle is the source of truth.
app.put('/api/users/me/concierge', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    if (!userId) return res.status(401).json({ error: 'Not authenticated' });
    const enabled = !!(req.body && req.body.enabled);
    await db.setConciergeEnabled(userId, enabled);
    res.json({ success: true, enabled });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Profile image for any user
app.get('/api/users/:id/avatar', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const targetId = parseInt(req.params.id);
    if (!(await canViewUser(db, targetId, req.session.user?.id))) {
      return res.status(403).json({ error: 'Forbidden' });
    }
    const row = await new Promise((resolve, reject) => {
      db.db.get('SELECT profile_image FROM users WHERE id = ?', [targetId], (err, row) => err ? reject(err) : resolve(row));
    });
    if (!row?.profile_image) return res.status(404).json({ error: 'No avatar' });
    if (!sendStoredImage(req, res, row.profile_image)) return res.status(404).json({ error: 'No avatar' });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Group/household profile image — only members may set it.
app.put('/api/groups/:id/avatar', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    if (!userId) return res.status(401).json({ error: 'Not authenticated' });
    const { image } = req.body;
    if (!image) return res.status(400).json({ error: 'No image provided' });
    if (!(await db.isGroupMember(req.params.id, userId))) {
      return res.status(403).json({ error: 'Not a member of this group' });
    }
    await db.updateGroupAvatar(req.params.id, image);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.get('/api/groups/:id/avatar', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await db.isGroupMember(req.params.id, req.session.user?.id))) {
      return res.status(403).json({ error: 'Not a member of this group' });
    }
    const image = await db.getGroupAvatar(req.params.id);
    if (!image) return res.status(404).json({ error: 'No avatar' });
    if (!sendStoredImage(req, res, image)) return res.status(404).json({ error: 'No avatar' });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Login page - Modern Design
app.get('/login', (req, res) => {
  res.set('Content-Security-Policy', PAGE_CSP);
  res.send(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Family Life - Sign In</title>
  <style>
    @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap');
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: 'Inter', sans-serif;
      background: linear-gradient(135deg, #1e1b4b 0%, #312e81 50%, #4338ca 100%);
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 20px;
    }
    .login-card {
      background: white;
      border-radius: 24px;
      padding: 48px;
      width: 100%;
      max-width: 420px;
      box-shadow: 0 25px 80px rgba(0,0,0,0.3);
    }
    .brand {
      text-align: center;
      margin-bottom: 40px;
    }
    .brand-icon {
      width: 64px;
      height: 64px;
      background: linear-gradient(135deg, #6366f1, #ec4899);
      border-radius: 16px;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 32px;
      margin: 0 auto 16px;
    }
    .brand h1 { font-size: 24px; font-weight: 700; color: #1e293b; }
    .brand p { color: #64748b; margin-top: 8px; }
    .user-selector { margin-bottom: 28px; }
    .selector-label {
      font-size: 14px;
      font-weight: 600;
      color: #374151;
      margin-bottom: 12px;
      display: block;
    }
    .user-options {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 12px;
    }
    .user-option {
      position: relative;
      cursor: pointer;
    }
    .user-option input {
      position: absolute;
      opacity: 0;
    }
    .user-card {
      border: 2px solid #e5e7eb;
      border-radius: 16px;
      padding: 24px;
      text-align: center;
      transition: all 0.2s;
    }
    .user-option:hover .user-card {
      border-color: #d1d5db;
    }
    .user-option input:checked + .user-card {
      border-color: #6366f1;
      background: #eef2ff;
    }
    .user-avatar {
      font-size: 40px;
      margin-bottom: 8px;
    }
    .user-name {
      font-weight: 600;
      color: #1f2937;
    }
    .password-section { margin-bottom: 24px; }
    .password-input {
      width: 100%;
      padding: 16px;
      border: 2px solid #e5e7eb;
      border-radius: 12px;
      font-size: 16px;
      transition: all 0.2s;
    }
    .password-input:focus {
      outline: none;
      border-color: #6366f1;
    }
    .signin-btn {
      width: 100%;
      padding: 16px;
      background: linear-gradient(135deg, #6366f1, #4f46e5);
      color: white;
      border: none;
      border-radius: 12px;
      font-size: 16px;
      font-weight: 600;
      cursor: pointer;
      transition: all 0.2s;
    }
    .signin-btn:hover {
      transform: translateY(-2px);
      box-shadow: 0 8px 25px rgba(99, 102, 241, 0.4);
    }
    .error {
      background: #fee2e2;
      color: #dc2626;
      padding: 12px 16px;
      border-radius: 8px;
      margin-bottom: 20px;
      font-size: 14px;
      text-align: center;
    }
    @media (max-width: 480px) {
      .login-card { padding: 32px 24px; }
    }
  </style>
  <script>
(function () {
  var E = "/api/permagent-analytics/collect";
  var S = null;
  try {
    S = sessionStorage.getItem("_pa_sid");
    if (!S) {
      S = Math.random().toString(36).slice(2) + Date.now().toString(36);
      sessionStorage.setItem("_pa_sid", S);
    }
  } catch (e) { }
  function send(kind, name, props, ref) {
    var body = JSON.stringify({
      k: kind,
      p: location.pathname + location.search,
      r: ref || null,
      n: name || null,
      d: props || null,
      s: S
    });
    if (!(navigator.sendBeacon && navigator.sendBeacon(E, body))) {
      fetch(E, { method: "POST", body: body, keepalive: true }).catch(function () {});
    }
  }
  var lastPath = null;
  var sentRef = false;
  function pageview() {
    if (location.pathname === lastPath) return;
    lastPath = location.pathname;
    var ref = sentRef ? null : (document.referrer || null);
    sentRef = true;
    send("pv", null, null, ref);
  }
  pageview();
  ["pushState", "replaceState"].forEach(function (m) {
    var orig = history[m];
    history[m] = function () { orig.apply(this, arguments); pageview(); };
  });
  addEventListener("popstate", pageview);
  window.permagent = window.permagent || {};
  window.permagent.event = function (name, props) { send("ev", name, props, null); };
  window.permagent.autocapture = function () {
    addEventListener("click", function (e) {
      var a = e.target && e.target.closest && e.target.closest("a[href]");
      if (!a) return;
      var url;
      try { url = new URL(a.href, location.href); } catch (err) { return; }
      if (url.host === location.host) return;
      send("ev", "outbound_click", { host: url.host, href: url.href.slice(0, 256) }, null);
    }, true);
  };
})();
  </script>
</head>
<body>
  <div class="login-card">
    <div class="brand">
      <div class="brand-icon">🏠</div>
      <h1>Family Life</h1>
      <p>Organize your household together</p>
    </div>
    ${req.query.error ? '<div class="error">Incorrect password. Please try again.</div>' : ''}
    <form method="POST" action="/login">
      <div class="user-selector">
        <label class="selector-label">Who's signing in?</label>
        <div class="user-options">
          <label class="user-option">
            <input type="radio" name="username" value="jesse" checked>
            <div class="user-card">
              <div class="user-avatar">👨‍💼</div>
              <div class="user-name">Jesse</div>
            </div>
          </label>
          <label class="user-option">
            <input type="radio" name="username" value="sophie">
            <div class="user-card">
              <div class="user-avatar">👩‍⚕️</div>
              <div class="user-name">Sophie</div>
            </div>
          </label>
        </div>
      </div>
      <div class="password-section">
        <input type="password" name="password" class="password-input" placeholder="Enter your password" required>
      </div>
      <button type="submit" class="signin-btn">Sign In</button>
    </form>
  </div>
</body>
</html>`);
});

// Login POST (web)
app.post('/login', loginLimiter, async (req, res) => {
  const db = new FamilyDB();
  try {
    const { username, password } = req.body;

    const dbUser = await db.getUserByUsername(username);
    const hash = dbUser?.password_hash || DUMMY_BCRYPT_HASH;
    const valid = await bcrypt.compare(String(password || ''), hash);
    if (dbUser && valid) {
      // The legacy web dashboard can't run the email-2FA flow, so it must NOT
      // be a way to bypass it. When 2FA is on, require the app for sign-in.
      if (TWO_FA_ENABLED) {
        return res.status(403).send('For your security, sign in from the Kinrows app. Two-factor authentication is required.');
      }
      await establishSession(req, { username: dbUser.username, name: dbUser.name, avatar: dbUser.avatar, id: dbUser.id });
      return res.redirect('/app');
    }

    res.redirect('/login?error=1');
  } catch (err) {
    res.redirect('/login?error=1');
  } finally {
    db.close();
  }
});

// Logout
app.get('/logout', (req, res) => {
  req.session.destroy();
  res.redirect('/login');
});

// Dashboard
// Legacy server-rendered browser dashboard. Moved off `/` (now the marketing
// site) to `/app` so it still works for anyone using the web app directly.
app.get('/app', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    const summary = await db.getDailySummary(userId);
    const groceries = await db.getGroceries('needed', userId);
    const tasks = await db.getTasks({ status: 'active' }, userId);
    const appointments = await db.getAppointments({}, userId);
    const tasksByCategory = {};
    tasks.forEach(task => {
      if (!tasksByCategory[task.category]) tasksByCategory[task.category] = [];
      tasksByCategory[task.category].push(task);
    });
    res.set('Content-Security-Policy', PAGE_CSP);
    res.send(renderDashboard(req.session.user, summary, groceries, tasksByCategory, appointments));
  } catch (err) {
    console.error('[error]', err && err.stack ? err.stack : err);
    res.status(500).send('Something went wrong. Please try again.');
  } finally {
    db.close();
  }
});

// Render Dashboard
function renderDashboard(user, summary, groceries, tasksByCategory, appointments) {
  const categories = Object.keys(tasksByCategory).sort();
  const today = todayLocal();
  const todayAppointments = appointments.filter(a => a.appointment_date === today);
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Family Life Organizer</title>
  <style>
    @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap');
    * { box-sizing: border-box; margin: 0; padding: 0; }
    :root {
      --primary: #6366f1;
      --primary-dark: #4f46e5;
      --gray-50: #f8fafc;
      --gray-100: #f1f5f9;
      --gray-200: #e2e8f0;
      --gray-300: #cbd5e1;
      --gray-600: #475569;
      --gray-800: #1e293b;
      --gray-900: #0f172a;
    }
    body {
      font-family: 'Inter', sans-serif;
      background: var(--gray-50);
      color: var(--gray-800);
    }
    .header {
      background: linear-gradient(135deg, #1e1b4b 0%, #312e81 100%);
      color: white;
      padding: 16px 24px;
      position: sticky;
      top: 0;
      z-index: 100;
    }
    .header-content {
      max-width: 1200px;
      margin: 0 auto;
      display: flex;
      justify-content: space-between;
      align-items: center;
    }
    .brand { display: flex; align-items: center; gap: 12px; }
    .brand-icon {
      width: 40px; height: 40px;
      background: linear-gradient(135deg, var(--primary), #ec4899);
      border-radius: 12px;
      display: flex; align-items: center; justify-content: center;
      font-size: 20px;
    }
    .brand h1 { font-size: 20px; font-weight: 700; }
    .user-menu { display: flex; align-items: center; gap: 16px; }
    .user-badge {
      display: flex; align-items: center; gap: 8px;
      padding: 8px 16px;
      background: rgba(255,255,255,0.1);
      border-radius: 9999px;
      font-size: 14px;
    }
    .logout-btn {
      padding: 8px 16px;
      background: rgba(255,255,255,0.1);
      color: white;
      border: none;
      border-radius: 8px;
      font-size: 14px;
      cursor: pointer;
    }
    .nav-tabs {
      background: white;
      border-bottom: 1px solid var(--gray-200);
      position: sticky;
      top: 72px;
      z-index: 99;
    }
    .nav-tabs-content {
      max-width: 1200px;
      margin: 0 auto;
      padding: 0 24px;
      display: flex;
      gap: 4px;
    }
    .nav-tab {
      padding: 16px 20px;
      background: none;
      border: none;
      border-bottom: 2px solid transparent;
      margin-bottom: -1px;
      font-size: 14px;
      font-weight: 500;
      color: var(--gray-600);
      cursor: pointer;
      display: flex;
      align-items: center;
      gap: 8px;
    }
    .nav-tab.active {
      color: var(--primary);
      border-bottom-color: var(--primary);
    }
    .main-content {
      max-width: 1200px;
      margin: 0 auto;
      padding: 24px;
    }
    .tab-panel {
      display: none;
      animation: fadeIn 0.3s ease;
    }
    .tab-panel.active { display: block; }
    @keyframes fadeIn {
      from { opacity: 0; transform: translateY(10px); }
      to { opacity: 1; transform: translateY(0); }
    }
    .stats-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
      gap: 20px;
      margin-bottom: 32px;
    }
    .stat-card {
      background: white;
      border-radius: 16px;
      padding: 24px;
      box-shadow: 0 1px 3px rgba(0,0,0,0.1);
    }
    .stat-header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin-bottom: 16px;
    }
    .stat-icon {
      width: 48px; height: 48px;
      border-radius: 12px;
      display: flex; align-items: center; justify-content: center;
      font-size: 24px;
    }
    .stat-value { font-size: 32px; font-weight: 700; }
    .stat-label { font-size: 14px; color: var(--gray-600); margin-top: 4px; }
    .card {
      background: white;
      border-radius: 16px;
      box-shadow: 0 1px 3px rgba(0,0,0,0.1);
      overflow: hidden;
    }
    .card-header {
      padding: 20px 24px;
      border-bottom: 1px solid var(--gray-100);
      display: flex;
      justify-content: space-between;
      align-items: center;
    }
    .card-title { font-size: 18px; font-weight: 600; }
    .card-body { padding: 24px; }
    .form-input, .form-select {
      width: 100%;
      padding: 12px 16px;
      border: 1px solid var(--gray-300);
      border-radius: 10px;
      font-size: 15px;
      margin-bottom: 12px;
    }
    .btn {
      padding: 12px 24px;
      border-radius: 10px;
      font-size: 14px;
      font-weight: 600;
      cursor: pointer;
      border: none;
    }
    .btn-primary {
      background: linear-gradient(135deg, var(--primary), var(--primary-dark));
      color: white;
    }
    .list-item {
      display: flex;
      align-items: center;
      padding: 16px;
      border-bottom: 1px solid var(--gray-100);
    }
    .list-item:last-child { border-bottom: none; }
    .checkbox {
      width: 22px; height: 22px;
      border: 2px solid var(--gray-300);
      border-radius: 6px;
      margin-right: 16px;
      cursor: pointer;
    }
    .list-content { flex: 1; }
    .badge {
      padding: 4px 12px;
      border-radius: 9999px;
      font-size: 12px;
      background: var(--gray-100);
      color: var(--gray-600);
    }
    .two-column {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 24px;
    }
    @media (max-width: 768px) {
      .two-column { grid-template-columns: 1fr; }
      .nav-tab-text { display: none; }
      .stats-grid { grid-template-columns: repeat(2, 1fr); gap: 12px; }
      .stat-card { padding: 16px; }
      .stat-value { font-size: 24px; }
      .stat-icon { width: 36px; height: 36px; font-size: 18px; }
      .card-header { padding: 16px; }
      .card-body { padding: 16px; }
      .form-input, .form-select { padding: 14px; font-size: 16px; }
      .btn { padding: 14px 20px; width: 100%; margin-bottom: 8px; }
      .main-content { padding: 16px; }
      .header-content { padding: 12px 16px; }
      .brand h1 { font-size: 18px; }
    }
    
    /* Calendar Grid Styles */
    .calendar-grid {
      display: grid;
      grid-template-columns: repeat(7, 1fr);
      gap: 4px;
    }
    .calendar-day-header {
      text-align: center;
      padding: 12px 4px;
      font-size: 12px;
      font-weight: 600;
      color: var(--gray-500);
      text-transform: uppercase;
    }
    .calendar-day {
      aspect-ratio: 1;
      border: 1px solid var(--gray-200);
      border-radius: 8px;
      padding: 6px;
      min-height: 80px;
      display: flex;
      flex-direction: column;
      background: white;
    }
    .calendar-day.other-month {
      background: var(--gray-50);
      color: var(--gray-400);
    }
    .calendar-day.today {
      border-color: var(--primary);
      border-width: 2px;
      background: #eef2ff;
    }
    .calendar-day-number {
      font-weight: 600;
      font-size: 14px;
      margin-bottom: 4px;
    }
    .calendar-day.today .calendar-day-number {
      color: var(--primary);
    }
    .calendar-event {
      font-size: 10px;
      padding: 2px 4px;
      background: var(--primary);
      color: white;
      border-radius: 4px;
      margin-bottom: 2px;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }
    .calendar-event-dot {
      width: 6px;
      height: 6px;
      background: var(--primary);
      border-radius: 50%;
      display: inline-block;
      margin-right: 4px;
    }
    @media (max-width: 640px) {
      .calendar-day {
        min-height: 50px;
        padding: 4px;
      }
      .calendar-day-header {
        padding: 8px 2px;
        font-size: 10px;
      }
      .calendar-day-number {
        font-size: 12px;
      }
      .calendar-event {
        font-size: 8px;
        padding: 1px 2px;
      }
    }
  </style>
  <script>
(function () {
  var E = "/api/permagent-analytics/collect";
  var S = null;
  try {
    S = sessionStorage.getItem("_pa_sid");
    if (!S) {
      S = Math.random().toString(36).slice(2) + Date.now().toString(36);
      sessionStorage.setItem("_pa_sid", S);
    }
  } catch (e) { }
  function send(kind, name, props, ref) {
    var body = JSON.stringify({
      k: kind,
      p: location.pathname + location.search,
      r: ref || null,
      n: name || null,
      d: props || null,
      s: S
    });
    if (!(navigator.sendBeacon && navigator.sendBeacon(E, body))) {
      fetch(E, { method: "POST", body: body, keepalive: true }).catch(function () {});
    }
  }
  var lastPath = null;
  var sentRef = false;
  function pageview() {
    if (location.pathname === lastPath) return;
    lastPath = location.pathname;
    var ref = sentRef ? null : (document.referrer || null);
    sentRef = true;
    send("pv", null, null, ref);
  }
  pageview();
  ["pushState", "replaceState"].forEach(function (m) {
    var orig = history[m];
    history[m] = function () { orig.apply(this, arguments); pageview(); };
  });
  addEventListener("popstate", pageview);
  window.permagent = window.permagent || {};
  window.permagent.event = function (name, props) { send("ev", name, props, null); };
  window.permagent.autocapture = function () {
    addEventListener("click", function (e) {
      var a = e.target && e.target.closest && e.target.closest("a[href]");
      if (!a) return;
      var url;
      try { url = new URL(a.href, location.href); } catch (err) { return; }
      if (url.host === location.host) return;
      send("ev", "outbound_click", { host: url.host, href: url.href.slice(0, 256) }, null);
    }, true);
  };
})();
  </script>
</head>
<body>
  <header class="header">
    <div class="header-content">
      <div class="brand">
        <div class="brand-icon">🏠</div>
        <h1>Family Life</h1>
      </div>
      <div class="user-menu">
        <div class="user-badge">
          <span>${htmlEsc(user.avatar)}</span>
          <span>${htmlEsc(user.name)}</span>
        </div>
        <button class="logout-btn" onclick="location.href='/logout'">Sign Out</button>
      </div>
    </div>
  </header>
  
  <nav class="nav-tabs">
    <div class="nav-tabs-content">
      <button class="nav-tab active" onclick="switchTab('overview', this)">
        <span>📊</span><span class="nav-tab-text">Overview</span>
      </button>
      <button class="nav-tab" onclick="switchTab('calendar', this)">
        <span>📅</span><span class="nav-tab-text">Calendar</span>
      </button>
      <button class="nav-tab" onclick="switchTab('budget', this)">
        <span>💰</span><span class="nav-tab-text">Budget</span>
      </button>
      <button class="nav-tab" onclick="switchTab('groceries', this)">
        <span>🛒</span><span class="nav-tab-text">Groceries</span>
      </button>
      <button class="nav-tab" onclick="switchTab('tasks', this)">
        <span>✓</span><span class="nav-tab-text">Tasks</span>
      </button>
      <button class="nav-tab" onclick="switchTab('add', this)">
        <span>+</span><span class="nav-tab-text">Add</span>
      </button>
    </div>
  </nav>
  
  <main class="main-content">
    <!-- Overview Tab -->
    <div id="overview" class="tab-panel active">
      <div class="stats-grid">
        <div class="stat-card">
          <div class="stat-header">
            <div>
              <div class="stat-value">${summary.tasks_today}</div>
              <div class="stat-label">Tasks Today</div>
            </div>
            <div class="stat-icon" style="background:#dbeafe">📋</div>
          </div>
        </div>
        <div class="stat-card">
          <div class="stat-header">
            <div>
              <div class="stat-value">${todayAppointments.length}</div>
              <div class="stat-label">Appointments</div>
            </div>
            <div class="stat-icon" style="background:#fce7f3">📅</div>
          </div>
        </div>
        <div class="stat-card">
          <div class="stat-header">
            <div>
              <div class="stat-value">${summary.groceries_needed}</div>
              <div class="stat-label">Groceries</div>
            </div>
            <div class="stat-icon" style="background:#d1fae5">🛒</div>
          </div>
        </div>
        <div class="stat-card">
          <div class="stat-header">
            <div>
              <div class="stat-value">${summary.overdue_tasks}</div>
              <div class="stat-label">Overdue</div>
            </div>
            <div class="stat-icon" style="background:#ffedd5">⚠️</div>
          </div>
        </div>
      </div>
      
      <div class="two-column">
        <div class="card">
          <div class="card-header">
            <h3 class="card-title">Quick Tasks</h3>
          </div>
          <div class="card-body">
            ${categories.slice(0, 3).map(cat => `
              <h4 style="font-size:14px;color:var(--gray-600);margin:16px 0 8px">${htmlEsc(cat)}</h4>
              ${tasksByCategory[cat].slice(0, 2).map(task => `
                <div class="list-item">
                  <div class="checkbox" onclick="completeTask(${task.id})"></div>
                  <div class="list-content">${htmlEsc(task.title)}</div>
                </div>
              `).join('')}
            `).join('') || '<p style="color:var(--gray-600);text-align:center;padding:32px">No tasks for today!</p>'}
          </div>
        </div>
        
        <div class="card">
          <div class="card-header">
            <h3 class="card-title">Grocery List</h3>
          </div>
          <div class="card-body">
            ${groceries.slice(0, 5).map(item => `
              <div class="list-item">
                <div class="checkbox" onclick="completeGrocery(${item.id})"></div>
                <div class="list-content">${htmlEsc(item.item)}</div>
                ${item.category ? `<span class="badge">${htmlEsc(item.category)}</span>` : ''}
              </div>
            `).join('') || '<p style="color:var(--gray-600);text-align:center;padding:32px">No items needed</p>'}
          </div>
        </div>
        
        <div class="card">
          <div class="card-header">
            <h3 class="card-title">Today's Appointments</h3>
          </div>
          <div class="card-body">
            ${todayAppointments.map(appt => `
              <div class="list-item">
                <div class="list-content">
                  <strong>${htmlEsc(appt.title)}</strong>
                  ${appt.appointment_time ? `<span style="color:var(--gray-500);margin-left:8px">${htmlEsc(appt.appointment_time)}</span>` : ''}
                  ${appt.person_tags ? `<div style="margin-top:4px">${appt.person_tags.split(',').map(p => `<span class="badge" style="margin-right:4px">${htmlEsc(p)}</span>`).join('')}</div>` : ''}
                </div>
              </div>
            `).join('') || '<p style="color:var(--gray-600);text-align:center;padding:32px">No appointments today</p>'}
          </div>
        </div>
      </div>
    </div>
    
    <!-- Calendar Tab -->
    <div id="calendar" class="tab-panel">
      <div class="card">
        <div class="card-header" style="flex-wrap:wrap;gap:12px">
          <h3 class="card-title" id="calendarTitle">Calendar</h3>
          <div style="display:flex;gap:8px">
            <button class="btn btn-secondary" onclick="changeMonth(-1)">← Prev</button>
            <button class="btn btn-secondary" onclick="changeMonth(1)">Next →</button>
            <button class="btn btn-primary" onclick="goToToday()">Today</button>
          </div>
        </div>
        <div class="card-body">
          <div class="calendar-grid" id="calendarGrid">
            <!-- Calendar generated by JS -->
          </div>
        </div>
      </div>
    </div>
    
    <!-- Budget Tab -->
    <div id="budget" class="tab-panel">
      <div class="card">
        <div class="card-header">
          <h3 class="card-title">Household Budget</h3>
        </div>
        <div class="card-body">
          <p style="background:#eef2ff;padding:16px;border-radius:12px;margin-bottom:24px">
            📧 Forward receipts to: <strong>redacted@example.com</strong>
          </p>
          <div class="two-column">
            <div>
              <h4 style="margin-bottom:16px">Add Receipt</h4>
              <input type="number" class="form-input" placeholder="Amount ($)">
              <input type="text" class="form-input" placeholder="Merchant">
              <select class="form-select">
                <option>Select category...</option>
                <option>Groceries</option>
                <option>Dining Out</option>
                <option>Gas/Transport</option>
                <option>Household</option>
                <option>Health</option>
                <option>Pets</option>
                <option>Entertainment</option>
                <option>Kids</option>
                <option>Other</option>
              </select>
              <button class="btn btn-primary">Add Receipt</button>
            </div>
            <div>
              <h4 style="margin-bottom:16px">Recent</h4>
              <p style="color:var(--gray-600);text-align:center;padding:32px">No receipts yet</p>
            </div>
          </div>
        </div>
      </div>
    </div>
    
    <!-- Groceries Tab -->
    <div id="groceries" class="tab-panel">
      <div class="card">
        <div class="card-header">
          <h3 class="card-title">Grocery List</h3>
        </div>
        <div class="card-body">
          <div style="display:flex;gap:12px;margin-bottom:24px">
            <input type="text" class="form-input" id="groceryInput" placeholder="Add item..." style="flex:1;margin:0">
            <button class="btn btn-primary" onclick="addGrocery()">Add</button>
          </div>
          ${groceries.map(item => `
            <div class="list-item">
              <div class="checkbox" onclick="completeGrocery(${item.id})"></div>
              <div class="list-content">${htmlEsc(item.item)}</div>
              ${item.category ? `<span class="badge">${htmlEsc(item.category)}</span>` : ''}
            </div>
          `).join('') || '<p style="color:var(--gray-600);text-align:center;padding:32px">No items needed</p>'}
        </div>
      </div>
    </div>
    
    <!-- Tasks Tab -->
    <div id="tasks" class="tab-panel">
      <div class="card">
        <div class="card-header">
          <h3 class="card-title">All Tasks</h3>
        </div>
        <div class="card-body">
          ${categories.map(cat => `
            <h4 style="font-size:14px;color:var(--gray-600);margin:24px 0 12px;text-transform:capitalize">${htmlEsc(cat)}</h4>
            ${tasksByCategory[cat].map(task => `
              <div class="list-item">
                <div class="checkbox" onclick="completeTask(${task.id})"></div>
                <div class="list-content">${htmlEsc(task.title)}</div>
                ${task.due_date ? `<span class="badge">${htmlEsc(task.due_date)}</span>` : ''}
              </div>
            `).join('')}
          `).join('') || '<p style="color:var(--gray-600);text-align:center;padding:32px">No tasks yet!</p>'}
        </div>
      </div>
    </div>
    
    <!-- Add Tab -->
    <div id="add" class="tab-panel">
      <div class="two-column">
        <div class="card">
          <div class="card-header">
            <h3 class="card-title">Add Task</h3>
          </div>
          <div class="card-body">
            <input type="text" class="form-input" id="taskTitle" placeholder="What needs to be done?">
            <select class="form-select" id="taskCategory">
              <option value="">Select category...</option>
              <option value="groceries">Groceries</option>
              <option value="appointments">Appointments</option>
              <option value="home">Home</option>
              <option value="automotive">Automotive</option>
              <option value="travel">Travel</option>
              <option value="finances">Finances</option>
              <option value="childcare">Childcare</option>
              <option value="health">Health</option>
            </select>
            <input type="date" class="form-input" id="taskDate">
            <button class="btn btn-primary" onclick="addTask()">Add Task</button>
          </div>
        </div>
        
        <div class="card">
          <div class="card-header">
            <h3 class="card-title">Add Appointment</h3>
          </div>
          <div class="card-body">
            <input type="text" class="form-input" id="apptTitle" placeholder="Event title (e.g., Dentist, School play)">
            <input type="date" class="form-input" id="apptDate">
            <input type="time" class="form-input" id="apptTime">
            <input type="text" class="form-input" id="apptLocation" placeholder="Location (optional)">
            <div style="margin-bottom:16px">
              <label style="display:block;font-size:14px;color:var(--gray-600);margin-bottom:8px">Who's involved?</label>
              <div style="display:flex;gap:16px;flex-wrap:wrap">
                <label style="display:flex;align-items:center;gap:6px;cursor:pointer">
                  <input type="checkbox" class="appt-person" value="Jesse"> Jesse
                </label>
                <label style="display:flex;align-items:center;gap:6px;cursor:pointer">
                  <input type="checkbox" class="appt-person" value="Sophie"> Sophie
                </label>
                <label style="display:flex;align-items:center;gap:6px;cursor:pointer">
                  <input type="checkbox" class="appt-person" value="Rowan"> Rowan
                </label>
                <label style="display:flex;align-items:center;gap:6px;cursor:pointer">
                  <input type="checkbox" class="appt-person" value="Baby"> Baby
                </label>
              </div>
            </div>
            <button class="btn btn-primary" onclick="addAppointment()">Add Appointment</button>
          </div>
        </div>
      </div>
    </div>
  </main>
  
  <script>
    function switchTab(tabName, btn) {
      document.querySelectorAll('.tab-panel').forEach(p => p.classList.remove('active'));
      document.querySelectorAll('.nav-tab').forEach(t => t.classList.remove('active'));
      document.getElementById(tabName).classList.add('active');
      btn.classList.add('active');
    }
    
    async function completeTask(id) {
      await fetch('/api/complete', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({type: 'task', id})
      });
      location.reload();
    }
    
    async function completeGrocery(id) {
      await fetch('/api/complete', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({type: 'grocery', id})
      });
      location.reload();
    }
    
    async function addGrocery() {
      const item = document.getElementById('groceryInput').value;
      if (!item) return;
      await fetch('/api/add', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({type: 'grocery', data: {item}})
      });
      location.reload();
    }
    
    async function addTask() {
      const title = document.getElementById('taskTitle').value;
      const category = document.getElementById('taskCategory').value;
      if (!title || !category) return;
      await fetch('/api/add', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({type: 'task', data: {title, category}})
      });
      location.reload();
    }
    
    async function addAppointment() {
      const btn = event.target;
      const title = document.getElementById('apptTitle')?.value;
      const date = document.getElementById('apptDate')?.value;
      const time = document.getElementById('apptTime')?.value;
      const locationVal = document.getElementById('apptLocation')?.value;
      const personCheckboxes = document.querySelectorAll('.appt-person:checked');
      const person_tags = Array.from(personCheckboxes).map(cb => cb.value);
      
      if (!title || !date) {
        alert('Please enter a title and date');
        return;
      }
      
      btn.disabled = true;
      btn.textContent = 'Adding...';
      
      try {
        const response = await fetch('/api/appointments', {
          method: 'POST',
          headers: {'Content-Type': 'application/json'},
          body: JSON.stringify({
            title, 
            appointment_date: date,
            appointment_time: time,
            location: locationVal,
            person_tags: person_tags
          })
        });
        
        if (!response.ok) {
          const err = await response.text();
          alert('Error: ' + err);
          btn.disabled = false;
          btn.textContent = 'Add Appointment';
          return;
        }
        
        location.reload();
      } catch (err) {
        alert('Network error: ' + err.message);
        btn.disabled = false;
        btn.textContent = 'Add Appointment';
      }
    }
    
    // Calendar Functions
    let currentCalendarDate = new Date();
    // "<" escaped as \\u003c so user data can never break out of this <script>
    // block (e.g. a title containing "</script>").
    const appointmentsData = ${JSON.stringify(appointments).replace(/</g, '\\u003c')};

    function escHtml(s) {
      return String(s == null ? '' : s)
        .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
    }
    
    function renderCalendar() {
      const year = currentCalendarDate.getFullYear();
      const month = currentCalendarDate.getMonth();
      const firstDay = new Date(year, month, 1);
      const lastDay = new Date(year, month + 1, 0);
      const daysInMonth = lastDay.getDate();
      const startDayOfWeek = firstDay.getDay();
      
      // Update title
      const monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 
                          'July', 'August', 'September', 'October', 'November', 'December'];
      document.getElementById('calendarTitle').textContent = monthNames[month] + ' ' + year;
      
      let html = '';
      
      // Day headers
      const dayHeaders = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
      dayHeaders.forEach(day => {
        html += '<div class="calendar-day-header">' + day + '</div>';
      });

      // Empty cells before start of month
      for (let i = 0; i < startDayOfWeek; i++) {
        html += '<div class="calendar-day other-month"></div>';
      }

      // Days of month
      const today = new Date().toISOString().split('T')[0];
      for (let day = 1; day <= daysInMonth; day++) {
        const dateStr = year + '-' + String(month + 1).padStart(2, '0') + '-' + String(day).padStart(2, '0');
        const isToday = dateStr === today;
        const dayAppointments = appointmentsData.filter(a => a.appointment_date === dateStr);

        html += '<div class="calendar-day ' + (isToday ? 'today' : '') + '">';
        html += '<div class="calendar-day-number">' + day + '</div>';

        if (dayAppointments.length > 0) {
          dayAppointments.slice(0, 2).forEach(appt => {
            html += '<div class="calendar-event" title="' + escHtml(appt.title) + '">' + escHtml(appt.title) + '</div>';
          });
          if (dayAppointments.length > 2) {
            html += '<div style="font-size:10px;color:var(--gray-500)">+' + (dayAppointments.length - 2) + ' more</div>';
          }
        }

        html += '</div>';
      }
      
      document.getElementById('calendarGrid').innerHTML = html;
    }
    
    function changeMonth(delta) {
      currentCalendarDate.setMonth(currentCalendarDate.getMonth() + delta);
      renderCalendar();
    }
    
    function goToToday() {
      currentCalendarDate = new Date();
      renderCalendar();
    }
    
    // Initialize calendar when tab is shown
    const originalSwitchTab = switchTab;
    switchTab = function(tabName, btn) {
      originalSwitchTab(tabName, btn);
      if (tabName === 'calendar') {
        renderCalendar();
      }
    };
    
    // Also update stats on load
    document.addEventListener('DOMContentLoaded', function() {
      // Update appointments count
      const today = new Date().toISOString().split('T')[0];
      const todayApptCount = appointmentsData.filter(a => a.appointment_date === today).length;
      const apptCard = document.querySelector('.stat-card:nth-child(2) .stat-value');
      if (apptCard) apptCard.textContent = todayApptCount;
    });
  </script>
</body>
</html>`;
}

// API Routes
app.post('/api/add', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const { type, data } = req.body;
    if (type === 'grocery') {
      if (typeof data?.item !== 'string' || !data.item.trim()) {
        return res.status(400).json({ error: 'item is required' });
      }
      // Resolve user's household group_id
      const username = req.session.user.username || req.session.user.name;
      const userGroupId = await db.getUserHouseholdId(req.session.user?.id);
      // Never write a NULL-group row: the startup backfill would later re-home
      // it into another household (cross-household leak).
      if (!userGroupId) return res.status(403).json({ error: 'Join a household first' });
      await db.addGrocery(data.item, data.category || null, data.quantity || '1', username, userGroupId);
    } else if (type === 'task') {
      if (typeof data?.title !== 'string' || !data.title.trim()) {
        return res.status(400).json({ error: 'title is required' });
      }
      const groupId = await db.getUserHouseholdId(req.session.user?.id);
      // Never write a NULL-group row: the startup backfill would later re-home
      // it into another household (same guard as the grocery branch).
      if (!groupId) return res.status(403).json({ error: 'Join a household first' });
      // category is NOT NULL in the schema — default rather than 500.
      await db.addTask({...data, category: data.category || 'personal', status: 'active', group_id: groupId});
    }
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Task edit/delete (household-scoped). The concierge and any future UI use
// the same DB methods.
app.put('/api/tasks/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireHouseholdRow(db, 'tasks', req.params.id, req, res))) return;
    await db.updateTask(req.params.id, req.body);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.delete('/api/tasks/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireHouseholdRow(db, 'tasks', req.params.id, req, res))) return;
    await db.deleteTask(req.params.id);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.post('/api/complete', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const { type, id } = req.body;
    if (type === 'grocery') {
      if (!(await requireHouseholdRow(db, 'groceries', id, req, res))) return;
      await db.purchaseGrocery(id);
    } else if (type === 'task') {
      // Verify the task is in the caller's household before completing — a
      // household-less user must not be able to complete arbitrary task ids
      // (completeTask with a null group would run unscoped).
      if (!(await requireHouseholdRow(db, 'tasks', id, req, res))) return;
      await db.completeTask(id, await db.getUserHouseholdId(req.session.user?.id));
    }
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.get('/api/data', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    const summary = await db.getDailySummary(userId);
    const groceries = await db.getGroceries('needed', userId);
    res.json({ summary, groceries });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Appointments in [dateFrom, dateTo], with recurrence expanded the same way
// GET /api/appointments does. Used by that list route and by GET /api/home so
// Home does not issue three appointment queries.
async function appointmentsInRange(db, userId, { dateFrom, dateTo, person } = {}) {
  const filters = {};
  if (dateFrom) filters.date_from = dateFrom;
  if (dateTo) filters.date_to = dateTo;
  if (person) filters.person = person;
  const appointments = await db.getAppointments(filters, userId);

  if (!filters.date_from && !filters.date_to) return appointments;

  const rangeStart = filters.date_from ? new Date(filters.date_from + 'T00:00:00') : new Date('2020-01-01');
  const rangeEnd = filters.date_to ? new Date(filters.date_to + 'T23:59:59') : new Date('2030-12-31');
  const recurring = await db.getRecurringAppointments(userId);
  const existingDates = new Set(appointments.map(a => `${a.id}-${a.appointment_date}`));
  for (const appt of recurring) {
    const originDate = new Date(appt.appointment_date + 'T12:00:00Z');
    const endDate = appt.recurrence_end ? new Date(appt.recurrence_end + 'T23:59:59Z') : null;
    const occurrences = expandRecurrence(appt.recurrence_rule, originDate, rangeStart, new Date(rangeEnd.getTime() + 86400000), endDate);
    for (const date of occurrences) {
      const dateStr = date.toISOString().slice(0, 10);
      if (filters.date_from && dateStr < filters.date_from) continue;
      if (filters.date_to && dateStr > filters.date_to) continue;
      const key = `${appt.id}-${dateStr}`;
      if (!existingDates.has(key)) {
        appointments.push({ ...appt, appointment_date: dateStr, _recurring_source: appt.id });
        existingDates.add(key);
      }
    }
  }
  appointments.sort((a, b) => (a.appointment_date + (a.appointment_time || '')).localeCompare(b.appointment_date + (b.appointment_time || '')));
  return appointments;
}

app.post('/api/appointments', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const data = { ...req.body };
    const userId = req.session.user.id;
    data.created_by = userId;
    if (typeof data.title === 'string') data.title = data.title.trim();
    if (data.appointment_date) data.appointment_date = normalizeDate(data.appointment_date);
    // Events are household-only: a supplied group_id must be one of the caller's
    // households; otherwise default to their primary household. Never a clan.
    const apptGid = await resolveCreateGroupId(db, userId, data.group_id, { householdOnly: true });
    if (apptGid == null) return res.status(403).json({ error: 'Cannot create an event in that group' });
    data.group_id = apptGid;
    const created = await db.addAppointment(data);
    res.json({ success: true, id: created.id });
    // Notify household members about the new event
    if (data.group_id) {
      const title = (data.title || 'New event').trim();
      const dateStr = data.appointment_date || '';
      const body = dateStr ? `${title} on ${dateStr} has been added to your calendar.` : `${title} has been added to your calendar.`;
      // Resolve the creator's CURRENT name from the DB — req.session.user.name is
      // cached at login and can be stale (e.g. an old "Sophie Chiasson " value).
      const creator = await db.getUserById(userId);
      const senderName = (creator?.name || '').trim();
      const pushTitle = senderName ? `${senderName} added an event` : 'New event added';
      jobs.pushToGroup(db, data.group_id, userId, pushTitle, body, { type: 'event', ref_id: created.id });
    }
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// === Mobile API Endpoints ===

// Tasks
app.get('/api/tasks', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const filters = {};
    if (req.query.status) filters.status = req.query.status;
    if (req.query.category) filters.category = req.query.category;
    if (req.query.assigned_to) filters.assigned_to = req.query.assigned_to;
    const tasks = await db.getTasks(filters, req.session.user.id);
    res.json(tasks);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Appointments - list with filters
app.get('/api/appointments', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const appointments = await appointmentsInRange(db, req.session.user.id, {
      dateFrom: req.query.date_from,
      dateTo: req.query.date_to,
      person: req.query.person,
    });
    res.json(appointments);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Event attachments — list items attached to an appointment.
// NOTE: defined BEFORE `/:year/:month` so "123/attachments" isn't parsed as a month.
app.get('/api/appointments/:id/attachments', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireHouseholdRow(db, 'appointments', req.params.id, req, res))) return;
    const attachments = await db.getEventAttachments(req.params.id);
    res.json(attachments);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Event attachments — attach an item to an appointment
app.post('/api/appointments/:id/attachments', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireHouseholdRow(db, 'appointments', req.params.id, req, res))) return;
    const { attachment_type, attachment_id } = req.body || {};
    const allowed = ['list', 'note', 'decision', 'receipt', 'trip', 'itinerary', 'task'];
    if (!allowed.includes(attachment_type) || !attachment_id) {
      return res.status(400).json({ error: 'Invalid attachment_type or attachment_id' });
    }
    const userId = req.session.user.id;
    if (!(await canAttachEntity(db, attachment_type, attachment_id, userId))) {
      return res.status(403).json({ error: 'Cannot attach an item you do not have access to' });
    }
    // Tag the attachment with the event's own household (the appointment already
    // passed requireHouseholdRow), so it follows the event's household, not the
    // caller's primary one (which may differ for a multi-household user).
    const apptRow = await dbGet(db, 'SELECT group_id FROM appointments WHERE id = ?', [req.params.id]);
    await db.addEventAttachment({
      appointment_id: req.params.id,
      attachment_type,
      attachment_id,
      group_id: apptRow?.group_id || null,
      added_by: userId,
    });
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Event attachments — remove an attachment from an appointment
app.delete('/api/appointments/:id/attachments/:attachmentId', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireHouseholdRow(db, 'appointments', req.params.id, req, res))) return;
    await db.deleteEventAttachment(req.params.attachmentId, req.params.id);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Appointments - by month
// Calendar sync — push this device's calendar events up to the household.
// Body: { events: [{external_id, calendar_name, title, location, starts_at, ends_at, all_day}],
//         window_start, window_end }  (window bounds let us soft-delete removed events)
app.post('/api/calendar-sync', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user.id;
    const gid = await db.getUserHouseholdId(userId);
    if (gid == null) return res.status(403).json({ error: 'No household to share a calendar with' });
    const { events, window_start, window_end } = req.body || {};
    if (!Array.isArray(events) || !window_start || !window_end) {
      return res.status(400).json({ error: 'events[], window_start and window_end are required' });
    }
    const result = await db.upsertSyncedCalendarEvents(userId, gid, events, window_start, window_end);
    res.json({ success: true, ...result });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Household members' synced device-calendar events for a month.
app.get('/api/calendar-sync/:year/:month', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const year = parseInt(req.params.year);
    const month = parseInt(req.params.month);
    const rows = await db.getSyncedCalendarEventsByMonth(year, month, req.session.user.id);
    res.json(rows);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// One appointment by id (for opening it from a notification). Household-scoped.
app.get('/api/appointments/id/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireHouseholdRow(db, 'appointments', req.params.id, req, res))) return;
    const appt = await dbGet(db, 'SELECT * FROM appointments WHERE id = ?', [req.params.id]);
    if (!appt) return res.status(404).json({ error: 'Not found' });
    res.json(appt);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.get('/api/appointments/:year/:month', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const year = parseInt(req.params.year);
    const month = parseInt(req.params.month);
    const userId = req.session.user.id;
    const appointments = await db.getAppointmentsByMonth(year, month, userId);

    // Expand recurring events into the queried month
    const rangeStart = new Date(year, month - 1, 1);
    const rangeEnd = new Date(month === 12 ? year + 1 : year, month === 12 ? 0 : month, 1);
    const recurring = await db.getRecurringAppointments(userId);
    const existingDates = new Set(appointments.map(a => `${a.id}-${a.appointment_date}`));
    for (const appt of recurring) {
      const originDate = new Date(appt.appointment_date + 'T12:00:00Z');
      const endDate = appt.recurrence_end ? new Date(appt.recurrence_end + 'T23:59:59Z') : null;
      const occurrences = expandRecurrence(appt.recurrence_rule, originDate, rangeStart, rangeEnd, endDate);
      for (const date of occurrences) {
        const dateStr = date.toISOString().slice(0, 10);
        const key = `${appt.id}-${dateStr}`;
        if (!existingDates.has(key)) {
          appointments.push({ ...appt, appointment_date: dateStr, _recurring_source: appt.id });
          existingDates.add(key);
        }
      }
    }

    appointments.sort((a, b) => (a.appointment_date + (a.appointment_time || '')).localeCompare(b.appointment_date + (b.appointment_time || '')));
    sendCachedJson(req, res, userId, appointments);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Appointments - delete
app.delete('/api/appointments/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireHouseholdRow(db, 'appointments', req.params.id, req, res))) return;
    await db.deleteAppointment(req.params.id);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.put('/api/appointments/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireHouseholdRow(db, 'appointments', req.params.id, req, res))) return;
    const data = { ...req.body };
    if (data.appointment_date) data.appointment_date = normalizeDate(data.appointment_date);
    await db.updateAppointment(req.params.id, data);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Groceries
app.get('/api/groceries', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const status = req.query.status || 'needed';
    const userId = req.session.user?.id;
    const groceries = await db.getGroceries(status, userId);
    res.json(groceries);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Receipts
app.get('/api/receipts', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const filters = {};
    if (req.query.month) filters.month = req.query.month;
    if (req.query.category) filters.category = req.query.category;
    const groupId = await db.getUserHouseholdId(req.session.user?.id);
    if (!groupId) return res.json([]);
    const receipts = await db.getReceipts(filters, groupId, {
      limit: req.query.limit != null ? clampLimit(req.query.limit, 50, 1000) : 1000,
      before_id: req.query.before_id ? parseInt(req.query.before_id, 10) : undefined,
      before_date: typeof req.query.before_date === 'string' ? req.query.before_date : undefined,
    });
    res.json(receipts);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Budget summary by month
// Budget stats / trends (declared before /api/budget/:month so it isn't
// captured as a month param). Monthly trend, category breakdown, budget vs
// actual, recurring fixed costs, and derived insights — all household-scoped.
app.get('/api/budget/stats', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const groupId = await db.getUserHouseholdId(req.session.user?.id);
    if (!groupId) {
      const ym = new Date().toLocaleDateString('en-CA').slice(0, 7);
      return res.json({
        month: ym, monthly: [], byCategory: [], budgetVsActual: [],
        currentTotal: 0, previousTotal: 0, momPct: null, trailingAvg: 0,
        projectedMonthEnd: 0, recurringMonthly: 0, variableThisMonth: 0, overBudget: [],
      });
    }
    const months = parseInt(req.query.months) || 6;
    const stats = await db.getSpendingStats(groupId, months);
    const budgetVsActual = await db.getBudgetSummary(stats.thisMonth, groupId);

    // Derived figures the iOS Stats view renders as insight cards.
    const series = stats.monthly;
    const curr = series.length ? series[series.length - 1].total : 0;
    const prev = series.length > 1 ? series[series.length - 2].total : 0;
    const momPct = prev > 0 ? Math.round(((curr - prev) / prev) * 100) : null;
    const avg = series.length ? series.reduce((s, m) => s + m.total, 0) / series.length : 0;

    // Run-rate projection for the current month + remaining fixed commitments.
    const now = new Date();
    const dayOfMonth = now.getDate();
    const daysInMonth = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate();
    const runRate = dayOfMonth > 0 ? (curr / dayOfMonth) * daysInMonth : curr;
    const projectedMonthEnd = Math.round(Math.max(runRate, curr));

    const overBudget = budgetVsActual.filter(b => b.monthly_limit > 0 && b.spent > b.monthly_limit)
      .map(b => ({ category: b.category, spent: b.spent, limit: b.monthly_limit }));
    const fixed = Math.round(stats.recurringMonthly);
    const variable = Math.round(Math.max(0, curr - fixed));

    res.json({
      month: stats.thisMonth,
      monthly: series,                 // [{ ym, total }] oldest -> newest
      byCategory: stats.byCategory,    // [{ category, spent }] current month, desc
      budgetVsActual,                  // [{ category, monthly_limit, color, spent }]
      currentTotal: Math.round(curr),
      previousTotal: Math.round(prev),
      momPct,
      trailingAvg: Math.round(avg),
      projectedMonthEnd,
      recurringMonthly: fixed,
      variableThisMonth: variable,
      overBudget,
    });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.get('/api/budget/:month', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const groupId = await db.getUserHouseholdId(req.session.user?.id);
    if (!groupId) return res.json([]);
    const budget = await db.getBudgetSummary(req.params.month, groupId);
    res.json(budget);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Recurring payments CRUD (household-scoped, track-only)
app.get('/api/recurring-payments', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const groupId = await db.getUserHouseholdId(req.session.user?.id);
    if (!groupId) return res.json([]);
    const items = await db.getRecurringPayments(groupId);
    res.json(items);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.post('/api/recurring-payments', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const groupId = await db.getUserHouseholdId(req.session.user?.id);
    // Never write a NULL-group row: the startup backfill would later re-home
    // it into another household (cross-household leak).
    if (!groupId) return res.status(403).json({ error: 'Join a household first' });
    const result = await db.addRecurringPayment({
      ...req.body,
      amount: parseMoney(req.body.amount),
      created_by: req.session.user?.username || req.session.user?.name,
      group_id: groupId,
    });
    res.json({ success: true, id: result.id });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.put('/api/recurring-payments/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireHouseholdRow(db, 'recurring_payments', req.params.id, req, res))) return;
    const rpUpdates = { ...req.body };
    if (rpUpdates.amount !== undefined) rpUpdates.amount = parseMoney(rpUpdates.amount);
    await db.updateRecurringPayment(req.params.id, rpUpdates);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.delete('/api/recurring-payments/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireHouseholdRow(db, 'recurring_payments', req.params.id, req, res))) return;
    await db.deleteRecurringPayment(req.params.id);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// ============================================
// Notes (private by default; owner can share to household / a group)
// ============================================

// Resolve the share target group_id from a requested scope. 'household' maps to
// the caller's household; 'group' requires membership in the given group.
async function resolveNoteShare(db, userId, scope, requestedGroupId) {
  if (scope === 'household') return await db.getUserHouseholdId(userId);
  if (scope === 'group') {
    const gid = parseInt(requestedGroupId);
    if (gid && await db.isGroupMember(gid, userId)) return gid;
    return null;
  }
  return null; // private
}

app.get('/api/notes', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const notes = await db.getNotes(req.session.user?.id);
    res.json(notes);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.post('/api/notes', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    const scope = req.body.shared_scope || 'private';
    const groupId = await resolveNoteShare(db, userId, scope, req.body.group_id);
    const result = await db.addNote({
      title: req.body.title, body: req.body.body, color: req.body.color,
      pinned: req.body.pinned, user_id: userId,
      shared_scope: groupId ? scope : 'private',
      group_id: groupId,
    });
    res.json({ success: true, id: result.id });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.put('/api/notes/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    const note = await db.getNoteById(req.params.id);
    if (!note) return res.status(404).json({ error: 'Not found' });

    if (note.user_id === userId) {
      // Owner — full update including sharing + collaboration settings.
      const updates = { ...req.body };
      if (updates.shared_scope !== undefined) {
        const groupId = await resolveNoteShare(db, userId, updates.shared_scope, updates.group_id);
        updates.shared_scope = groupId ? updates.shared_scope : 'private';
        updates.group_id = groupId;
      }
      await db.updateNote(req.params.id, updates, userId);
      return res.json({ success: true, role: 'owner' });
    }

    // Non-owner — allowed only if the note is shared to a group they belong to
    // AND collaboration is enabled. Content fields only.
    const result = await db.updateNoteAsCollaborator(req.params.id, {
      title: req.body.title, body: req.body.body, color: req.body.color,
    }, userId);
    if (!result.changed) return res.status(403).json({ error: 'You cannot edit this note' });
    res.json({ success: true, role: 'collaborator' });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.delete('/api/notes/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const result = await db.deleteNote(req.params.id, req.session.user?.id);
    if (!result.changed) return res.status(403).json({ error: 'Not your note' });
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Budget categories CRUD
app.get('/api/budget-categories', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const groupId = await db.getUserHouseholdId(req.session.user?.id);
    if (!groupId) return res.json([]);
    const categories = await db.getBudgetCategories(groupId);
    res.json(categories);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.post('/api/budget-categories', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const { name, color } = req.body;
    const monthly_limit = parseMoney(req.body.monthly_limit ?? 0);
    if (monthly_limit === null || monthly_limit < 0) {
      return res.status(400).json({ error: 'Invalid monthly limit' });
    }
    const groupId = await db.getUserHouseholdId(req.session.user?.id);
    if (!groupId) return res.status(403).json({ error: 'Join a household first' });
    const result = await db.addBudgetCategory(name, monthly_limit, color, groupId);
    res.json({ success: true, id: result.id });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.put('/api/budget-categories/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireHouseholdRow(db, 'budget_categories', req.params.id, req, res))) return;
    const updates = { ...req.body };
    if ('monthly_limit' in updates) {
      updates.monthly_limit = parseMoney(updates.monthly_limit);
      if (updates.monthly_limit === null || updates.monthly_limit < 0) {
        return res.status(400).json({ error: 'Invalid monthly limit' });
      }
    }
    await db.updateBudgetCategory(req.params.id, updates);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.delete('/api/budget-categories/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireHouseholdRow(db, 'budget_categories', req.params.id, req, res))) return;
    await db.deleteBudgetCategory(req.params.id);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Receipts - save
app.post('/api/receipts', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const groupId = await db.getUserHouseholdId(req.session.user?.id);
    // Never write a NULL-group row: the startup backfill would later re-home
    // it into another household (cross-household leak).
    if (!groupId) return res.status(403).json({ error: 'Join a household first' });
    if (req.body.category) {
      await db.ensureBudgetCategory(req.body.category, groupId);
    }
    const data = { ...req.body, group_id: groupId };
    if ('amount' in data) {
      data.amount = parseMoney(data.amount);
      if (data.amount === null || data.amount < 0) {
        return res.status(400).json({ error: 'Invalid amount' });
      }
    }
    if (data.itinerary_id && !(await requireItineraryAccess(db, data.itinerary_id, req, res))) return;
    if (data.date) data.date = normalizeDate(data.date);
    if (!data.added_by) data.added_by = req.session.user.username || req.session.user.name;
    const result = await db.addReceipt(data);
    res.json({ success: true, id: result.id });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Receipts - scan with Claude Vision
app.post('/api/receipts/scan', requireAuth, conciergeLimiter, aiDailyLimiter, async (req, res) => {
  try {
    const { image } = req.body;

    if (typeof image !== 'string' || image.length === 0) {
      return res.status(400).json({ error: 'Receipt image is required' });
    }

    if (!process.env.ANTHROPIC_API_KEY) {
      // Mock scan result when no API key
      res.json({
        merchant: "Sample Store",
        date: new Date().toISOString().split('T')[0],
        total: 42.50,
        category: "Groceries",
        items: [
          { name: "Milk", price: 4.99, quantity: "1" },
          { name: "Bread", price: 3.49, quantity: "1" },
          { name: "Eggs", price: 5.99, quantity: "1" },
          { name: "Chicken Breast", price: 12.99, quantity: "1" },
          { name: "Apples", price: 6.49, quantity: "1 bag" },
          { name: "Rice", price: 8.55, quantity: "1" }
        ]
      });
      return;
    }

    // The iOS client normalizes library photos to JPEG, but keep this endpoint
    // correct for other clients too: Anthropic rejects a declared media type
    // that does not match the uploaded bytes (HEIC is not supported).
    const imageData = image.replace(/^data:image\/[a-z0-9.+-]+;base64,/i, '');
    const bytes = Buffer.from(imageData, 'base64');
    let mediaType = 'image/jpeg';
    if (bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47) mediaType = 'image/png';
    else if (bytes[0] === 0x47 && bytes[1] === 0x49 && bytes[2] === 0x46) mediaType = 'image/gif';
    else if (bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46 && bytes.slice(8, 12).toString('ascii') === 'WEBP') mediaType = 'image/webp';

    const text = await ai.callClaude({
      maxTokens: 1500,
      messages: [{
        role: 'user',
        content: [
          { type: 'image', source: { type: 'base64', media_type: mediaType, data: imageData } },
          { type: 'text', text: 'Extract receipt data. Use Kids for children\'s clothing, shoes, school supplies, toys, activities, and child-specific purchases. Return ONLY valid JSON: {"merchant":"store name","date":"YYYY-MM-DD","total":0.00,"category":"Groceries|Dining Out|Gas/Transport|Household|Health|Pets|Entertainment|Kids|Other","items":[{"name":"item","price":0.00,"quantity":"1"}]}' }
        ]
      }]
    });
    const receipt = ai.extractJSON(text);
    receipt.category = normalizeReceiptCategory(receipt);
    res.json(receipt);
  } catch (err) {
    const message = String(err?.message || '');
    if (/credit balance|plans? & billing|rate.?limit|overloaded/i.test(message)) {
      console.error('[receipt-scan] upstream unavailable:', message);
      return res.status(503).json({ error: 'Receipt scanning is temporarily unavailable. Please try again later or add the receipt manually.' });
    }
    sendServerError(res, err);
  }
});

// Receipts - save scanned receipt (dual save: expenses + pantry)
app.post('/api/receipts/save', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const { merchant, date, category, notes, itinerary_id } = req.body;
    const total = parseMoney(req.body.total);
    if (total === null || total < 0) {
      return res.status(400).json({ error: 'Invalid receipt total' });
    }
    const username = req.session.user.username || req.session.user.name;
    const groupId = await db.getUserHouseholdId(req.session.user?.id);
    // Never write a NULL-group row: the startup backfill would later re-home
    // it into another household (cross-household leak).
    if (!groupId) return res.status(403).json({ error: 'Join a household first' });

    // Normalize date to YYYY-MM-DD for strftime compatibility
    // If the AI returned a date more than 60 days in the past or in the future, use today
    let normalizedDate = normalizeDate(date);
    const receiptDate = new Date(normalizedDate);
    const now = new Date();
    const diffDays = Math.abs((now - receiptDate) / (1000 * 60 * 60 * 24));
    if (diffDays > 60) {
      console.log(`[receipt-save] AI date "${date}" (${normalizedDate}) is ${Math.round(diffDays)} days off — using today`);
      normalizedDate = now.toISOString().split('T')[0];
    }

    // A receipt may only be attached to an itinerary the caller can access.
    if (itinerary_id && !(await requireItineraryAccess(db, itinerary_id, req, res))) return;

    // Ensure budget category exists (auto-create if new)
    if (category) {
      await db.ensureBudgetCategory(category, groupId);
    }

    // Save receipt
    const receipt = await db.addReceipt({
      amount: total,
      merchant,
      date: normalizedDate,
      category: category || 'Other',
      notes: notes || null,
      processed_by: 'scan',
      added_by: username,
      itinerary_id: itinerary_id || null,
      group_id: groupId
    });

    // Log ids/category only — no amounts, merchant, or usernames (financial PII
    // into the host log pipeline).
    console.log(`[receipt-save] id=${receipt.id} category="${category}" date=${normalizedDate}`);

    // Verify the receipt was actually written
    const verify = await new Promise((resolve, reject) => {
      db.db.get('SELECT id, amount, date, category FROM receipts WHERE id = ?', [receipt.id], (err, row) => err ? reject(err) : resolve(row));
    });
    if (!verify) {
      console.error(`[receipt-save] VERIFICATION FAILED — receipt id=${receipt.id} not found after insert`);
      return res.status(500).json({ error: 'Receipt insert verification failed' });
    }

    res.json({ success: true, id: receipt.id, receipt_id: receipt.id });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

function normalizeReceiptCategory(receipt) {
  const category = typeof receipt.category === 'string' ? receipt.category : 'Other';
  const text = [
    receipt.merchant,
    category,
    ...(Array.isArray(receipt.items) ? receipt.items.map(item => item?.name) : [])
  ].filter(Boolean).join(' ').toLowerCase();

  if (/shoe|sneaker|kids|child|children|youth|school/.test(text)) return 'Kids';
  return category;
}

app.delete('/api/receipts/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireHouseholdRow(db, 'receipts', req.params.id, req, res))) return;
    await db.deleteReceipt(req.params.id);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Helper: normalize date to YYYY-MM-DD for SQLite strftime
// Expand a recurrence rule into dates within [rangeStart, rangeEnd)
function expandRecurrence(rule, origin, rangeStart, rangeEnd, endDate) {
  const dates = [];
  const originDate = new Date(origin);
  const anchorDay = originDate.getDate();
  const step = { daily: 1, weekly: 7, biweekly: 14 }[rule];
  for (let i = 1; i <= 400; i++) {
    let cursor;
    if (step) {
      cursor = new Date(originDate.getTime() + i * step * 86400000);
    } else if (rule === 'monthly' || rule === 'yearly') {
      // Anchor each occurrence to the origin's day-of-month rather than mutating
      // a cursor: setMonth on Jan 31 overflows to Mar 2/3 and the drift compounds
      // forever. Shift from day 1 to avoid overflow, then clamp the anchor day to
      // the target month's length so Jan 31 -> Feb 28/29 -> Mar 31, as expected.
      const monthsToAdd = rule === 'monthly' ? i : i * 12;
      cursor = new Date(originDate);
      cursor.setDate(1);
      cursor.setMonth(originDate.getMonth() + monthsToAdd);
      const daysInMonth = new Date(cursor.getFullYear(), cursor.getMonth() + 1, 0).getDate();
      cursor.setDate(Math.min(anchorDay, daysInMonth));
    } else {
      break;
    }
    if (endDate && cursor > endDate) break;
    if (cursor >= rangeEnd) break;
    if (cursor >= rangeStart) dates.push(new Date(cursor));
  }
  return dates;
}

function normalizeDate(dateStr) {
  if (!dateStr) return todayLocal();
  // Already YYYY-MM-DD
  if (/^\d{4}-\d{2}-\d{2}$/.test(dateStr)) return dateStr;
  // Try parsing with Date constructor
  const parsed = new Date(dateStr);
  if (!isNaN(parsed.getTime())) {
    return parsed.toLocaleDateString('en-CA');
  }
  // Fallback to today
  return todayLocal();
}

// Helper: guess pantry category from item name
function guessItemCategory(name) {
  const n = name.toLowerCase();
  if (/milk|cheese|yogurt|butter|cream/.test(n)) return 'Dairy';
  if (/chicken|beef|pork|fish|salmon|shrimp|meat/.test(n)) return 'Meat';
  if (/apple|banana|tomato|lettuce|onion|potato|carrot|fruit|vegetable/.test(n)) return 'Produce';
  if (/bread|bagel|muffin|roll|bun/.test(n)) return 'Bakery';
  if (/frozen|ice cream|pizza/.test(n)) return 'Frozen';
  if (/rice|pasta|flour|sugar|cereal|oat/.test(n)) return 'Dry Goods';
  if (/water|juice|soda|coffee|tea|beer|wine/.test(n)) return 'Beverages';
  if (/chip|cookie|cracker|candy|snack/.test(n)) return 'Snacks';
  if (/soap|detergent|paper|tissue|cleaner/.test(n)) return 'Household';
  return 'Other';
}

// Helper: guess storage location from item name
function guessLocation(name) {
  const n = name.toLowerCase();
  if (/milk|cheese|yogurt|butter|cream|chicken|beef|fish|egg|juice/.test(n)) return 'fridge';
  if (/frozen|ice cream/.test(n)) return 'freezer';
  if (/banana|apple|bread|potato|onion|tomato/.test(n)) return 'counter';
  return 'pantry';
}

// Pantry CRUD
app.get('/api/pantry', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const filters = {};
    if (req.query.location) filters.location = req.query.location;
    if (req.query.category) filters.category = req.query.category;
    const groupId = await db.getUserHouseholdId(req.session.user?.id);
    if (!groupId) return res.json([]);
    const items = await db.getPantry(filters, groupId);
    res.json(items);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.post('/api/pantry', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const data = { ...req.body };
    if (data.expiry_date) data.expiry_date = normalizeDate(data.expiry_date);
    data.group_id = await db.getUserHouseholdId(req.session.user?.id);
    // Never write a NULL-group row: the startup backfill would later re-home
    // it into another household (cross-household leak).
    if (!data.group_id) return res.status(403).json({ error: 'Join a household first' });
    const result = await db.addPantryItem(data);
    res.json({ success: true, id: result.id });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.put('/api/pantry/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireHouseholdRow(db, 'pantry', req.params.id, req, res))) return;
    const data = { ...req.body };
    if (data.expiry_date) data.expiry_date = normalizeDate(data.expiry_date);
    await db.updatePantryItem(req.params.id, data);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.delete('/api/pantry/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireHouseholdRow(db, 'pantry', req.params.id, req, res))) return;
    await db.deletePantryItem(req.params.id);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Concierge - daily brief (read-only): what needs attention + warm summary
app.get('/api/concierge/brief', requireAuth, conciergeLimiter, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user.id;
    // skipAI: the client will summarize on-device (or has cloud AI off), so the
    // server makes NO Anthropic call — household data never leaves for the brief.
    const skipAI = req.query.skipAI === '1' || req.query.skipAI === 'true';
    const cacheKey = `${userId}:${skipAI ? 'local' : 'cloud'}`;
    const cached = briefCache.get(cacheKey);
    if (!req.query.refresh && cached && Date.now() - cached.ts < BRIEF_TTL_MS) {
      return res.json(cached.brief);
    }
    // Stale-while-revalidate: if a previous brief exists, return it immediately
    // and regenerate off-thread so the request never blocks on the Anthropic
    // call. Explicit ?refresh still waits for the fresh brief.
    if (!req.query.refresh && cached) {
      res.json(cached.brief);
      regenerateBriefInBackground(userId, req.session.user.name, skipAI, cacheKey);
      return;
    }
    // Cold cache (or explicit refresh): generate synchronously.
    const snapshot = await buildSnapshot(db, userId);
    const brief = await generateBrief(snapshot, req.session.user.name, { skipAI });
    const now = Date.now();
    for (const [k, v] of briefCache) if (now - v.ts >= BRIEF_TTL_MS) briefCache.delete(k);
    briefCache.set(cacheKey, { brief, ts: now });
    res.json(brief);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Subscriptions - verify a StoreKit 2 transaction and store household entitlement
app.post('/api/subscription/verify', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const signed = req.body.signed_transaction || req.body.transaction;
    if (!signed) return res.status(400).json({ error: 'signed_transaction required' });
    const status = await subscription.verifyAndStore(db, req.session.user.id, signed);
    _householdEntitlementCache.delete(req.session.user.id); // reflect new/upgraded tier immediately
    res.json(status);
  } catch (err) {
    // Log the real reason server-side; keep the client message opaque.
    console.error('[subscription/verify]', err && err.stack ? err.stack : err);
    res.status(400).json({ error: 'Subscription verification failed' });
  } finally {
    db.close();
  }
});

// App Store Server Notifications (v2) - Apple calls this; auth is the signature.
app.post('/api/subscription/notifications', async (req, res) => {
  const db = new FamilyDB();
  try {
    const signedPayload = req.body.signedPayload;
    if (!signedPayload) return res.status(400).json({ error: 'signedPayload required' });
    const result = await subscription.verifyAndApplyNotification(db, signedPayload);
    res.json(result);
  } catch (err) {
    // Apple is the caller; log details server-side, respond opaquely.
    console.error('[subscription/notifications]', err && err.stack ? err.stack : err);
    res.status(400).json({ error: 'Notification rejected' });
  } finally {
    db.close();
  }
});

// Subscriptions - current household entitlement status
app.get('/api/subscription/status', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    res.json(await subscription.getStatus(db, req.session.user.id));
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Public Concierge plan list (no secrets). Used by the website subscribe page.
app.get('/api/subscription/catalog', (req, res) => {
  res.json({
    stripe: stripeBilling.isConfigured(),
    plans: subscription.CATALOG,
  });
});

// Create a Stripe Checkout Session for a Concierge plan. Bound to the caller's
// household so the webhook can't attach the entitlement anywhere else.
app.post('/api/subscription/checkout', requireAuth, async (req, res) => {
  const productId = String(req.body?.product_id || '');
  if (!subscription.CATALOG.some((p) => p.product_id === productId)) {
    return res.status(400).json({ error: 'Unknown plan' });
  }
  if (!stripeBilling.isConfigured()) {
    return res.status(503).json({ error: 'Web billing is not configured' });
  }
  const db = new FamilyDB();
  try {
    const userId = req.session.user.id;
    const groupId = await db.getUserHouseholdId(userId);
    if (!groupId) return res.status(400).json({ error: 'Join a household before subscribing' });
    const user = await db.getUserById(userId);
    let customerId = null;
    try { customerId = await subscription.stripeCustomerIdForGroup(db, groupId); } catch { /* first purchase */ }
    const base = publicBaseUrl();
    const session = await stripeBilling.createCheckoutSession({
      productId,
      userId,
      groupId,
      customerId,
      customerEmail: (!customerId && user?.email) ? user.email : null,
      successUrl: `${base}/subscribe.html?success=1`,
      cancelUrl: `${base}/subscribe.html?canceled=1`,
    });
    res.json({ url: session.url, id: session.id });
  } catch (err) {
    if (err.status === 400) return res.status(400).json({ error: err.message });
    console.error('[subscription/checkout]', err && err.stack ? err.stack : err);
    res.status(502).json({ error: 'Could not start checkout' });
  } finally {
    db.close();
  }
});

// Stripe Customer Portal — manage payment method / cancel a web subscription.
app.post('/api/subscription/portal', requireAuth, async (req, res) => {
  if (!stripeBilling.isConfigured()) {
    return res.status(503).json({ error: 'Web billing is not configured' });
  }
  const db = new FamilyDB();
  try {
    const groupId = await db.getUserHouseholdId(req.session.user.id);
    if (!groupId) return res.status(400).json({ error: 'No household' });
    const customerId = await subscription.stripeCustomerIdForGroup(db, groupId);
    if (!customerId) return res.status(404).json({ error: 'No web subscription to manage' });
    const session = await stripeBilling.createPortalSession({
      customerId,
      returnUrl: `${publicBaseUrl()}/subscribe.html`,
    });
    res.json({ url: session.url });
  } catch (err) {
    console.error('[subscription/portal]', err && err.stack ? err.stack : err);
    res.status(502).json({ error: 'Could not open billing portal' });
  } finally {
    db.close();
  }
});

// Stripe webhooks. Auth is the signature — never a session cookie.
app.post('/api/subscription/stripe', async (req, res) => {
  const secret = process.env.STRIPE_WEBHOOK_SECRET;
  const raw = Buffer.isBuffer(req.body) ? req.body : Buffer.from(String(req.body || ''), 'utf8');
  if (!stripeBilling.verifyWebhookSignature(raw, req.headers['stripe-signature'], secret)) {
    return res.status(400).json({ error: 'Invalid signature' });
  }
  let event;
  try { event = JSON.parse(raw.toString('utf8')); } catch {
    return res.status(400).json({ error: 'Invalid payload' });
  }
  const db = new FamilyDB();
  try {
    const result = await subscription.applyStripeEvent(db, event);
    _householdEntitlementCache.clear();
    res.json(result);
  } catch (err) {
    console.error('[subscription/stripe]', err && err.stack ? err.stack : err);
    res.status(400).json({ error: 'Event rejected' });
  } finally {
    db.close();
  }
});

// ============================================
// Developer API — bring-your-own-agent (premium)
// ============================================
// Key management uses the normal session auth + premium gate. The `/v1/*`
// surface below authenticates with the minted key instead. See
// docs/DEVELOPER_API.md and services/developerApi.js.

app.get('/api/developer/keys', requireAuth, requirePremium, async (req, res) => {
  const db = new FamilyDB();
  try {
    res.json({ keys: await developerApi.listKeys(db, req.session.user.id) });
  } catch (err) { sendServerError(res, err); }
  finally { db.close(); }
});

app.post('/api/developer/keys', requireAuth, requirePremium, async (req, res) => {
  const db = new FamilyDB();
  try {
    const { name, scope } = req.body || {};
    if (scope !== undefined && scope !== 'read' && scope !== 'write') {
      return res.status(400).json({ error: "scope must be 'read' or 'write'" });
    }
    const created = await developerApi.createKey(db, req.session.user.id, { name, scope });
    res.status(201).json(created);
  } catch (err) {
    if (err.status) return res.status(err.status).json({ error: err.message });
    sendServerError(res, err);
  } finally { db.close(); }
});

app.delete('/api/developer/keys/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const id = parseInt(req.params.id, 10);
    if (!Number.isInteger(id)) return res.status(400).json({ error: 'Invalid key id' });
    // Deliberately NOT premium-gated: a lapsed subscriber must still be able to
    // revoke keys they minted.
    const ok = await developerApi.revokeKey(db, req.session.user.id, id);
    if (!ok) return res.status(404).json({ error: 'Key not found' });
    res.json({ success: true });
  } catch (err) { sendServerError(res, err); }
  finally { db.close(); }
});

// Bearer-key auth for /v1. Opens a DB handle for the request (req.devDb) and
// closes it when the response finishes, so handlers share one connection.
async function requireApiKey(req, res, next) {
  const db = new FamilyDB();
  let closed = false;
  const close = () => { if (!closed) { closed = true; db.close(); } };
  res.on('finish', close);
  res.on('close', close);
  try {
    req.apiKeyAuth = await developerApi.authenticateKey(db, req.get('authorization'));
    req.devDb = db;
    next();
  } catch (err) {
    if (err.status) {
      res.set('WWW-Authenticate', 'Bearer realm="kinrows"');
      return res.status(err.status).json({ error: err.message });
    }
    sendServerError(res, err);
  }
}

// Per-key limiter keyed on the hashed bearer (so a bad key can't be used to
// pollute another key's bucket) — falls back to IP for unauthenticated hits.
const developerLimiter = createRateLimiter({
  windowMs: 60000, max: 120,
  keyFn: req => {
    const m = /^Bearer\s+(\S+)$/i.exec(req.get('authorization') || '');
    return m ? `key:${crypto.createHash('sha256').update(m[1]).digest('hex').slice(0, 16)}` : `ip:${clientIp(req)}`;
  },
});

app.use('/v1', developerLimiter, requireApiKey);

app.get('/v1/me', async (req, res) => {
  try { res.json(await developerApi.whoami(req.devDb, req.apiKeyAuth)); }
  catch (err) { sendServerError(res, err); }
});

// Household snapshot (same digest the Concierge daily brief is built from).
app.get('/v1/snapshot', async (req, res) => {
  try { res.json(await developerApi.snapshot(req.devDb, req.apiKeyAuth)); }
  catch (err) { sendServerError(res, err); }
});

// Tool catalog. ?format=openai returns OpenAI function-calling shape.
app.get('/v1/tools', (req, res) => {
  res.json({ tools: developerApi.catalog(req.query.format === 'openai' ? 'openai' : 'anthropic') });
});

app.post('/v1/tools/:name', async (req, res) => {
  try {
    const out = await developerApi.callTool(req.devDb, req.apiKeyAuth, req.params.name, req.body);
    if (out.forbidden) return res.status(403).json({ error: out.result.error });
    const payload = out?.result ?? out;
    if (payload && typeof payload === 'object' && payload.error) return res.status(400).json(payload);
    res.json({ result: payload });
  } catch (err) { sendServerError(res, err); }
});

// MCP Streamable HTTP endpoint (stateless). Accepts a single JSON-RPC message
// or a batch; notifications get 202 with no body.
app.post('/v1/mcp', async (req, res) => {
  try {
    const body = req.body;
    const batch = Array.isArray(body);
    const msgs = batch ? body : [body];
    const replies = [];
    for (const m of msgs) {
      const r = await developerApi.handleMcp(req.devDb, req.apiKeyAuth, m);
      if (r) replies.push(r);
    }
    if (!replies.length) return res.status(202).end();
    res.json(batch ? replies : replies[0]);
  } catch (err) { sendServerError(res, err); }
});
app.get('/v1/mcp', (req, res) => res.status(405).json({ error: 'This MCP server is stateless; use POST.' }));
app.delete('/v1/mcp', (req, res) => res.status(204).end());

app.use('/v1', (req, res) => res.status(404).json({ error: 'Not found' }));

// Concierge - conversational chat with tool-calling (premium)
app.post('/api/concierge/chat', requireAuth, conciergeLimiter, conciergeChatDailyLimiter, requirePremium, async (req, res) => {
  const db = new FamilyDB();
  try {
    const message = (req.body.message || '').trim();
    if (!message) return res.status(400).json({ error: 'message required' });
    if (message.length > 8000) return res.status(400).json({ error: 'message too long' });
    const result = await handleChat(db, {
      userId: req.session.user.id,
      userName: req.session.user.name,
      message,
      conversationId: req.body.conversation_id || null,
      source: req.body.source || 'text',
    });
    res.json(result);
  } catch (err) {
    // Surface intentional, client-safe errors (err.status set); keep unexpected 500s opaque.
    if (err.status) { res.status(err.status).json({ error: err.message }); }
    else { sendServerError(res, err); }
  } finally {
    db.close();
  }
});

// Concierge - streaming chat (SSE). Same tool-calling loop as /chat, but text
// is streamed token-by-token. The non-streaming endpoint above stays as a
// fallback. Gating runs before any SSE bytes; once streaming starts, errors are
// delivered as `error` events.
app.post('/api/concierge/chat/stream', requireAuth, conciergeLimiter, conciergeChatDailyLimiter, requirePremium, async (req, res) => {
  const db = new FamilyDB();
  try {
    const message = (req.body.message || '').trim();
    if (!message) return res.status(400).json({ error: 'message required' });
    if (message.length > 8000) return res.status(400).json({ error: 'message too long' });

    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');
    res.setHeader('X-Accel-Buffering', 'no'); // disable proxy buffering so deltas flush
    if (res.flushHeaders) res.flushHeaders();

    const send = (event, data) => {
      res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
      if (typeof res.flush === 'function') res.flush();
    };

    try {
      const result = await handleChatStream(db, {
        userId: req.session.user.id,
        userName: req.session.user.name,
        message,
        conversationId: req.body.conversation_id || null,
        source: req.body.source || 'text',
      }, {
        onText: (t) => send('delta', { text: t }),
        onAction: (action) => send('action', action),
      });
      send('done', result);
    } catch (err) {
      send('error', { error: err.status ? err.message : 'Something went wrong.' });
    }
    res.end();
  } catch (err) {
    if (!res.headersSent) sendServerError(res, err);
    else { try { res.end(); } catch { /* already closed */ } }
  } finally {
    db.close();
  }
});

// Concierge - list the user's past conversations (premium, resumable history)
app.get('/api/concierge/conversations', requireAuth, conciergeLimiter, requirePremium, async (req, res) => {
  const db = new FamilyDB();
  try {
    const rows = await db.getConciergeConversations(req.session.user.id);
    res.json(rows);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Concierge - messages for one conversation (must belong to the caller)
app.get('/api/concierge/conversations/:id/messages', requireAuth, conciergeLimiter, requirePremium, async (req, res) => {
  const db = new FamilyDB();
  try {
    const convo = await db.getConciergeConversation(req.params.id);
    if (!convo || convo.user_id !== req.session.user.id) {
      return res.status(404).json({ error: 'Conversation not found' });
    }
    const messages = await db.getConciergeMessages(req.params.id, 100);
    res.json(messages);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Concierge - list the household's remembered facts (so they can be reviewed/cleared)
app.get('/api/concierge/memory', requireAuth, requirePremium, async (req, res) => {
  const db = new FamilyDB();
  try {
    const groupId = await db.getUserHouseholdId(req.session.user.id);
    const rows = groupId ? await db.getConciergeMemory(groupId) : [];
    res.json(rows.map(r => ({ id: r.id, content: r.content, created_at: r.created_at })));
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Concierge - forget one remembered fact (must be in the caller's household)
app.delete('/api/concierge/memory/:id', requireAuth, requirePremium, async (req, res) => {
  const db = new FamilyDB();
  try {
    const groupId = await db.getUserHouseholdId(req.session.user.id);
    const row = await dbGet(db, 'SELECT group_id FROM concierge_memory WHERE id = ?', [req.params.id]);
    if (!row || groupId == null || row.group_id !== groupId) return res.status(404).json({ error: 'Not found' });
    await dbRun(db, 'DELETE FROM concierge_memory WHERE id = ?', [req.params.id]);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Concierge - delete one of the caller's own conversations (and its messages)
app.delete('/api/concierge/conversations/:id', requireAuth, requirePremium, async (req, res) => {
  const db = new FamilyDB();
  try {
    const convo = await db.getConciergeConversation(req.params.id);
    if (!convo || convo.user_id !== req.session.user.id) return res.status(404).json({ error: 'Not found' });
    await dbRun(db, 'DELETE FROM concierge_messages WHERE conversation_id = ?', [req.params.id]);
    await dbRun(db, 'DELETE FROM concierge_conversations WHERE id = ?', [req.params.id]);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Cook - recipe suggestions (requires ANTHROPIC_API_KEY env var)
app.post('/api/cook/suggest', requireAuth, conciergeLimiter, aiDailyLimiter, async (req, res) => {
  const db = new FamilyDB();
  try {
    const groupId = await db.getUserHouseholdId(req.session.user?.id);
    if (!groupId) return res.status(403).json({ error: 'Join a household first' });
    const pantryItems = await db.getPantry({}, groupId);
    const pantryList = pantryItems.map(i => i.item + ' (' + (i.quantity || 1) + (i.unit ? ' ' + i.unit : '') + ')').join(', ');
    const query = req.body.query || 'What can I make for dinner?';

    // If no API key, return mock recipes
    if (!process.env.ANTHROPIC_API_KEY) {
      res.json({
        recipes: [
          {
            name: "Quick Pasta",
            cook_time: 20,
            difficulty: "Easy",
            servings: 4,
            ingredients: pantryItems.slice(0, 4).map(i => ({ name: i.item, quantity: i.quantity, available: true }))
              .concat([{ name: "Parmesan cheese", quantity: "1/2 cup", available: false }]),
            steps: ["Boil water and cook pasta", "Sauté garlic in olive oil", "Combine and season", "Serve with parmesan"]
          },
          {
            name: "Simple Stir Fry",
            cook_time: 15,
            difficulty: "Easy",
            servings: 4,
            ingredients: pantryItems.slice(0, 3).map(i => ({ name: i.item, quantity: i.quantity, available: true }))
              .concat([{ name: "Soy sauce", quantity: "2 tbsp", available: false }]),
            steps: ["Heat oil in wok", "Add vegetables and stir fry", "Add sauce", "Serve over rice"]
          },
          {
            name: "Family Salad Bowl",
            cook_time: 10,
            difficulty: "Easy",
            servings: 4,
            ingredients: pantryItems.slice(0, 5).map(i => ({ name: i.item, quantity: i.quantity, available: true }))
              .concat([{ name: "Feta cheese", quantity: "1/4 cup", available: false }]),
            steps: ["Wash and chop vegetables", "Prepare dressing", "Toss together", "Top with cheese and serve"]
          }
        ]
      });
      return;
    }

    // Call Claude API for real suggestions
    const text = await ai.callClaude({
      maxTokens: 2000,
      messages: [{
        role: 'user',
        content: `You are a helpful cooking assistant for a family. Here is what's in their pantry: ${pantryList}

Their question: ${query}

Suggest exactly 3 recipes. Return ONLY valid JSON with this structure:
{"recipes": [{"name": "...", "cook_time": 20, "difficulty": "Easy|Medium|Hard", "servings": 4, "ingredients": [{"name": "...", "quantity": "...", "available": true/false}], "steps": ["step 1", "step 2"]}]}

Mark ingredients as available:true if they're in the pantry list, available:false if not.`
      }]
    });
    res.json(ai.extractJSON(text));
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Cook - deduct ingredients from pantry
app.post('/api/cook/deduct', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const { ingredients } = req.body;
    if (!Array.isArray(ingredients)) return res.status(400).json({ error: 'ingredients must be an array' });
    const groupId = await db.getUserHouseholdId(req.session.user?.id);
    if (!groupId) return res.status(403).json({ error: 'Join a household first' });
    const pantryItems = await db.getPantry({}, groupId);
    for (const name of ingredients) {
      const match = pantryItems.find(p => p.item.toLowerCase() === name.toLowerCase());
      if (match) {
        const qty = parseInt(match.quantity) || 1;
        if (qty <= 1) {
          await db.deletePantryItem(match.id);
        } else {
          await db.updatePantryItem(match.id, { quantity: String(qty - 1) });
        }
      }
    }
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Trips
app.get('/api/trips', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const filters = {};
    if (req.query.status) filters.status = req.query.status;
    if (req.query.traveler) filters.traveler = req.query.traveler;
    const groupId = await db.getUserHouseholdId(req.session.user?.id);
    if (!groupId) return res.json([]);
    const trips = await db.getTrips(filters, groupId);
    res.json(trips);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.post('/api/trips', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const groupId = await db.getUserHouseholdId(req.session.user?.id);
    if (!groupId) return res.status(403).json({ error: 'Join a household first' });
    const result = await db.createTrip({ ...req.body, group_id: groupId });
    res.json({ success: true, id: result.id });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.put('/api/trips/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireHouseholdRow(db, 'trips', req.params.id, req, res))) return;
    await db.updateTrip(req.params.id, req.body);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.post('/api/trips/:id/arrive', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireHouseholdRow(db, 'trips', req.params.id, req, res))) return;
    await db.arriveTrip(req.params.id);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.post('/api/trips/:id/cancel', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireHouseholdRow(db, 'trips', req.params.id, req, res))) return;
    await db.cancelTrip(req.params.id);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.delete('/api/trips/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireHouseholdRow(db, 'trips', req.params.id, req, res))) return;
    await db.deleteTrip(req.params.id);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Family addresses
app.get('/api/addresses', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const groupId = await db.getUserHouseholdId(req.session.user?.id);
    if (!groupId) return res.json([]);
    const addresses = await db.getFamilyAddresses(groupId);
    res.json(addresses);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.post('/api/addresses', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const groupId = await db.getUserHouseholdId(req.session.user?.id);
    if (!groupId) return res.status(403).json({ error: 'Join a household first' });
    const result = await db.addFamilyAddress({ ...req.body, group_id: groupId });
    res.json({ success: true, id: result.id });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.put('/api/addresses/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireHouseholdRow(db, 'family_addresses', req.params.id, req, res))) return;
    const { name, address, lat, lng } = req.body;
    const fields = [];
    const params = [];
    if (name) { fields.push('name = ?'); params.push(name); }
    if (address !== undefined) { fields.push('address = ?'); params.push(address); }
    if (lat !== undefined) { fields.push('lat = ?'); params.push(lat); }
    if (lng !== undefined) { fields.push('lng = ?'); params.push(lng); }
    if (fields.length === 0) return res.status(400).json({ error: 'Nothing to update' });
    params.push(req.params.id);
    await new Promise((resolve, reject) => {
      db.db.run(`UPDATE family_addresses SET ${fields.join(', ')} WHERE id = ?`, params, (err) => err ? reject(err) : resolve());
    });
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.delete('/api/addresses/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireHouseholdRow(db, 'family_addresses', req.params.id, req, res))) return;
    await db.deleteFamilyAddress(req.params.id);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Decisions
app.get('/api/decisions', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const decisions = await db.getDecisions({ status: req.query.status }, req.session.user.id);
    res.json(decisions);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.get('/api/decisions/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireGroupRow(db, 'decisions', req.params.id, req, res))) return;
    const decision = await db.getDecisionById(req.params.id);
    if (!decision) return res.status(404).json({ error: 'Not found' });
    res.json(decision);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.post('/api/decisions', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const data = { ...req.body };
    const userId = req.session.user.id;
    const senderName = req.session.user.name;
    // Decisions are clan-shareable: a supplied group_id must be a group the caller
    // belongs to (clan or household); otherwise default to their household.
    const decisionGid = await resolveCreateGroupId(db, userId, data.group_id, { householdOnly: false });
    if (decisionGid == null) return res.status(403).json({ error: 'Cannot create a decision in that group' });
    data.group_id = decisionGid;
    // Optional "about <person>" tag: must be a person in the caller's own
    // household (people stay household-scoped even on clan-shared decisions).
    if (data.person_id != null && data.person_id !== '') {
      if (!(await personBelongsToCallerHousehold(db, userId, data.person_id))) {
        return res.status(403).json({ error: 'Cannot tag that person' });
      }
    }
    const result = await db.addDecision(data);
    res.json({ success: true, id: result.id });
    // Push to household members
    if (data.group_id) {
      jobs.pushToGroup(db, data.group_id, userId, `${senderName} needs your input`, data.title || 'New decision', { type: 'decision', ref_id: result.id });
    }
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.put('/api/decisions/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireGroupRow(db, 'decisions', req.params.id, req, res))) return;
    if (req.body.person_id != null && req.body.person_id !== '') {
      if (!(await personBelongsToCallerHousehold(db, req.session.user.id, req.body.person_id))) {
        return res.status(403).json({ error: 'Cannot tag that person' });
      }
    }
    await db.updateDecision(req.params.id, req.body);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.delete('/api/decisions/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  const run = (sql, params) => new Promise((resolve, reject) => {
    db.db.run(sql, params, (err) => err ? reject(err) : resolve());
  });
  try {
    if (!(await requireGroupRow(db, 'decisions', req.params.id, req, res))) return;
    await run('DELETE FROM decision_reactions WHERE decision_id = ?', [req.params.id]);
    await run('DELETE FROM decision_comments WHERE decision_id = ?', [req.params.id]);
    await run('DELETE FROM decisions WHERE id = ?', [req.params.id]);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.get('/api/decisions/:id/reactions', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireGroupRow(db, 'decisions', req.params.id, req, res))) return;
    const reactions = await db.getDecisionReactions(req.params.id);
    res.json(reactions);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.post('/api/decisions/:id/reactions', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireGroupRow(db, 'decisions', req.params.id, req, res))) return;
    const { reaction_type, poll_choice } = req.body;
    // Attribute to the authenticated user — never trust a client-supplied name
    // (prevents voting/commenting as someone else).
    await db.replaceDecisionReaction(req.params.id, req.session.user.name, reaction_type, poll_choice);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.get('/api/decisions/:id/comments', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireGroupRow(db, 'decisions', req.params.id, req, res))) return;
    const comments = await db.getDecisionComments(req.params.id);
    res.json(comments);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.post('/api/decisions/:id/comments', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireGroupRow(db, 'decisions', req.params.id, req, res))) return;
    await db.addDecisionComment(req.params.id, req.session.user.name, req.body.text);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Rivalries
app.get('/api/rivalries', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const rivalries = await db.getRivalries({ status: req.query.status }, req.session.user.id);
    res.json(rivalries);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.post('/api/rivalries', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const data = { ...req.body };
    if (data.start_date) data.start_date = normalizeDate(data.start_date);
    if (data.end_date) data.end_date = normalizeDate(data.end_date);
    if (data.group_id != null && data.group_id !== '') {
      // A supplied group_id must be a valid group the caller belongs to (no
      // injecting a rivalry into someone else's clan/household).
      const gid = parseInt(data.group_id);
      if (!Number.isInteger(gid) || !(await db.isGroupMember(gid, req.session.user.id))) {
        return res.status(403).json({ error: 'Cannot create a rivalry in that group' });
      }
      data.group_id = gid;
    } else {
      // For 1v1 rivalries, find the shared group between participants (server-derived).
      if (data.initiator_name && data.opponent_name) {
        data.group_id = await db.getSharedGroupByNames(data.initiator_name, data.opponent_name);
      }
      // The derived group must actually contain the caller — otherwise the two
      // body-supplied names could point at a group the caller isn't in, letting
      // them inject a rivalry (and spoofed "challenged you" pushes) into a
      // household/clan they don't belong to. Fall back to the caller's own household.
      if (!data.group_id || !(await db.isGroupMember(data.group_id, req.session.user.id))) {
        data.group_id = await db.getUserHouseholdId(req.session.user.id);
      }
    }
    const result = await db.addRivalry(data);
    res.json({ success: true, id: result.id });

    // Push notification to all opponents
    const senderName = req.session.user.name || data.initiator_name;
    let opponents = [];
    if (data.participants) {
      try { opponents = JSON.parse(data.participants).filter(n => n !== senderName); } catch {}
    }
    if (!opponents.length && data.opponent_name) opponents = [data.opponent_name];
    const ct = (data.challenge_type || 'challenge').replace(/_/g, ' ');
    for (const opName of opponents) {
      const opId = await db.getUserIdByName(opName, data.group_id);
      if (opId) {
        jobs.pushToUser(db, opId, `${senderName} challenged you!`,
          pick(RIVALRY_CHALLENGE_PUSH)(senderName, ct),
          { type: 'rivalry', ref_id: result.id });
      }
    }
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.put('/api/rivalries/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireGroupRow(db, 'rivalries', req.params.id, req, res))) return;
    const data = { ...req.body };
    if (data.start_date) data.start_date = normalizeDate(data.start_date);
    if (data.end_date) data.end_date = normalizeDate(data.end_date);
    await db.updateRivalry(req.params.id, data);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.delete('/api/rivalries/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireGroupRow(db, 'rivalries', req.params.id, req, res))) return;
    await db.deleteRivalry(req.params.id);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.get('/api/rivalries/:id/entries', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireGroupRow(db, 'rivalries', req.params.id, req, res))) return;
    const entries = await db.getRivalryEntries(req.params.id);
    res.json(entries);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.post('/api/rivalries/:id/entries', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireGroupRow(db, 'rivalries', req.params.id, req, res))) return;
    const rivalryId = Number(req.params.id);
    const entry = { ...req.body, rivalry_id: rivalryId };
    // Scores must be numeric — string values would make SUM() silently drop them.
    entry.value = parseMoney(entry.value);
    if (entry.value === null) {
      return res.status(400).json({ error: 'Invalid entry value' });
    }
    // member_name must be an actual participant of this rivalry — otherwise a
    // group member could log entries under an arbitrary name to rig totals or
    // fire false "you're behind" pushes.
    const rivalryRow = await db.getRivalryById(rivalryId);
    let rosterNames;
    try { rosterNames = JSON.parse(rivalryRow?.participants || '[]'); } catch { rosterNames = []; }
    if (!rosterNames.length) rosterNames = [rivalryRow?.initiator_name, rivalryRow?.opponent_name];
    const isParticipant = rosterNames
      .filter(Boolean)
      .some(n => n.toLowerCase() === String(entry.member_name || '').toLowerCase());
    if (!isParticipant) {
      return res.status(400).json({ error: 'member_name must be a participant of this rivalry' });
    }
    await db.addRivalryEntry(entry);
    res.json({ success: true });

    // Send score-update push to other participants
    try {
      const rivalry = await db.getRivalryById(rivalryId);
      if (rivalry && rivalry.status === 'active') {
        const totals = await db.getRivalryEntryTotals(rivalryId);
        let participants;
        try { participants = JSON.parse(rivalry.participants || '[]'); } catch { participants = []; }
        if (!participants.length) participants = [rivalry.initiator_name, rivalry.opponent_name];

        const loggerName = entry.member_name;
        const ct = (rivalry.challenge_type || 'challenge').replace(/_/g, ' ');
        const nameMatch = (a, b) => {
          const aL = a.toLowerCase(), bL = b.toLowerCase();
          return aL === bL || aL.startsWith(bL + ' ') || bL.startsWith(aL + ' ');
        };
        const findTotal = (name) => totals.find(t => nameMatch(t.member_name, name))?.total || 0;

        for (const pName of participants) {
          if (nameMatch(pName, loggerName)) continue;
          const pId = await db.getUserIdByName(pName, rivalry.group_id);
          if (!pId) continue;

          const myTotal = findTotal(pName);
          const theirTotal = findTotal(loggerName);
          const diff = Math.abs(myTotal - theirTotal);
          const fmtDiff = fmt(diff);

          if (theirTotal > myTotal && diff > 0) {
            // They pulled ahead of this participant
            jobs.pushToUser(db, pId, rivalry.title, pick(RIVALRY_AHEAD_PUSH)(loggerName, fmtDiff, ct), { type: 'rivalry', ref_id: rivalryId });
          } else if (myTotal > theirTotal) {
            // This participant is still ahead
            jobs.pushToUser(db, pId, rivalry.title, pick(RIVALRY_BEHIND_PUSH)(loggerName, ct), { type: 'rivalry', ref_id: rivalryId });
          } else if (diff === 0 && myTotal > 0) {
            // Tied
            jobs.pushToUser(db, pId, rivalry.title, `It's a dead tie with ${loggerName}! ${fmt(myTotal)} ${ct} each`, { type: 'rivalry', ref_id: rivalryId });
          } else if (diff > 0 && diff <= myTotal * 0.1) {
            // Very close
            jobs.pushToUser(db, pId, rivalry.title, pick(RIVALRY_CLOSE_PUSH)(loggerName, fmtDiff, ct), { type: 'rivalry', ref_id: rivalryId });
          }
        }
      }
    } catch (pushErr) {
      console.error('Rivalry entry push error:', pushErr.message);
    }
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Rivalry completion with announcements
const RIVALRY_CHALLENGE_PUSH = [
  (name, ct) => `Think you can keep up? ${name} wants a ${ct} showdown!`,
  (name, ct) => `${name} just threw down the gauntlet — ${ct} challenge. You in?`,
  (name, ct) => `${name} thinks they can beat you at ${ct}. Prove them wrong!`,
  (name, ct) => `Game on! ${name} started a ${ct} challenge with you`,
  (name, ct) => `${name} is feeling brave — they want a ${ct} battle!`,
];
const RIVALRY_AHEAD_PUSH = [
  (name, lead, ct) => `${name} just pulled ahead by ${lead} ${ct}! Time to step it up`,
  (name, lead, ct) => `Uh oh — ${name} is now leading by ${lead} ${ct}. Can you catch up?`,
  (name, lead, ct) => `${name} logged more ${ct} and leads by ${lead}. Don't let them run away with it!`,
];
const RIVALRY_BEHIND_PUSH = [
  (name, ct) => `Nice work! You just took the lead over ${name} in ${ct}!`,
  (name, ct) => `You're ahead of ${name} now — keep the pressure on!`,
  (name, ct) => `${name} is eating your dust! You pulled ahead in ${ct}`,
];
const RIVALRY_CLOSE_PUSH = [
  (name, diff, ct) => `It's neck and neck with ${name} — only ${diff} ${ct} apart!`,
  (name, diff, ct) => `You and ${name} are just ${diff} ${ct} apart. Every bit counts!`,
];
// Winner/tie completion messages + win/loss pushes moved to
// services/rivalryAnnounce.js (shared with the concierge tool).
function fmt(n) { return Number(n).toLocaleString('en-US', { maximumFractionDigits: 0 }); }
function pick(arr) { return arr[Math.floor(Math.random() * arr.length)]; }

app.post('/api/rivalries/:id/complete', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireGroupRow(db, 'rivalries', req.params.id, req, res))) return;
    const result = await db.completeRivalryWithTotals(Number(req.params.id));
    const { initiator_total, opponent_total, winner_name, winner_team } = result;
    // Shared with the concierge's complete_rivalry tool (feed post + pushes).
    const message = await announceRivalryCompletion(db, jobs, result, req.session.user.id);
    const scores = result.scores || [];
    res.json({ success: true, winner_name, winner_team: winner_team || null, initiator_total, opponent_total, scores, message, is_tie: !winner_name });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.get('/api/rivalries/leaderboard', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const rows = await db.getRivalryLeaderboard(req.session.user.id);
    res.json(rows);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Itineraries
app.get('/api/itineraries', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const itineraries = await db.getItineraries(req.session.user.id);
    res.json(itineraries);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.post('/api/itineraries', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const data = { ...req.body };
    data.traveler_id = req.session.user.id;
    data.traveler_name = req.session.user.name;
    // Validate any caller-supplied group_id against membership (don't trust the body).
    const groupId = await resolveCreateGroupId(db, req.session.user.id, req.body.group_id);
    if (groupId == null) return res.status(403).json({ error: 'Forbidden' });
    data.group_id = groupId;
    const result = await db.createItinerary(data);
    res.json({ success: true, id: result.id });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.put('/api/itineraries/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const itinerary = await db.getItineraryById(req.params.id);
    if (!itinerary || itinerary.traveler_id !== req.session.user.id) {
      return res.status(403).json({ error: 'Forbidden' });
    }
    await db.updateItinerary(req.params.id, req.body);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.delete('/api/itineraries/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const itinerary = await db.getItineraryById(req.params.id);
    if (!itinerary || itinerary.traveler_id !== req.session.user.id) {
      return res.status(403).json({ error: 'Forbidden' });
    }
    await db.deleteItinerary(req.params.id);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.get('/api/itineraries/:id/expenses', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireItineraryAccess(db, req.params.id, req, res))) return;
    const expenses = await db.getItineraryExpenses(req.params.id);
    const totals = await db.getItineraryExpenseTotal(req.params.id);
    res.json({ expenses, total: totals.total, count: totals.count });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.get('/api/itineraries/:id/stays', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const itinerary = await db.getItineraryById(req.params.id);
    if (!itinerary) return res.status(404).json({ error: 'Not found' });
    const userId = req.session.user.id;
    if (itinerary.traveler_id !== userId) {
      // Check if user is in the same group
      const groups = await new Promise((resolve, reject) => {
        db.db.all('SELECT group_id FROM group_members WHERE user_id = ?', [userId], (err, rows) => err ? reject(err) : resolve(rows || []));
      });
      const groupIds = groups.map(g => g.group_id);
      if (!itinerary.group_id || !groupIds.includes(itinerary.group_id)) {
        return res.status(403).json({ error: 'Forbidden' });
      }
    }
    const stays = await db.getItineraryStays(req.params.id);
    res.json(stays);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.post('/api/itineraries/:id/stays', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const itinerary = await db.getItineraryById(req.params.id);
    if (!itinerary || itinerary.traveler_id !== req.session.user.id) {
      return res.status(403).json({ error: 'Forbidden' });
    }
    const stay = { ...req.body, itinerary_id: Number(req.params.id) };
    // A host must be someone the traveler actually shares a group with —
    // otherwise a stay request would push "X wants to stay with you" (with dates
    // and notes) to an arbitrary user id.
    if (stay.host_user_id != null && stay.host_user_id !== '') {
      const hostId = parseInt(stay.host_user_id);
      if (!Number.isInteger(hostId) || !(await usersShareGroup(db, req.session.user.id, hostId))) {
        return res.status(403).json({ error: 'Host must be someone you share a household or clan with' });
      }
      stay.host_user_id = hostId;
    }
    const result = await db.addItineraryStay(stay);
    res.json({ success: true, id: result.id });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.put('/api/itineraries/:id/stays/:stayId', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const itinerary = await db.getItineraryById(req.params.id);
    if (!itinerary || itinerary.traveler_id !== req.session.user.id) {
      return res.status(403).json({ error: 'Forbidden' });
    }
    const stayUpdates = { ...req.body };
    if (stayUpdates.host_user_id != null && stayUpdates.host_user_id !== '') {
      const hostId = parseInt(stayUpdates.host_user_id);
      if (!Number.isInteger(hostId) || !(await usersShareGroup(db, req.session.user.id, hostId))) {
        return res.status(403).json({ error: 'Host must be someone you share a household or clan with' });
      }
      stayUpdates.host_user_id = hostId;
    }
    await db.updateItineraryStay(req.params.stayId, stayUpdates, req.params.id);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.delete('/api/itineraries/:id/stays/:stayId', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const itinerary = await db.getItineraryById(req.params.id);
    if (!itinerary || itinerary.traveler_id !== req.session.user.id) {
      return res.status(403).json({ error: 'Forbidden' });
    }
    await db.deleteItineraryStay(req.params.stayId, req.params.id);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Send stay request to host
app.post('/api/stays/:stayId/request', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const stay = await db.getItineraryStayById(req.params.stayId);
    if (!stay) return res.status(404).json({ error: 'Stay not found' });

    const itinerary = await db.getItineraryById(stay.itinerary_id);
    if (!itinerary || itinerary.traveler_id !== req.session.user.id) {
      return res.status(403).json({ error: 'Forbidden' });
    }

    await db.updateItineraryStay(stay.id, { status: 'requested' });

    // Push notification to host if they're an app user
    if (stay.host_user_id) {
      const itinerary = await db.getItineraryById(stay.itinerary_id);
      const traveler = itinerary?.traveler_name || 'Someone';
      jobs.pushToUser(db, stay.host_user_id,
        `${traveler} wants to stay with you`,
        `${stay.check_in} to ${stay.check_out}${stay.notes ? ' — ' + stay.notes : ''}`,
        { type: 'stay_request', ref_id: stay.id }
      );
    }

    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Host responds to stay request
app.post('/api/stays/:stayId/respond', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const stay = await db.getItineraryStayById(req.params.stayId);
    if (!stay) return res.status(404).json({ error: 'Stay not found' });

    if (stay.host_user_id !== req.session.user.id) {
      return res.status(403).json({ error: 'Forbidden' });
    }

    // Only a requested stay can be responded to — a retried/duplicated POST
    // would otherwise create a second pair of calendar events.
    if (stay.status !== 'requested') {
      return res.status(409).json({ error: `Stay is ${stay.status || 'draft'}, not awaiting a response` });
    }

    const { approved } = req.body;
    const itinerary = await db.getItineraryById(stay.itinerary_id);
    const travelerName = itinerary?.traveler_name || 'Visitor';
    const hostName = req.session.user.name;

    if (approved) {
      // Create calendar event for traveler — scope to the TRAVELER's household,
      // not the itinerary's group. Itineraries can live in a clan group, but
      // appointments are only read/edited through household-scoped queries, so a
      // clan-scoped event would be invisible and permanently uneditable.
      const travelerGroupId = itinerary?.traveler_id
        ? await db.getUserHouseholdId(itinerary.traveler_id)
        : null;
      const travelerEvent = await db.addAppointment({
        title: `Staying at ${hostName}'s`,
        appointment_date: stay.check_in,
        description: `${stay.check_in} to ${stay.check_out}${stay.location_name ? ' · ' + stay.location_name : ''}`,
        location: stay.address || stay.location_name || null,
        category: 'social',
        with_person: hostName,
        group_id: travelerGroupId
      });

      // Create calendar event for host
      const hostGroupId = await db.getUserHouseholdId(req.session.user.id);
      const hostEvent = await db.addAppointment({
        title: `${travelerName} visiting`,
        appointment_date: stay.check_in,
        description: `${stay.check_in} to ${stay.check_out}`,
        location: stay.address || stay.location_name || null,
        category: 'social',
        with_person: travelerName,
        group_id: hostGroupId
      });

      await db.updateItineraryStay(stay.id, {
        status: 'confirmed',
        calendar_event_id: travelerEvent.id,
        host_calendar_event_id: hostEvent.id
      });

      // Notify traveler
      if (itinerary?.traveler_id) {
        jobs.pushToUser(db, itinerary.traveler_id,
          `${hostName} confirmed your stay!`,
          `${stay.check_in} to ${stay.check_out} is all set`,
          { type: 'stay_confirmed', ref_id: stay.id }
        );
      }
    } else {
      await db.updateItineraryStay(stay.id, { status: 'declined' });

      // Notify traveler
      if (itinerary?.traveler_id) {
        jobs.pushToUser(db, itinerary.traveler_id,
          `${hostName} can't host ${stay.check_in} to ${stay.check_out}`,
          'You may need to adjust your itinerary',
          { type: 'stay_declined', ref_id: stay.id }
        );
      }
    }

    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Get pending stay requests for current user (as host)
app.get('/api/stays/pending', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const pending = await db.getPendingStayRequests(req.session.user.id);
    res.json(pending);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Gifts
app.get('/api/gifts/people', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const groupId = await db.getUserHouseholdId(req.session.user?.id);
    if (!groupId) return res.json([]);
    const people = await db.getGiftPeople(groupId);
    res.json(people);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.post('/api/gifts/people', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const groupId = await db.getUserHouseholdId(req.session.user?.id);
    if (!groupId) return res.status(403).json({ error: 'Join a household first' });
    const result = await db.addGiftPerson({ ...req.body, group_id: groupId });
    res.json({ success: true, id: result.id });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.get('/api/gifts/ideas', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const groupId = await db.getUserHouseholdId(req.session.user?.id);
    if (!groupId) return res.json([]);
    const ideas = await db.getGiftIdeas(req.query.person_id ? Number(req.query.person_id) : null, groupId);
    res.json(ideas);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.post('/api/gifts/ideas', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const groupId = await db.getUserHouseholdId(req.session.user?.id);
    if (!groupId) return res.status(403).json({ error: 'Join a household first' });
    const result = await db.addGiftIdea({ ...req.body, group_id: groupId });
    res.json({ success: true, id: result.id });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.put('/api/gifts/ideas/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireHouseholdRow(db, 'gift_ideas', req.params.id, req, res))) return;
    await db.updateGiftIdea(req.params.id, req.body);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.delete('/api/gifts/ideas/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireHouseholdRow(db, 'gift_ideas', req.params.id, req, res))) return;
    await db.deleteGiftIdea(req.params.id);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.get('/api/gifts/events', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const groupId = await db.getUserHouseholdId(req.session.user?.id);
    if (!groupId) return res.json([]);
    const events = await db.getSpecialEvents(groupId, req.session.user?.id);
    res.json(events);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.post('/api/gifts/events', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const data = { ...req.body };
    if (data.date) data.date = normalizeDate(data.date);
    data.group_id = await db.getUserHouseholdId(req.session.user?.id);
    if (!data.group_id) return res.status(403).json({ error: 'Join a household first' });
    // Ownership is what makes a private key date reachable by its author — without
    // it a private row would be invisible to everyone, including whoever added it.
    data.created_by = req.session.user?.id;
    data.shared_scope = data.shared_scope === 'private' ? 'private' : 'household';
    const result = await db.addSpecialEvent(data);
    res.json({ success: true, id: result.id });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.put('/api/gifts/events/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const row = await requireSpecialEventAccess(db, req.params.id, req, res);
    if (!row) return;
    const data = { ...req.body };
    if (data.date) data.date = normalizeDate(data.date);
    delete data.group_id;
    delete data.created_by;
    // Re-homing a date onto a person (or detaching it with null) is allowed,
    // but the person must be one of OURS — otherwise a key date could be hung
    // off another household's People card.
    if ('person_id' in data && data.person_id != null) {
      const pid = parseInt(data.person_id, 10);
      const person = Number.isInteger(pid)
        ? await dbGet(db, 'SELECT id FROM gift_people WHERE id = ? AND group_id = ?', [pid, row.group_id])
        : null;
      if (!person) return res.status(403).json({ error: 'That person is not in this household' });
      data.person_id = pid;
    }
    if ('shared_scope' in data) {
      // Only two values are meaningful, and only the owner may choose — the same
      // rule milestones follow, so the two features can't drift.
      const owner = row.created_by;
      if (owner != null && owner !== req.session.user?.id) {
        delete data.shared_scope;
      } else {
        data.shared_scope = data.shared_scope === 'private' ? 'private' : 'household';
        // Key dates added before this feature have no owner. Privatising one
        // without adopting it would hide it from EVERYONE, its author included,
        // with no way back — the guard would 404 for all of them.
        if (data.shared_scope === 'private' && owner == null) {
          await dbRun(db, 'UPDATE special_events SET created_by = ? WHERE id = ? AND created_by IS NULL',
            [req.session.user?.id, req.params.id]);
        }
      }
    }
    await db.updateSpecialEvent(req.params.id, data);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.delete('/api/gifts/events/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireSpecialEventAccess(db, req.params.id, req, res))) return;
    await db.deleteSpecialEvent(req.params.id);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// ============================================
// People — the household's person registry (adults auto-linked to their
// accounts, dependents added by parents), plus per-person milestones.
// Backed by the gift_people table; gift routes above share it.
// ============================================

app.get('/api/people', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const groupId = await db.getUserHouseholdId(req.session.user?.id);
    if (!groupId) return res.json([]);
    await db.ensureHouseholdUserPeople(groupId);
    res.json(await db.getPeople(groupId));
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.post('/api/people', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const groupId = await db.getUserHouseholdId(req.session.user?.id);
    if (!groupId) return res.status(403).json({ error: 'Join a household first' });
    const name = typeof req.body.name === 'string' ? req.body.name.trim() : '';
    if (!name) return res.status(400).json({ error: 'A name is required' });
    // Parents add dependents here; linked-user rows are created automatically.
    const result = await db.addPerson({ ...req.body, name, user_id: null, group_id: groupId });
    res.json({ success: true, id: result.id });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.put('/api/people/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireHouseholdRow(db, 'gift_people', req.params.id, req, res))) return;
    await db.updatePerson(req.params.id, req.body);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.delete('/api/people/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireHouseholdRow(db, 'gift_people', req.params.id, req, res))) return;
    await db.deletePerson(req.params.id);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// A person's tagged decisions — the "things we've talked about for them" list.
app.get('/api/people/:id/decisions', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireHouseholdRow(db, 'gift_people', req.params.id, req, res))) return;
    const person = await dbGet(db, 'SELECT id, group_id FROM gift_people WHERE id = ?', [req.params.id]);
    res.json(await db.getDecisionsForPerson(person.id, person.group_id));
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.get('/api/milestones', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const groupId = await db.getUserHouseholdId(req.session.user?.id);
    if (!groupId) return res.json([]);
    const personId = req.query.person_id ? Number(req.query.person_id) : null;
    res.json(await db.getMilestones(groupId, Number.isInteger(personId) ? personId : null, req.session.user?.id));
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.post('/api/milestones', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user.id;
    const groupId = await db.getUserHouseholdId(userId);
    if (!groupId) return res.status(403).json({ error: 'Join a household first' });
    const { person_id, title, milestone_date } = req.body;
    if (!title || !milestone_date) return res.status(400).json({ error: 'Title and date are required' });
    if (!(await personBelongsToCallerHousehold(db, userId, person_id))) {
      return res.status(403).json({ error: 'Cannot add a milestone for that person' });
    }
    // Optional clan celebration: the milestone row stays household-scoped and
    // the household always gets the feed post; a clan share ADDS a post in
    // that clan's feed too (clan members may not overlap the household, e.g.
    // a Jesse∩Ariel clan that Sophie isn't in — she'd miss a clan-only post).
    // `private` wins over any clan share: a milestone kept to yourself gets no
    // feed post and no push anywhere, and only you can see the row.
    let sharedScope = req.body.shared_scope === 'private' ? 'private' : 'household';
    let sharedGroupId = null;
    if (sharedScope !== 'private' && req.body.shared_group_id) {
      const gid = parseInt(req.body.shared_group_id);
      if (!Number.isInteger(gid) || !(await db.isGroupMember(gid, userId))) {
        return res.status(403).json({ error: 'Cannot share to that group' });
      }
      if (gid !== groupId) {          // picking your own household = plain household scope
        sharedScope = 'group';
        sharedGroupId = gid;
      }
    }
    const person = await dbGet(db, 'SELECT name FROM gift_people WHERE id = ?', [parseInt(person_id)]);
    const result = await db.addMilestone({
      ...req.body,
      shared_scope: sharedScope,
      shared_group_id: sharedGroupId,
      created_by: userId,
      creator_name: req.session.user.name,
      group_id: groupId,
    });
    res.json({ success: true, id: result.id });

    // Celebrate: feed post + push in the household, and in the clan if shared.
    // A private milestone is celebrated nowhere — that is the whole point of it.
    const celebrateIn = sharedScope === 'private'
      ? []
      : [groupId, ...(sharedGroupId ? [sharedGroupId] : [])];
    for (const gid of celebrateIn) {
      try {
        await db.addFeedPost({
          group_id: gid,
          author_id: userId,
          post_type: 'milestone',
          title: `${person.name}: ${title}`,
          body: req.body.description || null,
          // base64, same convention as photo posts — renders in the group feed
          photo_url: typeof req.body.photo_data === 'string' && req.body.photo_data ? req.body.photo_data : null,
          reference_type: 'milestone',
          reference_id: result.id,
        });
      } catch (e) { console.error('Milestone feed post error:', e.message); }
      jobs.pushToGroup(db, gid, userId, 'A new milestone',
        `${person.name} — ${title}. Cheer them on!`, { type: 'milestone', ref_id: result.id });
    }
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.put('/api/milestones/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const row = await requireMilestoneAccess(db, req.params.id, req, res);
    if (!row) return;
    const updates = { ...req.body };
    // Only the person who logged it decides who sees it, and only between
    // private and household — a clan share is set when the milestone is created.
    if ('shared_scope' in updates) {
      const owner = row.created_by;
      if (owner != null && owner !== req.session.user?.id) {
        delete updates.shared_scope;
      } else {
        // The edit sheet's toggle only expresses private vs not-private. Taking
        // "not private" literally as 'household' silently downgraded a
        // clan-shared milestone to household-only on an unrelated edit (a
        // rename), orphaning its shared_group_id — so preserve 'group'.
        updates.shared_scope = updates.shared_scope === 'private'
          ? 'private'
          : (row.shared_scope === 'group' ? 'group' : 'household');
        if (updates.shared_scope === 'private' && owner == null) {
          // Same trap as key dates: an unowned row made private is lost to all.
          await dbRun(db, 'UPDATE milestones SET created_by = ? WHERE id = ? AND created_by IS NULL',
            [req.session.user?.id, req.params.id]);
        }
      }
    }
    await db.updateMilestone(req.params.id, updates);
    // Going private has to retract the celebration too, or the record hides
    // while the feed post announcing it stays in everyone's feed.
    if (updates.shared_scope === 'private') {
      try { await db.deleteFeedPostsByReference('milestone', req.params.id); }
      catch (e) { console.error('Milestone feed retract error:', e.message); }
    }
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.delete('/api/milestones/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireMilestoneAccess(db, req.params.id, req, res))) return;
    await db.deleteMilestone(req.params.id);
    try { await db.deleteFeedPostsByReference('milestone', req.params.id); }
    catch (e) { console.error('Milestone feed cleanup error:', e.message); }
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// ============================================
// Groups
// ============================================

app.get('/api/groups', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    if (!userId) return res.json([]);
    const groups = await db.getGroupsByUser(userId);
    res.json(groups);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.post('/api/groups', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    const group = await db.createGroup({ ...req.body, created_by: userId });
    await db.addGroupMember(group.id, { user_id: userId, role: 'admin', added_by: userId });
    res.json({ success: true, id: group.id, invite_code: group.invite_code });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Founder (or any household member) emails the invite code to family.
// Specific path before /api/households/merge. Rate-limited; no user enumeration.
app.post('/api/household/invite', requireAuth, householdInviteLimiter, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    let emails;
    try {
      emails = householdInvite.parseEmails(req.body?.emails ?? req.body?.email);
    } catch (err) {
      return res.status(err.status || 400).json({ error: err.message });
    }
    const hid = await db.getUserHouseholdId(userId);
    if (!hid) return res.status(403).json({ error: 'Join a household first' });
    const group = await db.getGroupById(hid);
    if (!group?.invite_code) return res.status(400).json({ error: 'This household has no invite code yet' });
    if (!householdInvite.isEmailEnabled()) {
      return res.status(503).json({
        error: "Email isn't set up on this server yet. Copy the code and send it yourself.",
      });
    }
    const inviter = req.session.user?.name || 'Your family';
    const result = await householdInvite.sendHouseholdInvites({
      inviterName: inviter,
      householdName: group.name,
      inviteCode: group.invite_code,
      emails,
    });
    if (result.sent.length === 0) {
      return res.status(502).json({ error: "We couldn't send the invite just now. Try again, or copy the code.", ...result });
    }
    res.json({ success: true, ...result });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.post('/api/groups/join', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    const { invite_code } = req.body;
    if (!invite_code) return res.status(400).json({ error: 'invite_code required' });
    const group = await db.getGroupByInviteCode(invite_code);
    if (!group) return res.status(404).json({ error: 'Invalid invite code' });
    if (await db.isGroupMember(group.id, userId)) {
      return res.json({ success: true, group, already_member: true });
    }
    // Joiners are plain members. Households are co-managed by any member; clans
    // require an admin to add/remove/rename/delete, so a clan joiner can't manage.
    await db.addGroupMember(group.id, { user_id: userId, role: 'member', added_by: userId });
    res.json({ success: true, group });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Merge one household into another (e.g. each partner created their own at
// signup). Moves all of `source_id`'s data + members into the target, then
// deletes the source. Target can be given by id (caller already joined) or by
// invite_code (caller is joined as part of the merge). Caller must be a member
// of the source household.
app.post('/api/households/merge', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    const sourceId = parseInt(req.body.source_id);
    if (!sourceId) return res.status(400).json({ error: 'source_id required' });
    // Merging deletes the source household — require admin of it (not just member).
    if (!(await requireGroupManage(db, sourceId, req, res))) return;
    // Resolve target by id or invite code.
    let targetId = req.body.target_id ? parseInt(req.body.target_id) : null;
    if (!targetId && req.body.invite_code) {
      const tgt = await db.getGroupByInviteCode(req.body.invite_code);
      if (!tgt) return res.status(404).json({ error: 'Invalid invite code' });
      targetId = tgt.id;
      if (!(await db.isGroupMember(targetId, userId))) {
        await db.addGroupMember(targetId, { user_id: userId, role: 'member', added_by: userId });
      }
    }
    if (!targetId) return res.status(400).json({ error: 'target_id or invite_code required' });
    if (targetId === sourceId) return res.status(400).json({ error: 'Cannot merge a household into itself' });
    if (!(await db.isGroupMember(targetId, userId))) {
      return res.status(403).json({ error: 'Not a member of the target household' });
    }
    const result = await db.mergeHousehold(sourceId, targetId);
    res.json({ success: true, ...result });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.post('/api/groups/:id/leave', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    const members = await db.getGroupMembers(req.params.id);
    const myMembership = members.find(m => m.user_id === userId);
    if (!myMembership) return res.status(404).json({ error: 'Not a member' });
    await db.removeGroupMember(req.params.id, myMembership.id);
    // If no members left, delete the group
    const remaining = members.filter(m => m.id !== myMembership.id);
    if (remaining.length === 0) {
      await db.deleteGroup(parseInt(req.params.id));
    }
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.get('/api/groups/:id/members', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await db.isGroupMember(req.params.id, req.session.user?.id))) {
      return res.status(403).json({ error: 'Not a member of this group' });
    }
    const members = await db.getGroupMembers(req.params.id);
    res.json(members);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.post('/api/groups/:id/members', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    // Admin-only: adding an outsider to a household exposes its sensitive data.
    // New members are forced to 'member' — no self-promotion to admin.
    if (!(await requireGroupManage(db, req.params.id, req, res))) return;
    // Consent guard: an admin may only add people they actually know —
    // a contact they own, or an app user they already share a group with.
    // Without this, any enumerable user_id could be pulled into the group
    // (re-routing that user's household writes and exposing both sides' data).
    let addUserId = req.body.user_id ? Number(req.body.user_id) : null;
    let addContactId = req.body.contact_id ? Number(req.body.contact_id) : null;
    if (addContactId && addContactId < 0) {
      // Household-roster pseudo-contact (id = -(user_id)) — treat as a user add.
      addUserId = -addContactId;
      addContactId = null;
    }
    if (addContactId && !(await userOwnsContact(db, addContactId, userId))) {
      return res.status(403).json({ error: 'You can only add your own contacts' });
    }
    if (addUserId) {
      // Sharing a group is the robust consent link; the owned-contact name
      // match remains as a fallback for people not yet in any shared group.
      const known = (await usersShareGroup(db, userId, addUserId))
        || !!(await dbGet(db, `SELECT 1 FROM contacts c
              JOIN users u ON LOWER(u.name) = LOWER(c.name)
              WHERE c.added_by = ? AND u.id = ? LIMIT 1`, [userId, addUserId]));
      if (!known) return res.status(403).json({ error: 'Add this person to your contacts first, or have them join with an invite code' });
    }
    const result = await db.addGroupMember(req.params.id, {
      user_id: addUserId, contact_id: addContactId, role: 'member', added_by: userId,
    });
    res.json({ success: true, id: result.id });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.delete('/api/groups/:groupId/members/:memberId', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    if (!(await db.isGroupMember(req.params.groupId, userId))) {
      return res.status(403).json({ error: 'Not a member of this group' });
    }
    // Anyone may remove themselves (leave); only admins may remove others.
    const target = await dbGet(db, 'SELECT user_id FROM group_members WHERE id = ? AND group_id = ?',
      [req.params.memberId, req.params.groupId]);
    if (!target) return res.status(404).json({ error: 'Member not found' });
    const isSelf = target.user_id != null && target.user_id === userId;
    if (!isSelf && !(await requireGroupManage(db, req.params.groupId, req, res))) return;
    await db.removeGroupMember(req.params.groupId, req.params.memberId);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.put('/api/groups/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    // Renaming/redescribing a group is an admin action.
    if (!(await requireGroupManage(db, req.params.id, req, res))) return;
    const { name, description } = req.body;
    const fields = [];
    const params = [];
    if (name) { fields.push('name = ?'); params.push(name); }
    if (description !== undefined) { fields.push('description = ?'); params.push(description); }
    if (fields.length === 0) return res.status(400).json({ error: 'Nothing to update' });
    params.push(req.params.id);
    await new Promise((resolve, reject) => {
      db.db.run(`UPDATE groups SET ${fields.join(', ')} WHERE id = ?`, params, (err) => err ? reject(err) : resolve());
    });
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.delete('/api/groups/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    // Deleting a whole group/household is destructive — admins only.
    if (!(await requireGroupManage(db, req.params.id, req, res))) return;
    await db.deleteGroup(req.params.id);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// ============================================
// Contacts
// ============================================

app.get('/api/contacts', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    if (!userId) return res.json([]);
    const contacts = await db.getContactsByUser(userId);
    res.json(contacts);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.post('/api/contacts', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    const result = await db.addContact({ ...req.body, added_by: userId });
    res.json({ success: true, id: result.id });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Contacts are owner-scoped (added_by); only the creator may edit/delete.
async function requireContactOwner(db, id, req, res) {
  const row = await dbGet(db, 'SELECT added_by FROM contacts WHERE id = ?', [id]);
  if (!row) { res.status(404).json({ error: 'Not found' }); return false; }
  if (row.added_by !== req.session.user?.id) { res.status(403).json({ error: 'Forbidden' }); return false; }
  return true;
}

app.put('/api/contacts/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireContactOwner(db, req.params.id, req, res))) return;
    await db.updateContact(req.params.id, req.body);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.delete('/api/contacts/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireContactOwner(db, req.params.id, req, res))) return;
    await db.deleteContact(req.params.id);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// ============================================
// Feed
// ============================================

app.get('/api/groups/:id/feed', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await db.isGroupMember(req.params.id, req.session.user?.id))) {
      return res.status(403).json({ error: 'Not a member of this group' });
    }
    const posts = await db.getFeedPosts(req.params.id, {
      limit: clampLimit(req.query.limit, 50),
      before_id: req.query.before_id ? parseInt(req.query.before_id) : undefined,
      after_id: req.query.after_id ? parseInt(req.query.after_id) : undefined,
    });
    res.json(posts);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.post('/api/groups/:id/feed', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    const senderName = req.session.user?.name;
    const groupId = parseInt(req.params.id);
    if (!(await db.isGroupMember(groupId, userId))) {
      return res.status(403).json({ error: 'Not a member of this group' });
    }
    // reference_type/reference_id are set by the SERVER when it announces a
    // milestone or a shared routine — a user post has nothing to reference, and
    // accepting them would let a caller forge a row that points at someone
    // else's record.
    const { reference_type, reference_id, ...postBody } = req.body || {};
    const result = await db.addFeedPost({ ...postBody, group_id: groupId, author_id: userId });
    res.json({ success: true, id: result.id });
    // Push to group members (fire-and-forget). Include the group name so the
    // tap opens the exact group thread (the client router needs `name`).
    const preview = req.body.title || req.body.body || 'New post';
    const grp = await dbGet(db, 'SELECT name FROM groups WHERE id = ?', [groupId]);
    jobs.pushToGroup(db, groupId, userId, `New from ${senderName}`, preview,
      { type: 'group_message', ref_id: groupId, name: grp?.name || 'Group' });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Lazy photo fetch for the Home activity feed: the list carries only a
// has_photo flag (inlining base64 photos would balloon the hottest payload
// in the app); clients fetch the actual image per post on demand.
app.get('/api/feed/:id/photo', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireFeedPostMember(db, req.params.id, req, res))) return;
    const row = await dbGet(db, 'SELECT photo_url FROM feed_posts WHERE id = ?', [req.params.id]);
    if (!row?.photo_url) return res.status(404).json({ error: 'No image' });
    if (!sendStoredImage(req, res, row.photo_url, 'photo_url')) return res.status(404).json({ error: 'No image' });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.delete('/api/feed/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    // Only the post's author may delete it.
    const post = await dbGet(db, 'SELECT author_id FROM feed_posts WHERE id = ?', [req.params.id]);
    if (!post) return res.status(404).json({ error: 'Not found' });
    if (post.author_id !== req.session.user?.id) {
      return res.status(403).json({ error: 'Only the author can delete this post' });
    }
    await db.deleteFeedPost(req.params.id);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.post('/api/feed/:id/reactions', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    if (!(await requireFeedPostMember(db, req.params.id, req, res))) return;
    await db.addFeedReaction(req.params.id, userId, req.body.reaction_type);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.delete('/api/feed/:id/reactions', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    if (!(await requireFeedPostMember(db, req.params.id, req, res))) return;
    await db.removeFeedReaction(req.params.id, userId);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.get('/api/feed/:id/reactions', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireFeedPostMember(db, req.params.id, req, res))) return;
    const reactions = await db.getFeedReactions(req.params.id);
    res.json(reactions);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.get('/api/feed/:id/comments', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireFeedPostMember(db, req.params.id, req, res))) return;
    const comments = await db.getFeedComments(req.params.id);
    res.json(comments);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.post('/api/feed/:id/comments', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    if (!(await requireFeedPostMember(db, req.params.id, req, res))) return;
    const result = await db.addFeedComment(req.params.id, userId, req.body.text);
    res.json({ success: true, id: result.id });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Budget Projects
app.get('/api/projects', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const groupId = await db.getUserHouseholdId(req.session.user?.id);
    if (!groupId) return res.json([]);
    const projects = await db.getProjects(groupId);
    res.json(projects);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.post('/api/projects', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const groupId = await db.getUserHouseholdId(req.session.user?.id);
    if (!groupId) return res.status(403).json({ error: 'Join a household first' });
    const result = await db.addProject({ ...req.body, budget: parseMoney(req.body.budget), group_id: groupId });
    res.json({ success: true, id: result.id });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.delete('/api/projects/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireHouseholdRow(db, 'budget_projects', req.params.id, req, res))) return;
    await db.deleteProject(req.params.id);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.get('/api/projects/:id/expenses', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireHouseholdRow(db, 'budget_projects', req.params.id, req, res))) return;
    const groupId = await db.getUserHouseholdId(req.session.user?.id);
    const expenses = await db.getProjectExpenses(req.params.id, groupId);
    res.json(expenses);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.post('/api/projects/:id/expenses', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireHouseholdRow(db, 'budget_projects', req.params.id, req, res))) return;
    const groupId = await db.getUserHouseholdId(req.session.user?.id);
    const result = await db.addProjectExpense(req.params.id, { ...req.body, amount: parseMoney(req.body.amount) }, groupId);
    res.json({ success: true, id: result.id });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.delete('/api/projects/:projectId/expenses/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireHouseholdRow(db, 'budget_projects', req.params.projectId, req, res))) return;
    await db.deleteProjectExpense(req.params.id, req.params.projectId);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// ============================================
// Routines (period / baby-sleep / sleep-training / custom trackers)
// Route order: the static template + guidance paths are registered before the
// `/api/routines/:id` sibling so they don't get shadowed.
// ============================================
const sleepTraining = require('./services/sleepTraining');
const sleepStats = require('./services/sleepStats');
const cycleTracking = require('./services/cycleTracking');
const routineAchievements = require('./services/routineAchievements');
const chores = require('./services/chores');

// The guided sleep-training program (age-banded phases). Static, read-only —
// still behind auth so it isn't a public scrape target.
app.get('/api/routines/templates/sleep-training', requireAuth, (req, res) => {
  res.json(sleepTraining.template());
});

// The chores program: age-banded chore ladder, reward guidance, and sources.
app.get('/api/routines/templates/chores', requireAuth, (req, res) => {
  res.json(chores.template());
});

// Authorization guard for routine rows. Routines are private to their creator
// unless shared, so household membership alone is NOT enough: a private routine
// is 403 to everyone but its author. `{ owner: true }` additionally demands
// authorship, for the operations only the creator may perform (share/unshare,
// delete). Returns the row on success, null after sending 404/403.
async function requireRoutineAccess(db, id, req, res, { owner = false } = {}) {
  const userId = req.session.user?.id;
  const row = await dbGet(db, 'SELECT id, group_id, created_by, shared_scope FROM routines WHERE id = ?', [id]);
  if (!row) { res.status(404).json({ error: 'Not found' }); return null; }
  if (row.group_id == null || !(await db.isHouseholdMember(row.group_id, userId))) {
    res.status(403).json({ error: 'Forbidden' }); return null;
  }
  const isOwner = row.created_by != null && row.created_by === userId;
  if (isOwner) return row;
  if (owner) { res.status(403).json({ error: 'Only the person who created this routine can change that' }); return null; }
  // Same 403 a non-member gets: never reveal that a private routine exists.
  if (row.shared_scope !== 'household') { res.status(403).json({ error: 'Forbidden' }); return null; }
  return row;
}

// Milestones follow the same rule as key dates: household-visible unless marked
// private, and a private one is reachable only by whoever logged it.
async function requireMilestoneAccess(db, id, req, res) {
  const userId = req.session.user?.id;
  const row = await dbGet(db, 'SELECT group_id, created_by, shared_scope FROM milestones WHERE id = ?', [id]);
  if (!row) { res.status(404).json({ error: 'Not found' }); return null; }
  if (row.group_id == null || !(await db.isHouseholdMember(row.group_id, userId))) {
    res.status(403).json({ error: 'Forbidden' }); return null;
  }
  if (row.shared_scope === 'private' && row.created_by !== userId) {
    res.status(404).json({ error: 'Not found' }); return null;
  }
  return row;
}

// Key dates are household-visible unless marked private, in which case only the
// person who added them can see or touch them — otherwise a housemate could flip
// a private anniversary back to shared by id and read it.
async function requireSpecialEventAccess(db, id, req, res) {
  const userId = req.session.user?.id;
  const row = await dbGet(db, 'SELECT group_id, created_by, shared_scope FROM special_events WHERE id = ?', [id]);
  if (!row) { res.status(404).json({ error: 'Not found' }); return null; }
  if (row.group_id == null || !(await db.isHouseholdMember(row.group_id, userId))) {
    res.status(403).json({ error: 'Forbidden' }); return null;
  }
  if (row.shared_scope === 'private' && row.created_by !== userId) {
    res.status(404).json({ error: 'Not found' }); return null;
  }
  return row;
}

app.get('/api/routines', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    const groupId = await db.getUserHouseholdId(userId);
    if (!groupId) return res.json([]);
    res.json(await db.getRoutines(groupId, userId));
  } catch (err) { sendServerError(res, err); }
  finally { db.close(); }
});

app.post('/api/routines', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const groupId = await db.getUserHouseholdId(req.session.user?.id);
    if (!groupId) return res.status(403).json({ error: 'Join a household first' });
    const name = String(req.body.name || '').trim();
    if (!name) return res.status(400).json({ error: 'name is required' });
    const type = ['period', 'baby_sleep', 'sleep_training', 'activity', 'chores', 'custom'].includes(req.body.routine_type)
      ? req.body.routine_type : 'custom';
    const result = await db.createRoutine({
      group_id: groupId,
      created_by: req.session.user?.id,
      name,
      routine_type: type,
      subject_name: req.body.subject_name,
      subject_birthdate: req.body.subject_birthdate ? normalizeDate(req.body.subject_birthdate) : null,
      config: req.body.config,
      // Private unless the client explicitly opts in at creation time.
      shared_scope: req.body.shared_scope === 'household' ? 'household' : 'private',
      color: req.body.color,
      icon: req.body.icon,
      start_date: req.body.start_date ? normalizeDate(req.body.start_date) : todayLocal(),
    });
    res.json({ success: true, id: result.id });
  } catch (err) { sendServerError(res, err); }
  finally { db.close(); }
});

// The child's birthdate, from the routine if it carries one, otherwise from the
// person of that name in the same household — their People record, or failing
// that a birthday key date tied to them. Age drives every piece of sleep
// guidance, so a birthday already entered once shouldn't have to be typed again.
//
// Name matching is scoped to the household and refuses to guess: two people
// whose names both match returns nothing rather than picking one.
async function resolveSubjectBirthdate(db, routine, callerId) {
  if (routine?.subject_birthdate) return routine.subject_birthdate;
  const name = String(routine?.subject_name || '').trim();
  if (!name || routine.group_id == null) return null;

  const people = await new Promise((resolve) => db.db.all(
    'SELECT id, name, birthday FROM gift_people WHERE group_id = ?', [routine.group_id],
    (err, rows) => resolve(err ? [] : (rows || []))));

  const wanted = name.toLowerCase();
  const firstOf = (n) => String(n || '').trim().toLowerCase().split(/\s+/)[0];
  let matches = people.filter(p => String(p.name || '').trim().toLowerCase() === wanted);
  if (!matches.length) matches = people.filter(p => firstOf(p.name) === firstOf(name));
  if (matches.length !== 1) return null;   // none, or ambiguous — don't guess
  const person = matches[0];
  if (person.birthday) return String(person.birthday).slice(0, 10);

  // Fall back to a birthday key date filed against that person.
  const row = await dbGet(db,
    `SELECT date FROM special_events
     WHERE person_id = ? AND group_id = ? AND event_type = 'birthday'
       -- A private key date is its owner's alone; resolving an age through one
       -- would hand its date to the rest of the household.
       AND (COALESCE(shared_scope, 'household') != 'private' OR created_by = ?)
     ORDER BY date LIMIT 1`, [person.id, routine.group_id, callerId]);
  return row?.date ? String(row.date).slice(0, 10) : null;
}

// Today's chores for Home: each chores routine the caller can see, with the
// slots still open today and this week's earnings — so ticking off "fed the
// dog" is one tap from the front page. Shared with GET /api/home.
async function choresTodayForUser(db, userId) {
  const groupId = await db.getUserHouseholdId(userId);
  if (!groupId) return [];
  const routines = (await db.getRoutines(groupId, userId))
    .filter(r => r.active !== 0 && r.routine_type === 'chores')
    .slice(0, 4);
  const entriesBy = await db.getRoutineEntriesForIds(routines.map(r => r.id), { limitPer: 1000 });
  const out = [];
  for (const routine of routines) {
    const entries = entriesBy.get(routine.id) || [];
    const birthdate = await resolveSubjectBirthdate(db, routine, userId);
    const summary = chores.compute(entries, routine.config, { today: todayLocal(), birthdate });
    const todayCol = summary.chores.map(c => {
      const d = c.days.find(x => x.today);
      return { id: c.id, title: c.title, icon: c.icon, applies: !!d?.applies, slots: d ? d.slots : [] };
    }).filter(c => c.applies);
    out.push({
      routine_id: routine.id,
      name: routine.name,
      subject_name: routine.subject_name,
      color: routine.color,
      today: summary.today,
      chores: todayCol,
      open_slots: todayCol.reduce((n, c) => n + c.slots.filter(s => !s.done).length, 0),
      total_slots: todayCol.reduce((n, c) => n + c.slots.length, 0),
      streak_days: summary.streak_days,
      lifetime_done: summary.lifetime_done,
      week_total: summary.earnings.total,
      currency: summary.earnings.currency,
    });
  }
  return out;
}

// MUST stay above `/api/routines/:id`.
app.get('/api/routines/chores-today', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    res.json(await choresTodayForUser(db, req.session.user?.id));
  } catch (err) { sendServerError(res, err); }
  finally { db.close(); }
});

// The live sleep picture for Home: for each sleep routine the caller can see,
// whether they are asleep or awake right now, how long it has been, and when
// the next sleep is likely due. Shared with GET /api/home.
async function sleepNowForUser(db, userId) {
  const groupId = await db.getUserHouseholdId(userId);
  if (!groupId) return [];
  const routines = (await db.getRoutines(groupId, userId))
    .filter(r => r.active !== 0 && ['baby_sleep', 'sleep_training'].includes(r.routine_type))
    // Home has room for a couple of these; more than that belongs in Routines.
    .slice(0, 4);

  const ids = routines.map(r => r.id);
  const [entriesBy, openBy] = await Promise.all([
    db.getRoutineEntriesForIds(ids, { limitPer: 120 }),
    db.getOpenSleepEntriesForIds(ids),
  ]);
  const out = [];
  for (const routine of routines) {
    const entries = entriesBy.get(routine.id) || [];
    const birthdate = await resolveSubjectBirthdate(db, routine, userId);

    // A sleep in progress wins: the useful line then is "asleep 40m", and the
    // next-sleep prediction is meaningless until they wake.
    const open = openBy.get(routine.id) || null;
    let openValue = null;
    if (open) { try { openValue = JSON.parse(open.value || 'null'); } catch { openValue = null; } }
    const asleepSince = openValue?.sleep_start || null;

    const nextSleep = asleepSince ? null : sleepStats.nextSleepWindow(entries, { birthdate });
    const stats = sleepStats.compute(entries, { birthdate, today: todayLocal() });

    out.push({
      routine_id: routine.id,
      name: routine.name,
      subject_name: routine.subject_name,
      routine_type: routine.routine_type,
      color: routine.color,
      state: asleepSince ? 'asleep' : 'awake',
      // Which kind of sleep is running, so the bar can say "napping" rather
      // than the wrong one of the two at 8pm.
      asleep_kind: asleepSince ? open.entry_type : null,
      asleep_since: asleepSince,
      // Null when there is no finished sleep to measure from — the client must
      // then say nothing rather than count from an invented moment.
      awake_since: nextSleep ? nextSleep.last_wake_at : null,
      last_sleep_type: nextSleep ? nextSleep.last_sleep_type : null,
      next_sleep: nextSleep,
      bedtime_prep: sleepStats.bedtimePrep(stats),
      last_night_minutes: stats.totals.last_night_minutes,
      // Only surfaced when it is a real observation rather than a zero from
      // an unlogged night.
      avg_wakings: stats.totals.avg_wakings,
    });
  }
  return out;
}

// MUST stay above `/api/routines/:id` — "sleep-now" would otherwise be read as
// a routine id.
app.get('/api/routines/sleep-now', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    res.json(await sleepNowForUser(db, req.session.user?.id));
  } catch (err) { sendServerError(res, err); }
  finally { db.close(); }
});

// Cold-launch bootstrap for Home: one round trip instead of nine GETs.
// Same household / owner scoping as the per-resource routes it replaces.
// No base64. Register this exact path BEFORE any `/api/home/:param` sibling.
app.get('/api/home', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    const today = todayLocal();
    const weekEnd = fromLocalDate(7);
    const monthEnd = fromLocalDate(30);
    const householdId = await db.getUserHouseholdId(userId);
    const feedLimit = clampLimit(req.query.limit, 20, 50);

    const [
      summary,
      groceries,
      tasks,
      monthAppointments,
      feed,
      trips,
      sleep,
      chores,
      presence,
      groups,
    ] = await Promise.all([
      db.getDailySummary(userId),
      db.getGroceries('needed', userId),
      db.getTasks({ status: 'active' }, userId),
      appointmentsInRange(db, userId, { dateFrom: today, dateTo: monthEnd }),
      db.getActivityFeed(feedLimit, userId),
      householdId ? db.getTrips({ status: 'active' }, householdId) : Promise.resolve([]),
      sleepNowForUser(db, userId),
      choresTodayForUser(db, userId),
      db.getHouseholdPresence(userId),
      db.getGroupsByUser(userId),
    ]);

    const appointmentsToday = monthAppointments.filter(a => a.appointment_date === today);
    const weekEventCount = monthAppointments.filter(a => a.appointment_date >= today && a.appointment_date <= weekEnd).length;
    const nextAppointment = monthAppointments.find(a => a.appointment_date > today) || null;

    sendCachedJson(req, res, userId, {
      summary,
      groceries,
      tasks,
      appointments_today: appointmentsToday,
      next_appointment: nextAppointment,
      week_event_count: weekEventCount,
      month_event_count: monthAppointments.length,
      feed,
      trips,
      sleep,
      chores,
      presence,
      groups,
    });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.get('/api/routines/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireRoutineAccess(db, req.params.id, req, res))) return;
    const routine = await db.getRoutineById(req.params.id);
    const entries = await db.getRoutineEntries(req.params.id, {});
    // Attach type-specific derived data the client renders.
    let guidance = null, cycle = null, achievements = null, nextSleep = null, bedtimePrep = null, choreSummary = null;
    // Only the sleep types reason from an age, so only they pay for the lookup —
    // and a cycle routine whose subject is "Me" can't accidentally resolve some
    // household member's birthday into its response.
    const needsAge = ['baby_sleep', 'sleep_training', 'chores'].includes(routine.routine_type);
    const birthdate = needsAge
      ? await resolveSubjectBirthdate(db, routine, req.session.user?.id)
      : null;
    if (routine.routine_type === 'chores') {
      choreSummary = chores.compute(entries, routine.config, { today: todayLocal(), birthdate });
    } else if (needsAge) {
      // When the next nap is likely due, so the client can nudge before they're
      // overtired rather than after.
      nextSleep = sleepStats.nextSleepWindow(entries, { birthdate });
      bedtimePrep = sleepStats.bedtimePrep(
        sleepStats.compute(entries, { birthdate, today: todayLocal() }));
    }
    if (routine.routine_type === 'sleep_training' && birthdate) {
      guidance = sleepTraining.guidanceForBirthdate(birthdate);
    } else if (routine.routine_type === 'period') {
      cycle = cycleTracking.predict(entries, routine.config);
    } else if (routine.routine_type === 'activity') {
      achievements = routineAchievements.compute(entries, {});
    }
    res.json({
      ...routine, entries, guidance, cycle, achievements,
      next_sleep: nextSleep, bedtime_prep: bedtimePrep, chores: choreSummary,
      // What the age guidance was actually computed from, so the client can say
      // "using Jude's birthday from People" rather than looking psychic.
      resolved_birthdate: birthdate,
      birthdate_source: routine.subject_birthdate ? 'routine' : (birthdate ? 'people' : null),
    });
  } catch (err) { sendServerError(res, err); }
  finally { db.close(); }
});

app.put('/api/routines/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireRoutineAccess(db, req.params.id, req, res))) return;
    const updates = { ...req.body };
    if (updates.subject_birthdate) updates.subject_birthdate = normalizeDate(updates.subject_birthdate);
    if (updates.start_date) updates.start_date = normalizeDate(updates.start_date);
    await db.updateRoutine(req.params.id, updates);
    res.json({ success: true });
  } catch (err) { sendServerError(res, err); }
  finally { db.close(); }
});

// Deleting a routine takes its whole history with it — creator only, even when
// the routine is shared and the rest of the household can log to it.
app.delete('/api/routines/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireRoutineAccess(db, req.params.id, req, res, { owner: true }))) return;
    await db.deleteRoutine(req.params.id);
    // Otherwise the "shared a routine" post outlives the routine and its deep
    // link opens a detail page that can never load.
    try { await db.deleteFeedPostsByReference('routine', req.params.id); }
    catch (e) { console.error('Routine feed cleanup error:', e.message); }
    res.json({ success: true });
  } catch (err) { sendServerError(res, err); }
  finally { db.close(); }
});

// The share toggle. Creator-only (enforced again in SQL by setRoutineScope), and
// deliberately its own route so `shared_scope` can never ride in on a PUT body.
app.put('/api/routines/:id/share', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const row = await requireRoutineAccess(db, req.params.id, req, res, { owner: true });
    if (!row) return;
    const scope = req.body.shared_scope === 'household' || req.body.shared === true
      ? 'household' : 'private';
    const result = await db.setRoutineScope(req.params.id, req.session.user?.id, scope);
    res.json({ success: true, shared_scope: result.scope });

    // Pulling a routine back to private retracts the post that announced it.
    if (scope === 'private' && row.shared_scope === 'household') {
      try { await db.deleteFeedPostsByReference('routine', req.params.id); }
      catch (e) { console.error('Routine feed retract error:', e.message); }
    }

    // Announce it once, on the transition into sharing — this is the moment the
    // rest of the household can suddenly see and log to it. Un-sharing stays
    // quiet: nobody needs a feed post saying something was taken away. Fired
    // after the response so a feed failure can't fail the toggle itself.
    if (scope === 'household' && row.shared_scope !== 'household' && result.changed) {
      const routine = await db.getRoutineById(req.params.id);
      try {
        await db.addFeedPost({
          group_id: row.group_id,
          author_id: req.session.user?.id,
          post_type: 'routine',
          title: `Shared a routine: ${routine?.name || 'Routine'}`,
          body: routine?.subject_name ? `For ${routine.subject_name}` : null,
          reference_type: 'routine',
          reference_id: Number(req.params.id),
        });
      } catch (e) { console.error('Routine share feed post error:', e.message); }
      jobs.pushToGroup(db, row.group_id, req.session.user?.id, 'A routine was shared',
        `${routine?.name || 'A routine'} is now shared with your household`);
    }
  } catch (err) { sendServerError(res, err); }
  finally { db.close(); }
});

// ---- Chores: idempotent slot toggles, bonuses, and payouts ----------------
// Each is a thin write over routine_entries so history, sharing, and deletion
// all keep working the way they do for every other routine kind.

async function requireChoresRoutine(db, req, res) {
  const row = await requireRoutineAccess(db, req.params.id, req, res);
  if (!row) return null;
  const routine = await db.getRoutineById(req.params.id);
  if (routine.routine_type !== 'chores') { res.status(400).json({ error: 'Not a chores routine' }); return null; }
  return routine;
}

async function choreDetail(db, routine, req) {
  const entries = await db.getRoutineEntries(routine.id, { limit: 1000 });
  const birthdate = await resolveSubjectBirthdate(db, routine, req.session.user?.id);
  return chores.compute(entries, routine.config, { today: todayLocal(), birthdate });
}

// Toggle one chore slot on one day. Done -> not done deletes the entry; the
// response is the recomputed week so the client never has to guess.
app.post('/api/routines/:id/chores/toggle', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const routine = await requireChoresRoutine(db, req, res);
    if (!routine) return;
    const cfg = chores.parseConfig(routine.config);
    const chore = cfg.chores.find(c => c.id === String(req.body.chore_id || ''));
    if (!chore) return res.status(400).json({ error: 'Unknown chore' });
    const slot = chore.slots.includes(req.body.slot) ? req.body.slot : chore.slots[0];
    const date = req.body.date ? normalizeDate(req.body.date) : todayLocal();
    if (date > todayLocal()) return res.status(400).json({ error: "Can't mark a chore done in the future" });
    const existing = (await db.getRoutineEntries(routine.id, { from: date, to: date, limit: 200 }))
      .find(e => e.entry_type === 'chore_done' && (() => { try { const v = JSON.parse(e.value || '{}'); return v.chore_id === chore.id && (v.slot || 'anytime') === slot; } catch { return false; } })());
    const wantDone = req.body.done == null ? !existing : !!req.body.done;
    if (wantDone && !existing) {
      await db.addRoutineEntry(routine.id, {
        entry_date: date, entry_type: 'chore_done', value: { chore_id: chore.id, slot, title: chore.title },
        created_by: req.session.user?.id,
      });
    } else if (!wantDone && existing) {
      await db.deleteRoutineEntry(existing.id, routine.id);
    }
    res.json({ success: true, done: wantDone, chores: await choreDetail(db, routine, req) });
  } catch (err) { sendServerError(res, err); }
  finally { db.close(); }
});

// Mark a behaviour bonus (e.g. "good bedtime") earned or not on a day.
app.post('/api/routines/:id/chores/bonus', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const routine = await requireChoresRoutine(db, req, res);
    if (!routine) return;
    const cfg = chores.parseConfig(routine.config);
    const bonus = cfg.bonuses.find(b => b.id === String(req.body.bonus_id || ''));
    if (!bonus) return res.status(400).json({ error: 'Unknown bonus' });
    const date = req.body.date ? normalizeDate(req.body.date) : todayLocal();
    const existing = (await db.getRoutineEntries(routine.id, { from: date, to: date, limit: 200 }))
      .find(e => e.entry_type === 'bonus_earned' && (() => { try { return JSON.parse(e.value || '{}').bonus_id === bonus.id; } catch { return false; } })());
    const wantEarned = req.body.earned == null ? !existing : !!req.body.earned;
    if (wantEarned && !existing) {
      await db.addRoutineEntry(routine.id, {
        entry_date: date, entry_type: 'bonus_earned', value: { bonus_id: bonus.id, title: bonus.title, amount: bonus.amount },
        created_by: req.session.user?.id,
      });
    } else if (!wantEarned && existing) {
      await db.deleteRoutineEntry(existing.id, routine.id);
    }
    res.json({ success: true, earned: wantEarned, chores: await choreDetail(db, routine, req) });
  } catch (err) { sendServerError(res, err); }
  finally { db.close(); }
});

// Record that a week's allowance was paid. Amount defaults to what the week
// earned; week_start defaults to the current week.
app.post('/api/routines/:id/chores/payout', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const routine = await requireChoresRoutine(db, req, res);
    if (!routine) return;
    const summary = await choreDetail(db, routine, req);
    const weekStart = req.body.week_start ? chores.weekStartOf(normalizeDate(req.body.week_start), summary.week_start_day) : summary.week_start;
    const owedWeek = summary.ledger.unpaid_weeks.find(w => w.week_start === weekStart);
    const defaultAmount = weekStart === summary.week_start ? summary.earnings.total : (owedWeek ? owedWeek.amount : 0);
    const amount = req.body.amount != null ? parseMoney(req.body.amount) : defaultAmount;
    if (amount == null || amount < 0) return res.status(400).json({ error: 'Invalid amount' });
    const r = await db.addRoutineEntry(routine.id, {
      entry_date: todayLocal(), entry_type: 'payout', value: { amount, week_start: weekStart },
      notes: req.body.notes || null, created_by: req.session.user?.id,
    });
    res.json({ success: true, id: r.id, chores: await choreDetail(db, routine, req) });
  } catch (err) { sendServerError(res, err); }
  finally { db.close(); }
});

app.get('/api/routines/:id/entries', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireRoutineAccess(db, req.params.id, req, res))) return;
    const entries = await db.getRoutineEntries(req.params.id, {
      from: req.query.from, to: req.query.to, limit: clampLimit(req.query.limit, 200, 1000),
    });
    res.json(entries);
  } catch (err) { sendServerError(res, err); }
  finally { db.close(); }
});

app.post('/api/routines/:id/entries', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireRoutineAccess(db, req.params.id, req, res))) return;
    const entry_date = req.body.entry_date ? normalizeDate(req.body.entry_date) : todayLocal();
    const result = await db.addRoutineEntry(req.params.id, {
      entry_date,
      entry_time: req.body.entry_time,
      entry_type: req.body.entry_type,
      value: req.body.value,
      notes: req.body.notes,
      created_by: req.session.user?.id,
    });
    res.json({ success: true, id: result.id });
  } catch (err) { sendServerError(res, err); }
  finally { db.close(); }
});

// Correct an entry after the fact — most often a sleep whose end was stamped
// when you got round to tapping "Awake" rather than when they actually woke.
app.put('/api/routines/:id/entries/:entryId', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireRoutineAccess(db, req.params.id, req, res))) return;
    const existing = await db.getRoutineEntryById(req.params.entryId);
    if (!existing || existing.routine_id !== parseInt(req.params.id)) {
      return res.status(404).json({ error: 'Not found' });
    }
    const updates = {};
    if (req.body.entry_date) updates.entry_date = normalizeDate(req.body.entry_date);
    if (req.body.notes !== undefined) updates.notes = req.body.notes || null;

    // A sleep is corrected by its times; the span is recomputed server-side so
    // the stored duration can never disagree with the start and end shown.
    if (req.body.start_time && req.body.end_time) {
      const day = updates.entry_date || existing.entry_date;
      const span = sleepStats.span(day, req.body.start_time, req.body.end_time);
      if (!span) return res.status(400).json({ error: 'start_time and end_time must be HH:MM' });
      const value = { sleep_start: span.start, sleep_end: span.end, duration_minutes: span.minutes };
      if (req.body.wake_count != null) value.wake_count = Math.max(0, parseInt(req.body.wake_count) || 0);
      updates.value = value;
      updates.entry_time = span.startTime;
    } else if (req.body.entry_time) {
      updates.entry_time = req.body.entry_time;
    }

    const result = await db.updateRoutineEntry(req.params.entryId, req.params.id, updates);
    res.json({ success: true, changed: result.changed });
  } catch (err) { sendServerError(res, err); }
  finally { db.close(); }
});

app.delete('/api/routines/:id/entries/:entryId', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireRoutineAccess(db, req.params.id, req, res))) return;
    await db.deleteRoutineEntry(req.params.entryId, req.params.id);
    res.json({ success: true });
  } catch (err) { sendServerError(res, err); }
  finally { db.close(); }
});

// A sleep happening right now: POST starts it, PUT ends it. Stored as an
// ordinary entry whose value is marked in_progress until it closes, so nothing
// downstream needs a second table — and stats skip it until it has a duration.
app.post('/api/routines/:id/sleep/start', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireRoutineAccess(db, req.params.id, req, res))) return;
    const open = await db.getOpenSleepEntry(req.params.id);
    if (open) return res.status(409).json({ error: 'A sleep is already running', entry_id: open.id });
    const kind = req.body.kind === 'night_sleep' ? 'night_sleep' : 'nap';
    const date = req.body.date ? normalizeDate(req.body.date) : todayLocal();
    const time = req.body.time || nowTimeLocal();
    const span = sleepStats.span(date, time, time);
    if (!span) return res.status(400).json({ error: 'time must be HH:MM' });
    const result = await db.addRoutineEntry(req.params.id, {
      entry_date: date, entry_time: span.startTime, entry_type: kind,
      value: { sleep_start: span.start, in_progress: true },
      notes: req.body.notes, created_by: req.session.user?.id,
    });
    res.json({ success: true, id: result.id, started_at: span.start });
  } catch (err) { sendServerError(res, err); }
  finally { db.close(); }
});

// Correct the start time of the sleep that's currently running. Tapping "down
// for the night" stamps now, which is only right if you tapped it at the time —
// this is for the far more common case of remembering twenty minutes later.
app.put('/api/routines/:id/sleep/start', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireRoutineAccess(db, req.params.id, req, res))) return;
    const open = await db.getOpenSleepEntry(req.params.id);
    if (!open) return res.status(404).json({ error: 'No sleep is running' });
    let stored = {};
    try { stored = JSON.parse(open.value || '{}'); } catch {}
    // Keep the day the sleep was filed under and move only the clock time, so a
    // correction can't silently relocate the entry to another date.
    const day = String(stored.sleep_start || '').slice(0, 10) || open.entry_date;
    const span = sleepStats.span(day, req.body.time, req.body.time);
    if (!span) return res.status(400).json({ error: 'time must be HH:MM' });
    await db.setSleepEntryValue(open.id, req.params.id,
      { sleep_start: span.start, in_progress: true }, req.body.notes || null);
    await dbRun(db, 'UPDATE routine_entries SET entry_time = ? WHERE id = ? AND routine_id = ?',
      [span.startTime, open.id, req.params.id]);
    res.json({ success: true, id: open.id, started_at: span.start });
  } catch (err) { sendServerError(res, err); }
  finally { db.close(); }
});

app.put('/api/routines/:id/sleep/end', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireRoutineAccess(db, req.params.id, req, res))) return;
    const open = await db.getOpenSleepEntry(req.params.id);
    if (!open) return res.status(404).json({ error: 'No sleep is running' });
    let stored = {};
    try { stored = JSON.parse(open.value || '{}'); } catch {}
    const span = sleepStats.span(String(stored.sleep_start || '').slice(0, 10),
                                 String(stored.sleep_start || '').slice(11, 16),
                                 req.body.time || nowTimeLocal());
    if (!span) return res.status(400).json({ error: 'time must be HH:MM' });
    const value = { sleep_start: span.start, sleep_end: span.end, duration_minutes: span.minutes };
    if (req.body.wake_count != null) value.wake_count = Math.max(0, parseInt(req.body.wake_count) || 0);
    await db.setSleepEntryValue(open.id, req.params.id, value, req.body.notes || null);
    res.json({ success: true, id: open.id, duration_minutes: span.minutes });
  } catch (err) { sendServerError(res, err); }
  finally { db.close(); }
});

// Sleep statistics + age-appropriate guidance and tips for this routine.
app.get('/api/routines/:id/sleep-stats', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireRoutineAccess(db, req.params.id, req, res))) return;
    const routine = await db.getRoutineById(req.params.id);
    const entries = await db.getRoutineEntries(req.params.id, { limit: 400 });
    const birthdate = await resolveSubjectBirthdate(db, routine, req.session.user?.id);
    const today = todayLocal();
    const stats = sleepStats.compute(entries, {
      // Same resolution as the detail route: the age can come from People.
      birthdate, today,
      windowDays: clampLimit(req.query.window_days, 7, 30),
    });
    // The night-waking analysis reads back further than the averages do: an
    // every-second-night rhythm needs a couple of weeks of nights before it can
    // be told apart from a run of bad luck.
    const analysis = sleepStats.analyzeWakings(entries, {
      birthdate, today,
      windowDays: clampLimit(req.query.analysis_days, 14, 30),
    });
    res.json({
      ...stats,
      wakings: analysis,
      recommendations: sleepStats.recommend(stats, analysis, { birthdate }),
    });
  } catch (err) { sendServerError(res, err); }
  finally { db.close(); }
});

// Calendar occurrences for an activity routine: the linked events (by the
// routine's config.calendar_keyword), recurrence expanded, each flagged as
// confirmed if a session was logged that day. Powers the "how often does this
// happen" cadence, the pending-confirmation list, and confirmation nudges.
app.get('/api/routines/:id/occurrences', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireRoutineAccess(db, req.params.id, req, res))) return;
    const routine = await db.getRoutineById(req.params.id);
    let cfg = {};
    try { cfg = JSON.parse(routine.config || '{}'); } catch {}
    const keyword = (cfg.calendar_keyword || '').trim();
    if (!keyword) return res.json({ keyword: null, occurrences: [], scheduled: 0, attended: 0 });

    const groupId = await db.getUserHouseholdId(req.session.user?.id);
    const today = todayLocal();
    const windowStart = fromLocalDate(-90);  // look back ~3 months
    const windowEnd = fromLocalDate(30);     // and ~1 month ahead
    const base = await db.getAppointmentsMatching(groupId, keyword, null, windowEnd);

    // Expand each matching event's occurrences within the window.
    const rangeStart = new Date(windowStart + 'T00:00:00');
    const rangeEnd = new Date(windowEnd + 'T00:00:00');
    const dates = new Set();
    for (const appt of base) {
      const origin = new Date(appt.appointment_date + 'T00:00:00');
      if (appt.appointment_date >= windowStart && appt.appointment_date <= windowEnd) {
        dates.add(appt.appointment_date);
      }
      if (appt.recurrence_rule) {
        const endDate = appt.recurrence_end ? new Date(appt.recurrence_end + 'T00:00:00') : null;
        for (const d of expandRecurrence(appt.recurrence_rule, origin, rangeStart, rangeEnd, endDate)) {
          dates.add(d.toLocaleDateString('en-CA'));
        }
      }
    }

    // Which dates already have a logged session.
    const entries = await db.getRoutineEntries(req.params.id, {});
    const confirmed = new Set(entries
      .filter(e => e.entry_type === 'session' || e.entry_type === 'attended')
      .map(e => e.entry_date));

    const occurrences = [...dates].sort().map(d => ({
      date: d, confirmed: confirmed.has(d), past: d < today, today: d === today,
    }));
    const pending = occurrences.filter(o => o.past && !o.confirmed);
    res.json({
      keyword,
      occurrences,
      scheduled: occurrences.length,
      attended: occurrences.filter(o => o.confirmed).length,
      pending,
    });
  } catch (err) { sendServerError(res, err); }
  finally { db.close(); }
});

// Activity feed (unified home feed)
// ============================================
// Direct Messages
// ============================================

app.get('/api/messages/unread-count', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const count = await db.getUnreadCount(req.session.user.id);
    sendCachedJson(req, res, req.session.user.id, { count });
  } catch (err) { sendServerError(res, err); }
  finally { db.close(); }
});

app.get('/api/messages', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const conversations = await db.getConversations(req.session.user.id);
    res.json(conversations);
  } catch (err) { sendServerError(res, err); }
  finally { db.close(); }
});

app.get('/api/messages/:partnerId', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const messages = await db.getMessages(req.session.user.id, parseInt(req.params.partnerId), {
      limit: clampLimit(req.query.limit, 50),
      before_id: req.query.before_id ? parseInt(req.query.before_id) : undefined,
      after_id: req.query.after_id ? parseInt(req.query.after_id) : undefined,
    });
    res.json(messages);
  } catch (err) { sendServerError(res, err); }
  finally { db.close(); }
});

app.get('/api/messages/:partnerId/:messageId/image', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const image = await db.getMessageImage(parseInt(req.params.messageId), req.session.user?.id);
    if (!image) return res.status(404).json({ error: 'No image' });
    if (!sendStoredImage(req, res, image)) return res.status(404).json({ error: 'No image' });
  } catch (err) { sendServerError(res, err); }
  finally { db.close(); }
});

app.post('/api/messages', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const senderId = req.session.user.id;
    const senderName = req.session.user.name;
    // Only message users you share a group with (no DMing arbitrary user ids).
    if (!(await canViewUser(db, req.body.recipient_id, senderId))) {
      return res.status(403).json({ error: 'Forbidden' });
    }
    const result = await db.sendMessage({
      sender_id: senderId,
      recipient_id: req.body.recipient_id,
      text: req.body.text,
      reference_type: req.body.reference_type,
      reference_id: req.body.reference_id,
      reference_title: req.body.reference_title,
      image_data: req.body.image_data
    });
    res.json({ success: true, id: result.id });
    // Push notification to recipient (enqueued; drain sends APNs)
    const text = req.body.image_data ? 'Sent you a photo' : (req.body.text || '');
    jobs.pushToUser(db, req.body.recipient_id, `Message from ${senderName}`, text, { type: 'message', ref_id: senderId, name: senderName });
  } catch (err) { sendServerError(res, err); }
  finally { db.close(); }
});

app.post('/api/messages/:partnerId/read', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    await db.markRead(req.session.user.id, parseInt(req.params.partnerId));
    res.json({ success: true });
  } catch (err) { sendServerError(res, err); }
  finally { db.close(); }
});

// Delete a direct message the caller SENT (removes its stored text/photo).
app.delete('/api/messages/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const row = await dbGet(db, 'SELECT sender_id FROM direct_messages WHERE id = ?', [req.params.id]);
    if (!row) return res.status(404).json({ error: 'Not found' });
    if (row.sender_id !== req.session.user.id) return res.status(403).json({ error: 'You can only delete your own messages' });
    await dbRun(db, 'DELETE FROM direct_messages WHERE id = ?', [req.params.id]);
    res.json({ success: true });
  } catch (err) { sendServerError(res, err); }
  finally { db.close(); }
});

app.get('/api/activity', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    const feed = await db.getActivityFeed(clampLimit(req.query.limit, 20), userId);
    sendCachedJson(req, res, userId, feed);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// ============================================
// Admin diagnostic + manual fix
// ============================================

app.get('/api/admin/diagnostic', requireAuth, requireAdmin, async (req, res) => {
  const db = new FamilyDB();
  try {
    const query = (sql, params = []) => new Promise((resolve, reject) => {
      db.db.all(sql, params, (err, rows) => err ? reject(err) : resolve(rows));
    });
    const users = await query('SELECT id, username, name FROM users');
    const groups = await query('SELECT * FROM groups');
    const members = await query(`SELECT gm.*, u.name as user_name, u.username
      FROM group_members gm LEFT JOIN users u ON u.id = gm.user_id`);
    const apptStats = await query(`SELECT group_id, COUNT(*) as count FROM appointments GROUP BY group_id`);
    const decisionStats = await query(`SELECT group_id, COUNT(*) as count FROM decisions GROUP BY group_id`);
    const totalAppts = await query('SELECT COUNT(*) as count FROM appointments');
    res.json({ users, groups, members, apptStats, decisionStats, totalAppts: totalAppts[0]?.count });
  } catch (err) { sendServerError(res, err); }
  finally { db.close(); }
});

app.post('/api/admin/fix-household', requireAuth, requireAdmin, async (req, res) => {
  const db = new FamilyDB();
  try {
    await db.runHouseholdMigrations();
    res.json({ success: true, message: 'Household migration completed' });
  } catch (err) { sendServerError(res, err); }
  finally { db.close(); }
});

// Grant or revoke a comp (non-billed) premium entitlement for a household.
// Body: { group_id, action: 'grant' | 'revoke' }. Admin-only.
app.post('/api/admin/comp', requireAuth, requireAdmin, async (req, res) => {
  const db = new FamilyDB();
  try {
    const groupId = parseInt(req.body.group_id);
    if (!Number.isInteger(groupId)) return res.status(400).json({ error: 'group_id required' });
    if (req.body.action === 'revoke') {
      await subscription.revokeCompForGroup(db, groupId);
    } else {
      await subscription.grantCompForGroup(db, groupId, req.session.user.id);
    }
    res.json({ success: true });
  } catch (err) { sendServerError(res, err); }
  finally { db.close(); }
});

// ============================================
// Lists
// ============================================

app.get('/api/lists', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    const lists = await db.getLists(userId);
    sendCachedJson(req, res, userId, lists);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.post('/api/lists', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    const result = await db.createList({ ...req.body, created_by: userId });
    res.json({ success: true, id: result.id });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.put('/api/lists/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireListAccess(db, req.params.id, req, res))) return;
    await db.updateList(req.params.id, req.body);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Pin a list to the home screen KPI card (unpins any other)
app.post('/api/lists/:id/pin', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireListAccess(db, req.params.id, req, res))) return;
    // Unpin the household's other lists first (NOT every user's lists)
    const userId = req.session.user?.id;
    await new Promise((resolve, reject) => {
      db.db.run(`UPDATE lists SET pinned = 0 WHERE pinned = 1 AND (created_by = ? OR created_by IN (
        SELECT gm2.user_id FROM group_members gm2
        JOIN groups g ON g.id = gm2.group_id AND g.group_type = 'household'
        WHERE gm2.group_id IN (SELECT group_id FROM group_members WHERE user_id = ?)))`,
        [userId, userId], (err) => err ? reject(err) : resolve());
    });
    // Pin the selected one
    await db.updateList(req.params.id, { pinned: 1 });
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.post('/api/lists/:id/unpin', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireListAccess(db, req.params.id, req, res))) return;
    await db.updateList(req.params.id, { pinned: 0 });
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.delete('/api/lists/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireListAccess(db, req.params.id, req, res))) return;
    await db.deleteList(req.params.id);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.get('/api/lists/:id/items', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireListAccess(db, req.params.id, req, res))) return;
    // Check if this is a grocery list and backfill missing categories
    const list = await new Promise((resolve, reject) => {
      db.db.get('SELECT name, list_type FROM lists WHERE id = ?', [req.params.id], (err, row) => err ? reject(err) : resolve(row));
    });
    const isGrocery = list && (
      list.list_type === 'grocery' ||
      ['groceries', 'grocery', 'costco', 'walmart'].includes((list.name || '').toLowerCase())
    );
    const items = await db.getListItems(req.params.id);
    if (isGrocery) {
      const missing = items.filter(item => !item.category);
      if (missing.length) {
        const run = (sql, p) => new Promise((res, rej) => db.db.run(sql, p, function (e) { e ? rej(e) : res(); }));
        const cases = [];
        const params = [];
        for (const item of missing) {
          item.category = FamilyDB.categorizeGroceryItem(item.title);
          cases.push('WHEN ? THEN ?');
          params.push(item.id, item.category);
        }
        const ids = missing.map(item => item.id);
        params.push(...ids);
        await run(
          `UPDATE list_items SET category = CASE id ${cases.join(' ')} END WHERE id IN (${ids.map(() => '?').join(',')})`,
          params
        );
      }
    }
    res.json(items);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.post('/api/lists/:id/items', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireListAccess(db, req.params.id, req, res))) return;
    const userName = req.session.user?.name || req.session.user?.username;
    // Auto-categorize if the parent list is a grocery list
    const list = await new Promise((resolve, reject) => {
      db.db.get('SELECT name, list_type FROM lists WHERE id = ?', [req.params.id], (err, row) => err ? reject(err) : resolve(row));
    });
    const isGrocery = list && (
      list.list_type === 'grocery' ||
      ['groceries', 'grocery', 'costco', 'walmart'].includes((list.name || '').toLowerCase())
    );
    const category = isGrocery
      ? FamilyDB.categorizeGroceryItem(req.body.title)
      : null;
    // Auto-fix list_type if it wasn't set
    if (isGrocery && list.list_type !== 'grocery') {
      db.db.run("UPDATE lists SET list_type = 'grocery' WHERE id = ?", [req.params.id]);
    }
    const result = await db.addListItem({ list_id: req.params.id, title: req.body.title, added_by: userName, category });
    res.json({ success: true, id: result.id, category });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.post('/api/lists/items/:id/toggle', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireListItemAccess(db, req.params.id, req, res))) return;
    await db.toggleListItem(req.params.id);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.put('/api/lists/items/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireListItemAccess(db, req.params.id, req, res))) return;
    const updates = { title: req.body.title };
    // Re-categorize if parent list is grocery type
    if (req.body.title) {
      const item = await new Promise((resolve, reject) => {
        db.db.get('SELECT li.list_id, l.list_type, l.name as list_name FROM list_items li JOIN lists l ON l.id = li.list_id WHERE li.id = ?',
          [req.params.id], (err, row) => err ? reject(err) : resolve(row));
      });
      const isGrocery = item && (
        item.list_type === 'grocery' ||
        ['groceries', 'grocery', 'costco', 'walmart'].includes((item.list_name || '').toLowerCase())
      );
      if (isGrocery) {
        updates.category = FamilyDB.categorizeGroceryItem(req.body.title);
      }
    }
    await db.updateListItem(req.params.id, updates);
    res.json({ success: true, category: updates.category || null });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.post('/api/lists/:id/reorder', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireListAccess(db, req.params.id, req, res))) return;
    await db.reorderListItems(req.params.id, req.body.ordered_ids);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

app.delete('/api/lists/items/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (!(await requireListItemAccess(db, req.params.id, req, res))) return;
    await db.deleteListItem(req.params.id);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// ============================================
// Coverage / Care Cascade
// ============================================

// Create a coverage request with windows and recipients
app.post('/api/coverage', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    const { reason, note, windows } = req.body;

    // Recipients must resolve to contacts the requester owns — otherwise
    // another user's contact names/phones would be disclosed via
    // GET /api/coverage/:id. Household members arrive as negative pseudo-ids
    // and are materialized into real owned contact rows (see helper).
    const rawIds = Array.isArray(req.body.contact_ids) ? req.body.contact_ids : [];
    if (rawIds.length > 20) return res.status(400).json({ error: 'Too many recipients' });
    const contact_ids = [];
    const clientIdFor = new Map();   // resolved contact id -> the id the client sent
    for (const rawId of rawIds) {
      const resolved = await resolveOwnedContactId(db, rawId, userId, res);
      if (resolved === null) return;  // 4xx already sent
      if (!contact_ids.includes(resolved)) { contact_ids.push(resolved); clientIdFor.set(resolved, Number(rawId)); }
    }

    // Create request
    const request = await db.createCoverageRequest({ requester_id: userId, reason, note });

    // Add windows (normalize dates)
    for (const w of (windows || [])) {
      const winData = { request_id: request.id, ...w };
      if (winData.window_date) winData.window_date = normalizeDate(winData.window_date);
      await db.addCoverageWindow(winData);
    }

    // Add recipients and generate invite tokens
    const recipients = [];
    for (const contactId of (contact_ids || [])) {
      const rec = await db.addCoverageRecipient({ request_id: request.id, contact_id: contactId });
      // The client keys its share buttons by the id it sent (household members
      // arrive as negative pseudo-ids), so hand that back alongside the link.
      recipients.push({ ...rec, contact_id: contactId, client_contact_id: clientIdFor.get(contactId) ?? contactId,
        share_url: coverageShareUrl(rec.invite_token) });
    }

    res.json({ success: true, id: request.id, recipients });

    // Push to helpers who are app users
    const senderName = req.session.user?.name || 'Someone';
    for (const contactId of (contact_ids || [])) {
      const helperId = await db.getUserIdByContactId(contactId);
      if (helperId) {
        jobs.pushToUser(db, helperId, `${senderName} needs your help`, reason || 'Coverage request', {
          type: 'coverage', ref_id: request.id
        });
      }
    }
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Incoming coverage requests for helpers (requests where user is a recipient)
app.get('/api/coverage/incoming', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    const requests = await db.getIncomingCoverageRequests(userId);
    res.json(requests);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// List my coverage requests
app.get('/api/coverage', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    const requests = await db.getCoverageRequests(userId);
    res.json(requests);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Approved coverage blocks for calendar display
app.get('/api/coverage/blocks', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    const { date_from, date_to } = req.query;
    const blocks = await db.getCoverageBlocks(userId, date_from, date_to);
    res.json(blocks);
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Get full details of a coverage request
app.get('/api/coverage/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const request = await db.getCoverageRequestById(req.params.id);
    if (!request) return res.status(404).json({ error: 'Not found' });
    // Only the requester or a named recipient (care-team member who is an app user) may view.
    const userId = req.session.user?.id;
    const recipient = await db.getRecipientByUserId(req.params.id, userId);
    if (request.requester_id !== userId && !recipient) {
      return res.status(403).json({ error: 'Forbidden' });
    }
    const windows = await db.getCoverageWindows(req.params.id);
    // The invite link is the requester's to share — a fellow recipient viewing
    // the request must not be handed everyone else's tokens.
    const isRequester = request.requester_id === userId;
    const recipients = (await db.getCoverageRecipients(req.params.id)).map(r => ({
      ...r,
      invite_token: isRequester ? r.invite_token : undefined,
      share_url: isRequester && r.invite_token && r.status !== 'approved' ? coverageShareUrl(r.invite_token) : undefined,
    }));
    const approvals = await db.getCoverageApprovals(req.params.id);
    res.json({ ...request, windows, recipients, approvals });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Cancel a coverage request
app.post('/api/coverage/:id/cancel', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const request = await db.getCoverageRequestById(req.params.id);
    if (!request) return res.status(404).json({ error: 'Not found' });
    if (request.requester_id !== req.session.user?.id) {
      return res.status(403).json({ error: 'Forbidden' });
    }
    await db.cancelCoverageRequest(req.params.id);
    res.json({ success: true });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// PUBLIC: Approve coverage via invite token (no auth required — care team member uses link)
app.get('/api/coverage/approve/:token', async (req, res) => {
  const db = new FamilyDB();
  try {
    const recipient = await db.getRecipientByToken(req.params.token);
    if (!recipient) return res.status(404).json({ error: 'Invalid or expired link' });
    const windows = await db.getCoverageWindows(recipient.request_id);
    res.json({
      contact_name: recipient.contact_name,
      requester_name: recipient.requester_name,
      reason: recipient.reason,
      note: recipient.note,
      request_id: recipient.request_id,
      recipient_id: recipient.id,
      status: recipient.status,
      windows
    });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// PUBLIC: the branded approval page a helper opens from the share link. No
// account needed. Everything the page shows comes from the same token lookup
// the JSON route uses; the form posts to /api/coverage/approve/:token.
app.get('/c/:token', async (req, res) => {
  const db = new FamilyDB();
  try {
    const token = String(req.params.token || '');
    const recipient = /^[a-f0-9]{16,64}$/i.test(token) ? await db.getRecipientByToken(token) : null;
    const windows = recipient ? await db.getCoverageWindows(recipient.request_id) : [];
    res.set('Cache-Control', 'no-store');
    res.type('html').send(coveragePage({ recipient, windows, token }));
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

function coveragePage({ recipient, windows, token }) {
  const esc = (v) => String(v ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const site = publicBaseUrl();
  const fmtDate = (iso) => {
    const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(iso || ''));
    if (!m) return esc(iso);
    const d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
    return d.toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' });
  };
  const fmtTime = (hm) => {
    const m = /^(\d{1,2}):(\d{2})/.exec(String(hm || ''));
    if (!m) return esc(hm);
    const h = Number(m[1]); const ap = h >= 12 ? 'pm' : 'am'; const h12 = ((h + 11) % 12) + 1;
    return `${h12}:${m[2]}${ap}`;
  };
  const head = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex"><title>Can you help? · Kinrows</title>
<link rel="icon" href="${site}/assets/favicon.png">
<style>
:root{--cream-1:#fdf5e0;--cream-2:#fbecca;--card:#fef8ea;--card-2:#fffdf6;--ink-1:#2a1f1a;--ink-2:#5a463a;--ink-3:#7a6353;--ink-4:#b8a394;--sage:#7ba05b;--terracotta:#c46a4a;--line:rgba(42,31,26,.10);--shadow:0 10px 30px rgba(120,74,46,.10),0 2px 8px rgba(120,74,46,.06)}
*{box-sizing:border-box}body{margin:0;font-family:"Inter",-apple-system,BlinkMacSystemFont,"Segoe UI",system-ui,sans-serif;background:radial-gradient(120% 80% at 50% -10%,var(--cream-2),var(--cream-1) 60%);color:var(--ink-1);min-height:100vh}
.wrap{max-width:520px;margin:0 auto;padding:28px 18px 60px}.brand{display:flex;align-items:center;gap:10px;font-weight:700;letter-spacing:-.01em;color:var(--ink-2);text-decoration:none;font-size:15px}.brand img{width:28px;height:28px;border-radius:8px}
.eyebrow{font-size:11px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:var(--sage);margin:26px 0 6px}h1{font-size:28px;line-height:1.15;margin:0 0 8px;letter-spacing:-.02em}.lede{color:var(--ink-3);margin:0 0 20px;font-size:15px;line-height:1.5}
.card{background:var(--card-2);border:1px solid var(--line);border-radius:22px;padding:16px;box-shadow:var(--shadow);margin-bottom:12px}.note{background:var(--card);border-radius:14px;padding:12px;color:var(--ink-2);font-style:italic;font-size:14px;margin-bottom:12px}
.label{font-size:11px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:var(--ink-3);margin:6px 0 10px}
.win{display:flex;gap:12px;align-items:center;padding:12px;border:1px solid var(--line);border-radius:14px;margin-bottom:8px;cursor:pointer;background:var(--card)}.win input{accent-color:var(--sage);width:18px;height:18px}.win b{display:block;font-size:15px}.win span{color:var(--sage);font-weight:600;font-size:13px}.win small{display:block;color:var(--ink-3);font-size:12px;margin-top:2px}
.row{display:flex;gap:8px}.field{flex:1}.field label{display:block;font-size:11px;font-weight:700;letter-spacing:.06em;text-transform:uppercase;color:var(--ink-3);margin-bottom:4px}input[type=time],textarea{width:100%;padding:10px 12px;border:1px solid var(--line);border-radius:12px;font:inherit;font-size:15px;background:var(--card)}textarea{min-height:64px;resize:vertical}
details{margin:6px 0 12px}summary{cursor:pointer;color:var(--ink-3);font-size:13px;font-weight:600}
.btn{display:block;width:100%;padding:15px;border:0;border-radius:999px;background:var(--sage);color:#fff;font:inherit;font-size:16px;font-weight:700;cursor:pointer;box-shadow:var(--shadow)}.btn[disabled]{opacity:.5;cursor:default}
.err{color:var(--terracotta);font-size:14px;margin:10px 0 0;min-height:1.2em}.done{text-align:center;padding:30px 10px}.done .tick{width:64px;height:64px;border-radius:50%;background:var(--sage);color:#fff;display:flex;align-items:center;justify-content:center;font-size:30px;margin:0 auto 14px}
.foot{margin-top:26px;color:var(--ink-4);font-size:12px;text-align:center}.foot a{color:var(--ink-3)}
</style></head><body><div class="wrap"><a class="brand" href="${site}/"><img src="${site}/assets/logo.png" alt=""> Kinrows</a>`;
  const foot = `<p class="foot">Sent from the Kinrows app. No account needed — this link is just for ${recipient ? esc(recipient.contact_name) : 'you'}. <a href="${site}/privacy.html">Privacy</a></p></div></body></html>`;

  if (!recipient) {
    return head + `<p class="eyebrow">Coverage request</p><h1>This link isn't valid any more.</h1><p class="lede">It may have been cancelled, or the address was copied incompletely. Ask whoever sent it to share it again.</p>` + foot;
  }
  const first = esc(String(recipient.requester_name || 'Someone').split(/\s+/)[0]);
  if (recipient.status === 'approved') {
    return head + `<p class="eyebrow">Coverage request</p><div class="done"><div class="tick">✓</div><h1>You're covering this. Thank you.</h1><p class="lede">${first} has been told. If anything changes, just let them know directly.</p></div>` + foot;
  }
  const winHtml = windows.map((w, i) => `<label class="win"><input type="radio" name="window_id" value="${w.id}" ${i === 0 ? 'checked' : ''} data-start="${esc(w.start_time)}" data-end="${esc(w.end_time)}"><div><b>${fmtDate(w.window_date)}</b><span>${fmtTime(w.start_time)} – ${fmtTime(w.end_time)}</span>${w.description ? `<small>${esc(w.description)}</small>` : ''}</div></label>`).join('');
  return head + `<p class="eyebrow">Hi ${esc(recipient.contact_name)}</p><h1>${first} needs a hand with <em>${esc((recipient.reason || 'some coverage').toLowerCase())}</em>.</h1><p class="lede">Pick a time that works and ${first} will get it on their calendar straight away.</p>
${recipient.note ? `<div class="note">“${esc(recipient.note)}”</div>` : ''}
<form class="card" id="f"><div class="label">When could you help?</div>${winHtml || '<p class="lede">No times were proposed — reply to ' + first + ' directly.</p>'}
<details><summary>I can do part of that window</summary><div class="row" style="margin-top:10px"><div class="field"><label for="s">From</label><input type="time" id="s" name="approved_start"></div><div class="field"><label for="e">To</label><input type="time" id="e" name="approved_end"></div></div></details>
<div class="field"><label for="n">A note for ${first} (optional)</label><textarea id="n" name="helper_note" placeholder="e.g. I'll bring the kids back by 3"></textarea></div>
<p class="err" id="err"></p><button class="btn" id="go" type="submit" ${windows.length ? '' : 'disabled'}>I can help</button></form>
<script>
(function(){var f=document.getElementById('f'),go=document.getElementById('go'),err=document.getElementById('err');
f.addEventListener('submit',async function(ev){ev.preventDefault();err.textContent='';go.disabled=true;go.textContent='Sending…';
var w=f.querySelector('input[name=window_id]:checked');var body={window_id:w?Number(w.value):null,helper_note:f.helper_note.value||''};
if(f.approved_start.value&&f.approved_end.value){body.approved_start=f.approved_start.value;body.approved_end=f.approved_end.value;}
try{var r=await fetch('/api/coverage/approve/${esc(token)}',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});var j=await r.json().catch(function(){return {}});
if(!r.ok){throw new Error(j.error||'Something went wrong');}
f.outerHTML='<div class="done"><div class="tick">✓</div><h1>Thank you — ${first} has been told.</h1><p class="lede">You\'ll hear from them if anything changes.</p></div>';}
catch(e){err.textContent=e.message;go.disabled=false;go.textContent='I can help';}});})();
</script>` + foot;
}

// PUBLIC: Submit approval (care team member confirms a window)
app.post('/api/coverage/approve/:token', async (req, res) => {
  const db = new FamilyDB();
  try {
    const recipient = await db.getRecipientByToken(req.params.token);
    if (!recipient) return res.status(404).json({ error: 'Invalid or expired link' });
    if (recipient.status === 'approved') return res.status(409).json({ error: 'Already approved' });

    const { window_id, helper_note } = req.body;
    const win = await requireWindowInRequest(db, window_id, recipient.request_id, res);
    if (!win) return;
    const times = resolveApprovalTimes(win, req.body, res);
    if (!times) return;
    const { approved_date, approved_start, approved_end } = times;

    await db.approveCoverage({
      request_id: recipient.request_id,
      recipient_id: recipient.id,
      window_id,
      approved_date,
      approved_start,
      approved_end,
      helper_note
    });

    // Push notification to requester
    const request = await db.getCoverageRequestById(recipient.request_id);
    if (request) {
      const helperName = recipient.contact_name || 'Your care team';
      const requesterName = recipient.requester_name || 'Family';
      const timeDesc = approved_start && approved_end ? `${approved_start}–${approved_end}` : 'a time block';
      jobs.pushToUser(db, request.requester_id, 'Coverage Confirmed', `${helperName} approved ${timeDesc}`, {
        type: 'coverage', ref_id: recipient.request_id
      });

      // Add coverage block to helper's calendar (if helper is an app user)
      const helperId = await db.getUserIdByContactId(recipient.contact_id);
      if (helperId && approved_date) {
        await db.addAppointment({
          title: `Helping ${requesterName} · ${request.reason || 'Coverage'}`,
          appointment_date: approved_date ? normalizeDate(approved_date) : null,
          appointment_time: approved_start || null,
          location: null,
          notes: helper_note || null,
          category: 'coverage',
          person_tags: [requesterName],
          group_id: await db.getUserHouseholdId(helperId)
        });
      }
    }

    res.json({ success: true, message: 'Coverage confirmed' });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Authenticated in-app approval (helper approves from their app)
app.post('/api/coverage/incoming/:id/approve', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    const requestId = parseInt(req.params.id);
    const recipient = await db.getRecipientByUserId(requestId, userId);
    if (!recipient) return res.status(404).json({ error: 'Not found' });
    if (recipient.status === 'approved') return res.status(409).json({ error: 'Already approved' });

    const { window_id, helper_note } = req.body;
    const win = await requireWindowInRequest(db, window_id, requestId, res);
    if (!win) return;
    const times = resolveApprovalTimes(win, req.body, res);
    if (!times) return;
    const { approved_date, approved_start, approved_end } = times;

    await db.approveCoverage({
      request_id: requestId,
      recipient_id: recipient.id,
      window_id,
      approved_date,
      approved_start,
      approved_end,
      helper_note
    });

    // Push to requester
    const request = await db.getCoverageRequestById(requestId);
    if (request) {
      const helperName = req.session.user?.name || 'Your care team';
      const timeDesc = approved_start && approved_end ? `${approved_start}–${approved_end}` : 'a time block';
      jobs.pushToUser(db, request.requester_id, 'Coverage Confirmed', `${helperName} approved ${timeDesc}`, {
        type: 'coverage', ref_id: requestId
      });

      // Add to helper's calendar
      if (approved_date) {
        await db.addAppointment({
          title: `Helping ${request.requester_name || 'Family'} · ${request.reason || 'Coverage'}`,
          appointment_date: normalizeDate(approved_date),
          appointment_time: approved_start || null,
          location: null,
          notes: helper_note || null,
          category: 'coverage',
          person_tags: [req.session.user?.name],
          group_id: await db.getUserHouseholdId(userId)
        });
      }
    }

    res.json({ success: true, message: 'Coverage confirmed' });
  } catch (err) {
    sendServerError(res, err);
  } finally {
    db.close();
  }
});

// Initialize database on startup — runs full schema.sql with proper async handling
async function initializeDatabase() {
  const db = new FamilyDB();
  try {
    await db.initSchema();
    await db.runHouseholdMigrations();
    await db.reattributeHouseholdsOnce();
    await subscription.ensureCompPremium(db);
    console.log('✅ Database initialized with full schema + household isolation');
  } catch (err) {
    console.error('❌ Database init error:', err.message);
    // Never serve traffic against a half-migrated schema — fail the boot so
    // the platform keeps the previous healthy deploy running.
    throw err;
  } finally {
    db.close();
  }
}

// ============================================================================
// Permagent self-hosted analytics: POST /api/permagent-analytics/collect
// ============================================================================
// IMPORTANT: This route is EXEMPT from global rate limiting — a normal browsing
// session can produce many pageviews and must never be throttled. It is also NOT
// gated behind auth — analytics must work for unauthenticated visitors.
// navigator.sendBeacon sends Content-Type: text/plain, so we accept text/* and
// parse defensively. Malformed bodies return 204, never 500.
app.post('/api/permagent-analytics/collect', textAny, (req, res) => {
  // textAny parser gives us req.body as a string (or empty string if no body)
  let body;
  
  // If body is already an object (shouldn't happen with textAny, but be defensive)
  if (typeof req.body === 'object' && req.body !== null) {
    body = req.body;
  } else if (typeof req.body === 'string') {
    try {
      body = JSON.parse(req.body);
    } catch {
      return res.status(204).send(); // malformed beacon: silent drop
    }
  } else {
    return res.status(204).send(); // no valid body
  }

  try {
    // Body shape: { k: 'pv'|'ev', p: string, r: string|null, n: string|null, d: object|null, s: string|null }
    const { k, p, r, n, d, s } = body;

    if (!k || !p) return res.status(204).send(); // required fields missing

    // Map kind: 'pv' -> 'pageview', 'ev' -> 'event'
    const kind = k === 'pv' ? 'pageview' : k === 'ev' ? 'event' : null;
    if (!kind) return res.status(204).send();

    // Parse path+query, extract UTM and other allowed params, store path WITHOUT query
    let path = p;
    let utm = { source: null, medium: null, campaign: null };
    try {
      const url = new URL(p, 'http://localhost'); // parse relative paths
      path = url.pathname;
      // Allowlist: utm_*, ref, gclid, fbclid
      if (url.searchParams.has('utm_source')) utm.source = url.searchParams.get('utm_source');
      if (url.searchParams.has('utm_medium')) utm.medium = url.searchParams.get('utm_medium');
      if (url.searchParams.has('utm_campaign')) utm.campaign = url.searchParams.get('utm_campaign');
    } catch {
      // If path parsing fails, store the string as-is
    }

    // Clamp string fields to their limits
    const referrer = (r || '').slice(0, 512) || null;
    const name = (n || '').slice(0, 128) || null;
    const sessionId = (s || '').slice(0, 64) || null;

    // Properties: flatten, drop nested objects/arrays, cap at 32 keys, 256 chars per value, 4 kb total
    let properties = null;
    if (d && typeof d === 'object' && !Array.isArray(d)) {
      const flat = {};
      const keys = Object.keys(d);
      for (let i = 0; i < Math.min(keys.length, 32); i++) {
        const key = keys[i];
        const val = d[key];
        // Keep only scalars: string, number, boolean
        if (val === null || val === undefined) continue;
        if (typeof val === 'object') continue; // skip nested objects and arrays
        const str = String(val).slice(0, 256);
        flat[key] = typeof val === 'string' ? str : val; // re-cast number/bool
      }
      // Truncate to 4kb if needed
      const propStr = JSON.stringify(flat);
      if (propStr.length > 4096) {
        // Truncate by removing values, starting from the end
        const truncated = {};
        let totalSize = 0;
        for (const [key, val] of Object.entries(flat)) {
          const valStr = JSON.stringify(val);
          if (totalSize + valStr.length + key.length + 4 > 4096) break;
          truncated[key] = val;
          totalSize += valStr.length + key.length + 4;
        }
        properties = truncated;
      } else {
        properties = flat;
      }
    }

    // Compute visitor_hash server-side: sha256(salt + user-agent + accept-language + UTC date)
    const SALT = process.env.PERMAGENT_ANALYTICS_SALT;
    let visitorHash = null;
    if (SALT) {
      const ua = req.get('user-agent') || '';
      const al = req.get('accept-language') || '';
      const date = new Date().toISOString().slice(0, 10); // YYYY-MM-DD
      const hash = crypto.createHash('sha256').update(SALT + ua + al + date).digest('hex');
      visitorHash = hash.slice(0, 32); // first 32 hex chars
    }

    // Set is_bot server-side from User-Agent
    const ua = (req.get('user-agent') || '').toLowerCase();
    const isBot = !ua || /bot|crawler|spider|headless|curl|python-requests|facebookexternalhit/.test(ua);

    // Resolve country from edge headers (Cloudflare, Vercel, Fly)
    let country = null;
    if (req.get('cf-ipcountry')) country = req.get('cf-ipcountry');
    else if (req.get('x-vercel-ip-country')) country = req.get('x-vercel-ip-country');
    // Note: Fly's x-forwarded-for region isn't exposed as easily; would need Fly-Client-IP parsing

    // Store the event
    const db = new FamilyDB();
    db.recordAnalyticsEvent({
      kind,
      path: path.slice(0, 512), // clamp path too
      referrer,
      name,
      visitorHash,
      properties,
      isBot,
      sessionId,
      utmSource: utm.source,
      utmMedium: utm.medium,
      utmCampaign: utm.campaign,
      country
    })
      .then(() => res.status(202).send()) // Accepted, no body
      .catch(() => res.status(202).send()) // Even on DB error, return 202 so browser doesn't retry
      .finally(() => db.close());
  } catch (err) {
    // Defensive: any error in analytics parsing should not break the response
    console.error('[analytics collect error]', err.message);
    res.status(202).send();
  }
});

// ============================================================================
// Permagent self-hosted analytics: GET /api/permagent-analytics/drain
// ============================================================================
// Authenticated drain for the Permagent daemon. Auth via x-permagent-key header.
// Query: ?since=<id>&limit=<n> (default limit 500, cap 1000).
// Returns events with id > since, ordered by id ASC, as JSON.
app.get('/api/permagent-analytics/drain', async (req, res) => {
  const KEY = process.env.PERMAGENT_ANALYTICS_KEY;

  // Fail closed: if the env var is not set or the header does not match, return 401
  if (!KEY || req.get('x-permagent-key') !== KEY) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  try {
    const since = Math.max(0, parseInt(req.query.since || '0', 10) || 0);
    const limit = Math.max(1, Math.min(parseInt(req.query.limit || '500', 10) || 500, 1000));

    const db = new FamilyDB();
    const payload = await db.drainAnalyticsEvents(since, limit);
    db.close();

    res.json(payload);
  } catch (err) {
    console.error('[analytics drain error]', err.message);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// 404 for unmatched API routes (avoids falling through to static/HTML).
app.use('/api', (req, res) => res.status(404).json({ error: 'Not found' }));

// Centralized error handler — last line of defense. Express 5 forwards rejected
// async handlers here. Logs server-side, returns an opaque message to clients.
// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  console.error('[unhandled]', err && err.stack ? err.stack : err);
  if (res.headersSent) return next(err);
  const isApi = req.path.startsWith('/api/');
  if (isApi) res.status(500).json({ error: 'Internal server error' });
  else res.status(500).send('Something went wrong. Please try again.');
});

// Last-resort process guards: log fire-and-forget failures (background pushes,
// brief regeneration) instead of dying silently; exit on truly unknown state.
process.on('unhandledRejection', (reason) => {
  console.error('[unhandledRejection]', reason && reason.stack ? reason.stack : reason);
});
process.on('uncaughtException', (err) => {
  console.error('[uncaughtException]', err && err.stack ? err.stack : err);
  process.exit(1);
});

// Start server after DB init
initializeDatabase().then(() => {
  const server = app.listen(PORT, () => {
    console.log('Kinrows running on port', PORT);
    console.log('AI features:', process.env.ANTHROPIC_API_KEY ? 'ENABLED' : 'DISABLED (no ANTHROPIC_API_KEY)');
    console.log('Stripe billing:', stripeBilling.isConfigured() ? 'ENABLED' : 'DISABLED (no STRIPE_SECRET_KEY)');
    startProactiveNudges();
    startDailyBriefs();
    startNightlyBackups();
    startOnboardingEmails();
    jobs.startWorker();
  });
  // Graceful shutdown on platform-issued SIGTERM (deploys/restarts): stop
  // accepting connections, let in-flight requests finish, then exit. WAL keeps
  // the DB crash-safe if the 10s drain window expires.
  process.on('SIGTERM', () => {
    console.log('SIGTERM received — draining connections');
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(0), 10000).unref();
  });
}).catch((err) => {
  console.error('FATAL: DB init/migration failed, refusing to start:', err && err.stack ? err.stack : err);
  process.exit(1);
});

// Nightly on-disk DB snapshots (VACUUM INTO), retained 14 days. Guards against
// bad migrations and corruption. Note: backups live on the same volume as the
// DB — offsite copies still need a disk snapshot or external sync.
function startNightlyBackups() {
  const fs = require('fs');
  const BACKUP_DIR = path.join(FamilyDB.DB_DIR, 'backups');
  const RETAIN = 14;
  const runBackup = async () => {
    const db = new FamilyDB();
    try {
      fs.mkdirSync(BACKUP_DIR, { recursive: true });
      const stamp = new Date().toISOString().slice(0, 10);
      const dest = path.join(BACKUP_DIR, `family-${stamp}.db`);
      if (!fs.existsSync(dest)) {
        await db.backupTo(dest);
        console.log('DB backup written:', dest);
      }
      const { purged } = await db.purgeDeletedSyncedEvents(30);
      if (purged) console.log(`Purged ${purged} soft-deleted synced calendar events`);
      const files = fs.readdirSync(BACKUP_DIR)
        .filter(f => /^family-\d{4}-\d{2}-\d{2}\.db$/.test(f)).sort();
      for (const f of files.slice(0, Math.max(0, files.length - RETAIN))) {
        fs.unlinkSync(path.join(BACKUP_DIR, f));
      }
    } catch (err) {
      console.error('DB backup failed:', err.message);
    } finally {
      db.close();
    }
  };
  runBackup(); // at boot, so every deploy day has a snapshot before any writes
  const handle = setInterval(runBackup, 24 * 60 * 60 * 1000);
  handle.unref();
}

// Onboarding email drip: sweep hourly during civil hours (nobody wants a
// "getting started" email at 3am). At most one stage per user per sweep;
// dedupe/idempotence lives in the onboarding_emails log, so redeploys and
// restarts are harmless.
function startOnboardingEmails() {
  const SWEEP_MS = 60 * 60 * 1000; // hourly
  const runIfDaytime = async () => {
    if (!email.isEmailEnabled()) return;
    const hour = new Date().getHours(); // server TZ (America/Halifax)
    if (hour < 9 || hour >= 20) return;
    const db = new FamilyDB();
    try {
      const summary = await runOnboardingEmailSweep(db);
      if (summary.sent || summary.errors) console.log('Onboarding emails:', JSON.stringify(summary));
    } catch (err) {
      console.error('Onboarding email sweep error:', err.message);
    } finally {
      db.close();
    }
  };
  const handle = setInterval(runIfDaytime, SWEEP_MS);
  handle.unref();
}

// Proactive concierge nudges: sweep premium households hourly, but only push
// during waking hours. Throttling/dedup lives in the sweep itself.
function startProactiveNudges() {
  const SWEEP_MS = 60 * 60 * 1000; // hourly
  const runIfDaytime = async () => {
    const hour = new Date().getHours(); // server TZ (America/Halifax)
    if (hour < 8 || hour >= 21) return;
    const db = new FamilyDB();
    try {
      const summary = await runProactiveSweep(db);
      if (summary.sent) console.log('Proactive nudges sent:', JSON.stringify(summary));
    } catch (err) {
      console.error('Proactive sweep error:', err.message);
    } finally {
      db.close();
    }
  };
  const handle = setInterval(runIfDaytime, SWEEP_MS);
  handle.unref(); // don't keep the process alive solely for the sweep
}

// Daily concierge brief → household feed. Same waking-hours window as nudges;
// one post per household per local day (dedupe lives in the sweep).
function startDailyBriefs() {
  const SWEEP_MS = 60 * 60 * 1000; // hourly
  let running = false;
  const runIfDaytime = async () => {
    const hour = new Date().getHours(); // server TZ (America/Halifax)
    if (hour < 8 || hour >= 21) return;
    if (running) return;
    running = true;
    const db = new FamilyDB();
    try {
      const summary = await runDailyBriefSweep(db);
      if (summary.posted) console.log('Daily briefs posted:', JSON.stringify(summary));
    } catch (err) {
      console.error('Daily brief sweep error:', err.message);
    } finally {
      db.close();
      running = false;
    }
  };
  runIfDaytime();
  const handle = setInterval(runIfDaytime, SWEEP_MS);
  handle.unref();
}
