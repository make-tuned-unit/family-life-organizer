// Sign in with Apple: identity-token verification, account create/link, and
// household assignment. Boots a real server; JWKS is injected via env so we
// never hit Apple.

const { test, before, after } = require('node:test');
const assert = require('node:assert');
const { spawn } = require('node:child_process');
const crypto = require('crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { sha256Hex } = require('../services/appleSignIn');

const PORT = 3986;
const BASE = `http://127.0.0.1:${PORT}`;
const AUD = 'com.kinrows.app';

const { publicKey, privateKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
const testJwk = publicKey.export({ format: 'jwk' });
testJwk.kid = 'test-kid';
testJwk.use = 'sig';
testJwk.alg = 'RS256';

let server;
let tmpDir;

function signJwt(payload, { kid = 'test-kid', alg = 'RS256' } = {}) {
  const header = Buffer.from(JSON.stringify({ alg, kid })).toString('base64url');
  const body = Buffer.from(JSON.stringify(payload)).toString('base64url');
  const sig = crypto.sign('sha256', Buffer.from(`${header}.${body}`), privateKey).toString('base64url');
  return `${header}.${body}.${sig}`;
}

function appleToken({ sub, nonce, email, emailVerified = true, aud = AUD, expOffset = 600, iss = 'https://appleid.apple.com' } = {}) {
  const now = Math.floor(Date.now() / 1000);
  return signJwt({
    iss,
    aud,
    sub,
    nonce: sha256Hex(nonce),
    email,
    email_verified: emailVerified,
    iat: now,
    exp: now + expOffset,
  });
}

async function post(pathname, body) {
  const res = await fetch(BASE + pathname, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  let json = null;
  try { json = await res.json(); } catch {}
  return { status: res.status, body: json };
}

function makeClient() {
  let cookie = '';
  return async (method, pathname, body) => {
    const res = await fetch(BASE + pathname, {
      method,
      headers: { 'Content-Type': 'application/json', ...(cookie ? { Cookie: cookie } : {}) },
      body: body ? JSON.stringify(body) : undefined,
      redirect: 'manual',
    });
    const sc = res.headers.get('set-cookie');
    if (sc) cookie = sc.split(';')[0];
    let json = null; try { json = await res.json(); } catch {}
    return { status: res.status, body: json };
  };
}

async function waitForHealth(timeoutMs = 15000) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    try {
      const res = await fetch(BASE + '/healthz');
      if (res.ok) return;
    } catch {}
    await new Promise((r) => setTimeout(r, 200));
  }
  throw new Error('server did not become healthy');
}

before(async () => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'fl-apple-'));
  server = spawn('node', ['dashboard.js'], {
    cwd: path.join(__dirname, '..'),
    env: {
      ...process.env,
      PORT: String(PORT),
      FAMILY_DB_DIR: tmpDir,
      SESSION_SECRET: 'test-secret',
      NODE_ENV: 'test',
      ANTHROPIC_API_KEY: '',
      APPLE_SIGNIN_TEST_JWK: JSON.stringify(testJwk),
      APPLE_SIGNIN_AUD: AUD,
    },
    stdio: 'ignore',
  });
  await waitForHealth();
});

after(() => {
  if (server) server.kill('SIGKILL');
  if (tmpDir) fs.rmSync(tmpDir, { recursive: true, force: true });
});

test('apple sign-in creates a household on first use', async () => {
  const nonce = 'nonce-create-1';
  const res = await post('/api/auth/apple', {
    identity_token: appleToken({ sub: 'apple-sub-1', nonce, email: 'one@privaterelay.appleid.com' }),
    nonce,
    name: 'Avery Apple',
    household_name: 'The Apples',
    device_name: 'test',
  });
  assert.equal(res.status, 200, JSON.stringify(res.body));
  assert.equal(res.body.success, true);
  assert.equal(res.body.created, true);
  assert.equal(res.body.user.name, 'Avery Apple');
  assert.ok(res.body.user.username.startsWith('apple_'));
  assert.ok(res.body.household.invite_code);
  assert.ok(res.body.refresh_token);
});

test('apple sign-in logs the same sub back into the existing account', async () => {
  const nonce1 = 'nonce-replay-a';
  const first = await post('/api/auth/apple', {
    identity_token: appleToken({ sub: 'apple-sub-2', nonce: nonce1, email: 'two@example.com' }),
    nonce: nonce1,
    name: 'Blair',
  });
  assert.equal(first.status, 200);
  const id = first.body.user.id;

  const nonce2 = 'nonce-replay-b';
  const second = await post('/api/auth/apple', {
    identity_token: appleToken({ sub: 'apple-sub-2', nonce: nonce2, email: 'two@example.com' }),
    nonce: nonce2,
  });
  assert.equal(second.status, 200);
  assert.equal(second.body.created, false);
  assert.equal(second.body.user.id, id);
  assert.equal(second.body.user.name, 'Blair');
});

test('apple sign-in with a bad audience is rejected', async () => {
  const nonce = 'nonce-badaud';
  const res = await post('/api/auth/apple', {
    identity_token: appleToken({ sub: 'apple-sub-3', nonce, aud: 'com.someone.else' }),
    nonce,
    name: 'Nope',
  });
  assert.equal(res.status, 401);
});

test('apple sign-in with a mismatched nonce is rejected', async () => {
  const res = await post('/api/auth/apple', {
    identity_token: appleToken({ sub: 'apple-sub-4', nonce: 'real-nonce' }),
    nonce: 'other-nonce',
    name: 'Nope',
  });
  assert.equal(res.status, 401);
});

test('apple join with an invalid invite code returns 400', async () => {
  const nonce = 'nonce-badinvite';
  const res = await post('/api/auth/apple', {
    identity_token: appleToken({ sub: 'apple-sub-5', nonce }),
    nonce,
    name: 'Joiner',
    invite_code: 'NOTAREALCODE',
  });
  assert.equal(res.status, 400);
  assert.match(res.body.error, /invite code/i);
});

test('apple join with a valid invite code lands in that household', async () => {
  const host = await post('/api/auth/register', {
    username: 'host_apple',
    password: 'password123',
    name: 'Host',
    household_name: 'Host House',
  });
  assert.equal(host.status, 200);
  const code = host.body.household.invite_code;

  const nonce = 'nonce-goodinvite';
  const res = await post('/api/auth/apple', {
    identity_token: appleToken({ sub: 'apple-sub-6', nonce, email: 'joiner@example.com' }),
    nonce,
    name: 'Guest',
    invite_code: code,
  });
  assert.equal(res.status, 200, JSON.stringify(res.body));
  assert.equal(res.body.household.invite_code, code);
});

test('apple sign-in links a verified-email password account instead of minting a second user', async () => {
  const email = 'linkme@example.com';
  const reg = await post('/api/auth/register', {
    username: 'link_me',
    password: 'password123',
    name: 'Linkable',
    email,
  });
  assert.equal(reg.status, 200);
  const originalId = reg.body.user.id;

  const { DatabaseSync } = require('node:sqlite');
  const db = new DatabaseSync(path.join(tmpDir, 'family.db'));
  db.prepare('UPDATE users SET email_verified = 1 WHERE username = ?').run('link_me');
  db.close();

  const nonce = 'nonce-link';
  const res = await post('/api/auth/apple', {
    identity_token: appleToken({ sub: 'apple-sub-link', nonce, email }),
    nonce,
    name: 'Should Be Ignored',
  });
  assert.equal(res.status, 200, JSON.stringify(res.body));
  assert.equal(res.body.created, false);
  assert.equal(res.body.user.id, originalId);
  assert.equal(res.body.user.username, 'link_me');
  assert.equal(res.body.user.name, 'Linkable');
});

test('SIWA account cannot delete with a dummy password; Apple identity token works', async () => {
  const c = makeClient();
  const nonce = 'nonce-del-siwa';
  const sub = 'apple-sub-del';
  const created = await c('POST', '/api/auth/apple', {
    identity_token: appleToken({ sub, nonce, email: 'del@privaterelay.appleid.com' }),
    nonce,
    name: 'Delete Me',
    device_name: 'test',
  });
  assert.equal(created.status, 200, JSON.stringify(created.body));
  const sec = await c('GET', '/api/account/security');
  assert.equal(sec.status, 200);
  assert.equal(sec.body.has_apple, true);

  const dummy = await c('POST', '/api/account/delete', { current_password: 'password123' });
  assert.equal(dummy.status, 401);

  const noCreds = await c('POST', '/api/account/delete', {});
  assert.equal(noCreds.status, 401);

  const nonce2 = 'nonce-del-siwa-ok';
  const ok = await c('POST', '/api/account/delete', {
    identity_token: appleToken({ sub, nonce: nonce2, email: 'del@privaterelay.appleid.com' }),
    nonce: nonce2,
  });
  assert.equal(ok.status, 200, JSON.stringify(ok.body));
  assert.equal((await c('GET', '/api/auth/me')).status, 401);
});
