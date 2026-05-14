/**
 * APNs Push Notification Service
 * Uses HTTP/2 directly — no external dependencies needed.
 */
const http2 = require('http2');
const crypto = require('crypto');

const APNS_HOST = process.env.APNS_ENV === 'development'
  ? 'api.sandbox.push.apple.com'
  : 'api.push.apple.com';
const APNS_PORT = 443;

// APNs auth key config (from environment variables)
const KEY_ID = process.env.APNS_KEY_ID;
const TEAM_ID = process.env.APNS_TEAM_ID;
const BUNDLE_ID = process.env.APNS_BUNDLE_ID || 'com.mylauft.kinrows';
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
function sendPush(deviceToken, payload) {
  if (!isConfigured()) return Promise.resolve(false);

  return new Promise((resolve) => {
    const client = http2.connect(`https://${APNS_HOST}:${APNS_PORT}`);
    client.on('error', () => { client.close(); resolve(false); });

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
      if (status === 200) {
        resolve(true);
      } else {
        let data = '';
        req.on('data', (chunk) => { data += chunk; });
        req.on('end', () => {
          console.error(`APNs error ${status} for ${deviceToken.substring(0, 8)}...: ${data}`);
          resolve(false);
        });
      }
      client.close();
    });

    req.on('error', () => { client.close(); resolve(false); });
    req.end(body);
  });
}

/**
 * Send push to multiple device tokens.
 * @param {string[]} tokens
 * @param {string} title
 * @param {string} body
 * @param {object} [data] - custom data payload
 */
async function pushToTokens(tokens, title, body, data = {}) {
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
    tokens.map(token => sendPush(token, payload))
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
  const tokens = await db.getDeviceTokens(userId);
  await pushToTokens(tokens, title, body, data);
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
  const members = await db.getGroupMembers(groupId);
  const userIds = members
    .filter(m => m.user_id && m.user_id !== excludeUserId)
    .map(m => m.user_id);
  if (userIds.length === 0) return;

  const tokenRows = await db.getDeviceTokensForUsers(userIds);
  const tokens = tokenRows.map(r => r.token);
  await pushToTokens(tokens, title, body, data);
}

module.exports = { isConfigured, pushToUser, pushToGroup, pushToTokens };
