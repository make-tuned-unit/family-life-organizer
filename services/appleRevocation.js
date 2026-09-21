// Fresh native reauthorization avoids retaining Apple refresh tokens at rest.
// The exchange result must belong to the account being erased before revoking.
const crypto = require('node:crypto');
const apple = require('./appleSignIn');
function isConfigured() {
  return !!(process.env.APPLE_SIGNIN_TEAM_ID && process.env.APPLE_SIGNIN_KEY_ID && process.env.APPLE_SIGNIN_KEY_BASE64);
}
function clientSecret(now = Math.floor(Date.now() / 1000)) {
  if (!isConfigured()) throw new Error('Apple revocation is not configured');
  const header = Buffer.from(JSON.stringify({ alg: 'ES256', kid: process.env.APPLE_SIGNIN_KEY_ID })).toString('base64url');
  const body = Buffer.from(JSON.stringify({ iss: process.env.APPLE_SIGNIN_TEAM_ID, iat: now, exp: now + 300, aud: apple.APPLE_ISS, sub: apple.audience() })).toString('base64url');
  const key = crypto.createPrivateKey(Buffer.from(process.env.APPLE_SIGNIN_KEY_BASE64, 'base64'));
  const signature = crypto.sign('sha256', Buffer.from(`${header}.${body}`), { key, dsaEncoding: 'ieee-p1363' }).toString('base64url');
  return `${header}.${body}.${signature}`;
}
async function revokeAuthorization({ authorizationCode, nonce, expectedSub }, fetcher = fetch) {
  if (!authorizationCode || typeof authorizationCode !== 'string' || authorizationCode.length > 10000) throw new Error('Fresh Apple authorization code required');
  const common = { client_id: apple.audience(), client_secret: clientSecret() };
  const post = async (path, fields) => fetcher(`${apple.APPLE_ISS}/auth/${path}`, {
    method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ ...common, ...fields }).toString(), signal: AbortSignal.timeout(15000),
  });
  const exchange = await post('token', { code: authorizationCode, grant_type: 'authorization_code' });
  if (!exchange.ok) throw new Error('Apple authorization exchange failed');
  const tokens = await exchange.json();
  const claims = await apple.verifyIdentityToken(tokens.id_token, { nonce });
  if (claims.sub !== expectedSub) throw new Error('Apple authorization does not match this account');
  const token = tokens.refresh_token || tokens.access_token;
  if (!token || typeof token !== 'string') throw new Error('Apple returned no revocable token');
  const result = await post('revoke', { token, token_type_hint: tokens.refresh_token ? 'refresh_token' : 'access_token' });
  if (!result.ok) throw new Error('Apple authorization revocation failed');
  // Apple's success is an empty 200 response. Never persist or log tokens.
}
module.exports = { isConfigured, clientSecret, revokeAuthorization };
