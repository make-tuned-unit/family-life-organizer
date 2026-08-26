// Verifies a native Sign in with Apple identity token (JWT).
//
// This is NOT StoreKit (`appleVerify.js`). Apple ID tokens are RS256 JWTs
// whose signing keys live at Apple's JWKS endpoint, with `iss` =
// https://appleid.apple.com and `aud` = the app's bundle ID.
//
// Tests inject a public JWK via APPLE_SIGNIN_TEST_JWK so the suite never
// hits the network.

const crypto = require('crypto');

const APPLE_ISS = 'https://appleid.apple.com';
const APPLE_JWKS_URL = 'https://appleid.apple.com/auth/keys';
const JWKS_TTL_MS = 6 * 60 * 60 * 1000;
const CLOCK_SKEW_SECONDS = 60;

let cachedJwks = null;
let cachedAt = 0;

function audience() {
  return process.env.APPLE_SIGNIN_AUD || 'com.kinrows.app';
}

function b64urlToBuffer(str) {
  const pad = str.length % 4 === 0 ? '' : '='.repeat(4 - (str.length % 4));
  return Buffer.from(str.replace(/-/g, '+').replace(/_/g, '/') + pad, 'base64');
}

function decodeSegment(seg) {
  return JSON.parse(b64urlToBuffer(seg).toString('utf8'));
}

function sha256Hex(value) {
  return crypto.createHash('sha256').update(String(value)).digest('hex');
}

async function loadJwks() {
  if (process.env.APPLE_SIGNIN_TEST_JWK) {
    const key = JSON.parse(process.env.APPLE_SIGNIN_TEST_JWK);
    return { keys: [key] };
  }
  if (cachedJwks && Date.now() - cachedAt < JWKS_TTL_MS) return cachedJwks;
  const res = await fetch(APPLE_JWKS_URL);
  if (!res.ok) throw new Error('jwks_fetch_failed');
  cachedJwks = await res.json();
  cachedAt = Date.now();
  return cachedJwks;
}

function jwkToKey(jwk) {
  return crypto.createPublicKey({ key: jwk, format: 'jwk' });
}

function findKey(jwks, kid) {
  const keys = Array.isArray(jwks?.keys) ? jwks.keys : [];
  if (kid) {
    const match = keys.find((k) => k.kid === kid);
    if (match) return match;
  }
  if (keys.length === 1) return keys[0];
  return null;
}

function assertClaims(payload, { nonce, aud }) {
  if (payload.iss !== APPLE_ISS) throw new Error('bad_iss');
  const tokenAud = payload.aud;
  const audOk = Array.isArray(tokenAud) ? tokenAud.includes(aud) : tokenAud === aud;
  if (!audOk) throw new Error('bad_aud');
  if (!payload.sub || typeof payload.sub !== 'string') throw new Error('bad_sub');
  const now = Math.floor(Date.now() / 1000);
  if (typeof payload.exp !== 'number' || payload.exp + CLOCK_SKEW_SECONDS < now) {
    throw new Error('expired');
  }
  if (typeof payload.iat === 'number' && payload.iat - CLOCK_SKEW_SECONDS > now) {
    throw new Error('not_yet_valid');
  }
  if (!nonce || typeof nonce !== 'string') throw new Error('nonce_required');
  const expected = sha256Hex(nonce);
  if (payload.nonce !== expected) throw new Error('bad_nonce');
}

/**
 * @param {string} identityToken Apple identity JWT
 * @param {{ nonce: string, audience?: string }} opts raw nonce the client hashed into the request
 * @returns {Promise<{ sub: string, email: string|null, emailVerified: boolean }>}
 */
async function verifyIdentityToken(identityToken, opts = {}) {
  if (typeof identityToken !== 'string' || identityToken.split('.').length !== 3) {
    throw new Error('invalid_token');
  }
  const [h, p, s] = identityToken.split('.');
  let header;
  let payload;
  try {
    header = decodeSegment(h);
    payload = decodeSegment(p);
  } catch {
    throw new Error('invalid_token');
  }
  if (header.alg !== 'RS256') throw new Error('bad_alg');

  const jwks = await loadJwks();
  const jwk = findKey(jwks, header.kid);
  if (!jwk) throw new Error('unknown_kid');

  const ok = crypto.verify(
    'sha256',
    Buffer.from(`${h}.${p}`),
    jwkToKey(jwk),
    b64urlToBuffer(s)
  );
  if (!ok) throw new Error('bad_signature');

  assertClaims(payload, { nonce: opts.nonce, aud: opts.audience || audience() });

  const email = typeof payload.email === 'string' && payload.email.trim()
    ? payload.email.trim().toLowerCase()
    : null;
  const emailVerified = payload.email_verified === true || payload.email_verified === 'true';
  return { sub: payload.sub, email, emailVerified };
}

module.exports = {
  APPLE_ISS,
  audience,
  sha256Hex,
  verifyIdentityToken,
};
