/**
 * APNs Push Notification Service
 * Uses HTTP/2 directly — no external dependencies needed.
 */
const http2 = require('http2');
const crypto = require('crypto');

const APNS_PROD_HOST = 'api.push.apple.com';
const APNS_SANDBOX_HOST = 'api.sandbox.push.apple.com';
// Primary host honors APNS_ENV (default production), but we fall back to the
// other host per-token: debug/Xcode builds mint sandbox tokens while
// TestFlight/App Store builds mint production ones, and one household has both.
const PRIMARY_HOST = process.env.APNS_ENV === 'development' ? APNS_SANDBOX_HOST : APNS_PROD_HOST;
const ALTERNATE_HOST = PRIMARY_HOST === APNS_PROD_HOST ? APNS_SANDBOX_HOST : APNS_PROD_HOST;
const APNS_PORT = 443;

// Reasons that mean "valid credentials, wrong environment for this token" —
// retry the other host. BadEnvironmentKeyInToken is APNs's (undocumented) 403
// for exactly this; BadDeviceToken is the 400 variant.
const ENV_MISMATCH_REASONS = new Set(['BadEnvironmentKeyInToken', 'BadDeviceToken']);

// APNs auth key config (from environment variables)
const KEY_ID = process.env.APNS_KEY_ID;
const TEAM_ID = process.env.APNS_TEAM_ID;
const BUNDLE_ID = process.env.APNS_BUNDLE_ID || 'com.kinrows.app';
const KEY_BASE64 = process.env.APNS_KEY_BASE64; // .p8 key contents, base64-encoded

let _cachedToken = null;
let _tokenExpiry = 0;

function isConfigured() {
  return !!(KEY_ID && TEAM_ID && KEY_BASE64);
}

function getJWT() {
  const now = Math.floor(Date.now() / 1000);
  // Reuse token for 50 minutes (APNs tokens valid for 60 min)
  if (_cachedToken && now < _tokenExpiry) return _cachedToken;

  const header = Buffer.from(JSON.stringify({ alg: 'ES256', kid: KEY_ID })).toString('base64url');
  const claims = Buffer.from(JSON.stringify({ iss: TEAM_ID, iat: now })).toString('base64url');
  const signingInput = `${header}.${claims}`;

  const keyPem = Buffer.from(KEY_BASE64, 'base64').toString('utf8');
  const sign = crypto.createSign('SHA256');
  sign.update(signingInput);
  const derSig = sign.sign(keyPem);

  // Convert DER signature to raw r||s format for ES256
  const rawSig = derToRaw(derSig);
  const signature = rawSig.toString('base64url');

  _cachedToken = `${signingInput}.${signature}`;
  _tokenExpiry = now + 3000; // 50 minutes
  return _cachedToken;
}

function derToRaw(derSig) {
  // Parse DER SEQUENCE { INTEGER r, INTEGER s }
  let offset = 2; // skip SEQUENCE tag + length
  if (derSig[1] & 0x80) offset += (derSig[1] & 0x7f);

  // Read r
  offset++; // INTEGER tag
  let rLen = derSig[offset++];
  let rStart = offset;
  offset += rLen;

  // Read s
  offset++; // INTEGER tag
  let sLen = derSig[offset++];
  let sStart = offset;

  // Strip leading zero padding, pad to 32 bytes
  let r = derSig.subarray(rStart, rStart + rLen);
  let s = derSig.subarray(sStart, sStart + sLen);
  if (r.length > 32) r = r.subarray(r.length - 32);
  if (s.length > 32) s = s.subarray(s.length - 32);

  const raw = Buffer.alloc(64);
  r.copy(raw, 32 - r.length);
  s.copy(raw, 64 - s.length);
  return raw;
}

/**
 * Send a push notification to a single device token.
 * @param {string} deviceToken - hex device token
 * @param {object} payload - APNs payload { aps: { alert: { title, body }, sound, badge } }
 * @returns {Promise<boolean>} true if sent successfully
 */
function sendOnce(deviceToken, payload, host) {
  return new Promise((resolve) => {
    const client = http2.connect(`https://${host}:${APNS_PORT}`);
    client.on('error', () => { client.close(); resolve({ ok: false, reason: 'connect_error' }); });

    const jwt = getJWT();
    const body = JSON.stringify(payload);

    const req = client.request({
      ':method': 'POST',
      ':path': `/3/device/${deviceToken}`,
      'authorization': `bearer ${jwt}`,
      'apns-topic': BUNDLE_ID,
      'apns-push-type': 'alert',
      'apns-priority': '10',
      'content-type': 'application/json',
      'content-length': Buffer.byteLength(body),
    });

    req.on('response', (headers) => {
      const status = headers[':status'];
      if (status === 200) { client.close(); resolve({ ok: true }); return; }
      let data = '';
      req.on('data', (chunk) => { data += chunk; });
      req.on('end', () => {
        client.close();
        let reason = '';
        try { reason = JSON.parse(data).reason || ''; } catch { /* non-JSON body */ }
        resolve({ ok: false, status, reason, data });
      });
    });

    req.on('error', () => { client.close(); resolve({ ok: false, reason: 'request_error' }); });
    req.end(body);
  });
}

function sendPush(deviceToken, payload, db = null) {
  if (!isConfigured()) return Promise.resolve(false);

  return (async () => {
    let res = await sendOnce(deviceToken, payload, PRIMARY_HOST);
    // The same auth key is valid for both environments — only the host differs,
    // so an environment-mismatch reason just means "try the other host".
    if (!res.ok && ENV_MISMATCH_REASONS.has(res.reason)) {
      res = await sendOnce(deviceToken, payload, ALTERNATE_HOST);
    }
    if (!res.ok) {
      console.error(`APNs error ${res.status || ''} for ${deviceToken.substring(0, 8)}...: ${res.data || res.reason}`);
      // 410 Unregistered is Apple telling us the app is gone from this device.
      // Dropping it here is what stops a dead token being retried forever.
      //
      // Deliberately ONLY this reason. DeviceTokenNotForTopic and
      // BadDeviceToken also mean "this token is useless to us", but both are
      // what EVERY token returns if APNS_BUNDLE_ID is ever wrong — pruning on
      // them would let one bad env var empty the table. Unregistered is
      // per-device and cannot be mass-triggered by misconfiguration.
      if (db && res.reason === 'Unregistered') {
        try {
          await db.removeDeviceToken(deviceToken);
          console.log(`📱 Dropped unregistered token ${deviceToken.substring(0, 8)}…`);
        } catch (err) {
          console.error('Failed to drop unregistered token:', err.message);
        }
      }
    }
    return res.ok;
  })();
}

/**
 * Send push to multiple device tokens.
 * @param {string[]} tokens
 * @param {string} title
 * @param {string} body
 * @param {object} [data] - custom data payload
 */
async function pushToTokens(tokens, title, body, data = {}, db = null) {
  if (!isConfigured() || !tokens || tokens.length === 0) return;

  const payload = {
    aps: {
      alert: { title, body: body.substring(0, 200) },
      sound: 'default',
      'mutable-content': 1,
    },
    ...data,
  };

  const results = await Promise.allSettled(
    tokens.map(token => sendPush(token, payload, db))
  );

  const sent = results.filter(r => r.status === 'fulfilled' && r.value).length;
  if (sent > 0) console.log(`📱 Push sent to ${sent}/${tokens.length} devices`);
}

/**
 * Send push to a specific user (all their registered devices).
 * @param {FamilyDB} db
 * @param {number} userId
 * @param {string} title
 * @param {string} body
 * @param {object} [data]
 */
async function pushToUser(db, userId, title, body, data = {}) {
  try {
    const tokens = await db.getDeviceTokens(userId);
    await pushToTokens(tokens, title, body, data, db);
  } catch (err) {
    // Callers fire-and-forget (no queue). Swallow so an APNs blip cannot
    // reject the HTTP handler; log so the failure is still inspectable.
    console.error('[push] pushToUser failed:', err.message);
  }
}

/**
 * Send push to all members of a group EXCEPT the sender.
 * @param {FamilyDB} db
 * @param {number} groupId
 * @param {number} excludeUserId - don't notify the sender
 * @param {string} title
 * @param {string} body
 * @param {object} [data]
 */
async function pushToGroup(db, groupId, excludeUserId, title, body, data = {}) {
  try {
    const members = await db.getGroupMembers(groupId);
    const userIds = members
      .filter(m => m.user_id && m.user_id !== excludeUserId)
      .map(m => m.user_id);
    if (userIds.length === 0) return;

    const tokenRows = await db.getDeviceTokensForUsers(userIds);
    const tokens = tokenRows.map(r => r.token);
    await pushToTokens(tokens, title, body, data, db);
  } catch (err) {
    console.error('[push] pushToGroup failed:', err.message);
  }
}

// ---------------------------------------------------------------------------
// Diagnostics
// ---------------------------------------------------------------------------
// Push fails silently by design — an unconfigured server simply doesn't notify.
// That is right for production and useless when you are trying to work out why
// nothing arrived, so these two expose the state without ever revealing the key.

/// What this process actually believes about APNs. `keyParses` is the one that
/// catches the common mistake: APNS_KEY_BASE64 holding something other than the
/// base64 of a .p8 file's text.
function describeConfig() {
  let keyParses = false, keyError = null;
  if (KEY_BASE64) {
    try {
      const pem = Buffer.from(KEY_BASE64, 'base64').toString('utf8');
      if (!pem.includes('BEGIN PRIVATE KEY')) {
        keyError = 'decoded value is not a PEM private key — base64 the .p8 file itself, contents and all';
      } else {
        crypto.createPrivateKey(pem);
        keyParses = true;
      }
    } catch (err) {
      keyError = err.message;
    }
  }
  return {
    configured: isConfigured(),
    keyId: KEY_ID || null,
    teamId: TEAM_ID || null,
    bundleId: BUNDLE_ID,
    primaryHost: PRIMARY_HOST,
    alternateHost: ALTERNATE_HOST,
    hasKey: !!KEY_BASE64,
    keyParses,
    keyError,
  };
}

/// A single push whose verdict is RETURNED rather than logged and dropped —
/// including which host answered, so an environment mismatch is visible instead
/// of just looking like success. Same send path as real pushes, so a pass here
/// means real pushes work.
async function sendTest(deviceToken, { title = 'Kinrows', body = 'Test push' } = {}) {
  if (!isConfigured()) return { ok: false, reason: 'not_configured' };
  const payload = { aps: { alert: { title, body }, sound: 'default' } };

  let res = await sendOnce(deviceToken, payload, PRIMARY_HOST);
  if (res.ok) return { ...res, host: PRIMARY_HOST };
  if (ENV_MISMATCH_REASONS.has(res.reason)) {
    const alt = await sendOnce(deviceToken, payload, ALTERNATE_HOST);
    return { ...alt, host: ALTERNATE_HOST, fellBackFrom: PRIMARY_HOST };
  }
  return { ...res, host: PRIMARY_HOST };
}

module.exports = { isConfigured, pushToUser, pushToGroup, pushToTokens, describeConfig, sendTest };
