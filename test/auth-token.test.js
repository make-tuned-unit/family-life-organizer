// Device refresh-token lifecycle: issue on login, rotate on token-login,
// reject replays, revoke on logout, revoke-all on password change.
// Boots a server with 2FA OFF (token issuance is independent of 2FA).

const { test, before, after } = require('node:test');
const assert = require('node:assert');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const PORT = 3997;
const BASE = `http://127.0.0.1:${PORT}`;
let server;
let tmpDir;

function makeClient() {
  let cookie = '';
  return async (method, pathname, body) => {
    const res = await fetch(BASE + pathname, {
      method,
      headers: { 'Content-Type': 'application/json', ...(cookie ? { Cookie: cookie } : {}) },
      body: body ? JSON.stringify(body) : undefined,
      redirect: 'manual',
    });
    const setCookie = res.headers.get('set-cookie');
    if (setCookie) cookie = setCookie.split(';')[0];
    let json = null;
    try { json = await res.json(); } catch {}
    return { status: res.status, body: json };
  };
}

async function waitForHealth(timeoutMs = 15000) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    try { if ((await fetch(BASE + '/healthz')).ok) return; } catch {}
    await new Promise(r => setTimeout(r, 200));
  }
  throw new Error('server did not become healthy');
}

before(async () => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'fl-token-'));
  server = spawn('node', ['dashboard.js'], {
    cwd: path.join(__dirname, '..'),
    env: {
      ...process.env,
      PORT: String(PORT),
      FAMILY_DB_DIR: tmpDir,
      SESSION_SECRET: 'test-secret',
      NODE_ENV: 'test',
      ANTHROPIC_API_KEY: '',
    },
    stdio: 'ignore',
  });
  await waitForHealth();
});

after(() => {
  if (server) server.kill('SIGKILL');
  if (tmpDir) fs.rmSync(tmpDir, { recursive: true, force: true });
});

test('login issues a refresh token; token-login works and rotates it', async () => {
  const c = makeClient();
  const reg = await c('POST', '/api/auth/register', { username: 'tina_t', password: 'password123', name: 'Tina' });
  assert.equal(reg.status, 200);
  assert.ok(reg.body.refresh_token, 'register returns a refresh token');

  const login = await makeClient()('POST', '/api/auth/login', { username: 'tina_t', password: 'password123' });
  assert.equal(login.status, 200);
  const token1 = login.body.refresh_token;
  assert.ok(token1 && token1.length >= 64, 'login returns a refresh token');

  // Token login establishes a session without a password.
  const device = makeClient();
  const tl = await device('POST', '/api/auth/token-login', { refresh_token: token1 });
  assert.equal(tl.status, 200);
  assert.equal(tl.body.user.username, 'tina_t');
  const token2 = tl.body.refresh_token;
  assert.ok(token2 && token2 !== token1, 'token rotates on use');

  // The session from token-login actually works.
  const me = await device('GET', '/api/auth/me');
  assert.equal(me.status, 200);

  // Replaying the rotated (old) token fails.
  const replay = await makeClient()('POST', '/api/auth/token-login', { refresh_token: token1 });
  assert.equal(replay.status, 401);

  // The fresh token still works.
  const tl2 = await makeClient()('POST', '/api/auth/token-login', { refresh_token: token2 });
  assert.equal(tl2.status, 200);
});

test('logout revokes the device token', async () => {
  const c = makeClient();
  await c('POST', '/api/auth/register', { username: 'uma_t', password: 'password123', name: 'Uma' });
  const login = await makeClient()('POST', '/api/auth/login', { username: 'uma_t', password: 'password123' });
  const token = login.body.refresh_token;

  const device = makeClient();
  await device('POST', '/api/auth/logout', { refresh_token: token });
  const after = await makeClient()('POST', '/api/auth/token-login', { refresh_token: token });
  assert.equal(after.status, 401, 'revoked token is rejected');
});

test('password change revokes all tokens but re-issues for this device', async () => {
  const c = makeClient();
  await c('POST', '/api/auth/register', { username: 'vic_t', password: 'password123', name: 'Vic' });

  const deviceA = makeClient();
  const loginA = await deviceA('POST', '/api/auth/login', { username: 'vic_t', password: 'password123' });
  const tokenA = loginA.body.refresh_token;

  const deviceB = makeClient();
  const loginB = await deviceB('POST', '/api/auth/login', { username: 'vic_t', password: 'password123' });
  const tokenB = loginB.body.refresh_token;

  // Device A changes the password.
  const change = await deviceA('POST', '/api/auth/change-password', {
    current_password: 'password123', new_password: 'newpassword456',
  });
  assert.equal(change.status, 200);
  const freshA = change.body.refresh_token;
  assert.ok(freshA, 'password change returns a fresh token for this device');

  // Device B's token (and A's old one) are dead; A's fresh one works.
  assert.equal((await makeClient()('POST', '/api/auth/token-login', { refresh_token: tokenB })).status, 401);
  assert.equal((await makeClient()('POST', '/api/auth/token-login', { refresh_token: tokenA })).status, 401);
  assert.equal((await makeClient()('POST', '/api/auth/token-login', { refresh_token: freshA })).status, 200);
});

test('garbage tokens are rejected', async () => {
  assert.equal((await makeClient()('POST', '/api/auth/token-login', { refresh_token: 'short' })).status, 400);
  assert.equal((await makeClient()('POST', '/api/auth/token-login', { refresh_token: 'f'.repeat(64) })).status, 401);
});
