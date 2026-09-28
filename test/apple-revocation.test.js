const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const apple = require('../services/appleSignIn');
const revoke = require('../services/appleRevocation');
const signing = crypto.generateKeyPairSync('ec', { namedCurve: 'P-256' });
const identity = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
const nonce = 'revocation-test-nonce';
const keys = ['APPLE_SIGNIN_TEAM_ID', 'APPLE_SIGNIN_KEY_ID', 'APPLE_SIGNIN_KEY_BASE64', 'APPLE_SIGNIN_TEST_JWK'];
const original = Object.fromEntries(keys.map(k => [k, process.env[k]]));
before(() => {
  process.env.APPLE_SIGNIN_TEAM_ID = 'TESTTEAM';
  process.env.APPLE_SIGNIN_KEY_ID = 'TESTKEY';
  process.env.APPLE_SIGNIN_KEY_BASE64 = Buffer.from(signing.privateKey.export({ format: 'pem', type: 'pkcs8' })).toString('base64');
  process.env.APPLE_SIGNIN_TEST_JWK = JSON.stringify({ ...identity.publicKey.export({ format: 'jwk' }), kid: 'revocation-fixture' });
});
after(() => { for (const k of keys) { if (original[k] === undefined) delete process.env[k]; else process.env[k] = original[k]; } });
function token(sub = 'expected-user') {
  const h = Buffer.from(JSON.stringify({ alg: 'RS256', kid: 'revocation-fixture' })).toString('base64url');
  const p = Buffer.from(JSON.stringify({ iss: apple.APPLE_ISS, aud: apple.audience(), sub, nonce: apple.sha256Hex(nonce), iat: Math.floor(Date.now() / 1000), exp: Math.floor(Date.now() / 1000) + 600 })).toString('base64url');
  return `${h}.${p}.${crypto.sign('sha256', Buffer.from(`${h}.${p}`), identity.privateKey).toString('base64url')}`;
}
test('Apple client secret is a short-lived ES256 JWT bound to the app and team', () => {
  const [h, p, s] = revoke.clientSecret(1700000000).split('.');
  assert.equal(JSON.parse(Buffer.from(h, 'base64url')).alg, 'ES256');
  assert.deepEqual(JSON.parse(Buffer.from(p, 'base64url')), { iss: 'TESTTEAM', iat: 1700000000, exp: 1700000300, aud: apple.APPLE_ISS, sub: apple.audience() });
  assert.ok(crypto.verify('sha256', Buffer.from(`${h}.${p}`), { key: signing.publicKey, dsaEncoding: 'ieee-p1363' }, Buffer.from(s, 'base64url')));
});
test('Apple code exchange verifies identity then revokes the refresh token with an empty success response', async () => {
  const calls = [];
  await revoke.revokeAuthorization({ authorizationCode: 'fresh-fixture', nonce, expectedSub: 'expected-user' }, async (url, req) => {
    const form = new URLSearchParams(req.body); calls.push(url);
    assert.equal(req.method, 'POST'); assert.equal(form.get('client_id'), apple.audience());
    if (url.endsWith('/token')) {
      assert.equal(form.get('code'), 'fresh-fixture'); assert.equal(form.get('grant_type'), 'authorization_code');
      return new Response(JSON.stringify({ id_token: token(), refresh_token: 'test-refresh-only', access_token: 'test-access-only' }), { status: 200 });
    }
    assert.equal(form.get('token'), 'test-refresh-only'); assert.equal(form.get('token_type_hint'), 'refresh_token');
    return new Response(null, { status: 200 });
  });
  assert.deepEqual(calls, [`${apple.APPLE_ISS}/auth/token`, `${apple.APPLE_ISS}/auth/revoke`]);
});
test('Apple revocation fails closed on foreign identities, nonce mismatches, network and provider errors', async () => {
  const request = { authorizationCode: 'fresh-fixture', nonce, expectedSub: 'expected-user' };
  let calls = 0;
  await assert.rejects(revoke.revokeAuthorization(request, async () => { calls++; return new Response(JSON.stringify({ id_token: token('someone-else'), refresh_token: 'x' })); }), /does not match/);
  assert.equal(calls, 1, 'never revokes another account');
  await assert.rejects(revoke.revokeAuthorization({ ...request, nonce: 'wrong' }, async () => new Response(JSON.stringify({ id_token: token(), refresh_token: 'x' }))), /bad_nonce/);
  await assert.rejects(revoke.revokeAuthorization(request, async () => new Response('{}', { status: 400 })), /exchange failed/);
  await assert.rejects(revoke.revokeAuthorization(request, async url => url.endsWith('/token') ? new Response(JSON.stringify({ id_token: token(), refresh_token: 'x' })) : new Response('{}', { status: 500 })), /revocation failed/);
  await assert.rejects(revoke.revokeAuthorization(request, async () => { throw new Error('network'); }), /network/);
});
