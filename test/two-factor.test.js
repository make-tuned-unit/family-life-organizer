// Email-2FA login flow. Boots a server with 2FA ON and AUTH_2FA_ECHO_CODE so the
// emailed code is returned in the response (no inbox needed). Run: npm test

const { test, before, after } = require('node:test');
const assert = require('node:assert');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const PORT = 3998;
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
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'fl-2fa-'));
  server = spawn('node', ['dashboard.js'], {
    cwd: path.join(__dirname, '..'),
    env: {
      ...process.env,
      PORT: String(PORT),
      FAMILY_DB_DIR: tmpDir,
      SESSION_SECRET: 'test-secret',
      NODE_ENV: 'test',
      ANTHROPIC_API_KEY: '',
      AUTH_2FA_ENABLED: '1',     // turn the feature on for this suite
      AUTH_2FA_ECHO_CODE: '1',   // echo the code back so the test can complete it
    },
    stdio: 'ignore',
  });
  await waitForHealth();
});

after(() => {
  if (server) server.kill('SIGKILL');
  if (tmpDir) fs.rmSync(tmpDir, { recursive: true, force: true });
});

test('first login enrolls email, code completes sign-in; thereafter code is required', async () => {
  const c = makeClient();
  // Register establishes a session directly (no 2FA at signup).
  const reg = await c('POST', '/api/auth/register', { username: 'dave_t', password: 'password123', name: 'Dave' });
  assert.equal(reg.status, 200);

  // A fresh login now requires 2FA and, with no email yet, asks to enroll one.
  const fresh = makeClient();
  const login = await fresh('POST', '/api/auth/login', { username: 'dave_t', password: 'password123' });
  assert.equal(login.status, 200);
  assert.equal(login.body.two_factor_required, true);
  assert.equal(login.body.status, 'enroll_email');
  const challenge = login.body.challenge;
  assert.ok(challenge);

  // Provide an email → server "sends" a code (echoed back in test mode).
  const setEmail = await fresh('POST', '/api/auth/login/email', { challenge, email: 'dave@example.com' });
  assert.equal(setEmail.status, 200);
  assert.equal(setEmail.body.status, 'code_sent');
  const code = setEmail.body.dev_code;
  assert.ok(/^\d{6}$/.test(code), 'a 6-digit code was issued');

  // Wrong code is rejected; correct code establishes the session.
  const wrong = await fresh('POST', '/api/auth/login/verify', { challenge, code: '000000' === code ? '111111' : '000000' });
  assert.equal(wrong.status, 401);

  const verify = await fresh('POST', '/api/auth/login/verify', { challenge, code });
  assert.equal(verify.status, 200);
  assert.equal(verify.body.success, true);

  // Session works now.
  const me = await fresh('GET', '/api/account/security');
  assert.equal(me.status, 200);
  assert.equal(me.body.email, 'dave@example.com');
  assert.equal(me.body.two_factor_enabled, true);

  // Second login: email already verified → code sent straight away.
  const again = makeClient();
  const login2 = await again('POST', '/api/auth/login', { username: 'dave_t', password: 'password123' });
  assert.equal(login2.body.status, 'code_sent');
  const v2 = await again('POST', '/api/auth/login/verify', { challenge: login2.body.challenge, code: login2.body.dev_code });
  assert.equal(v2.status, 200);
});

test('a used challenge cannot be replayed', async () => {
  const c = makeClient();
  await c('POST', '/api/auth/register', { username: 'erin_t', password: 'password123', name: 'Erin' });
  const fresh = makeClient();
  const login = await fresh('POST', '/api/auth/login', { username: 'erin_t', password: 'password123' });
  const challenge = login.body.challenge;
  const setEmail = await fresh('POST', '/api/auth/login/email', { challenge, email: 'erin@example.com' });
  const ok = await fresh('POST', '/api/auth/login/verify', { challenge, code: setEmail.body.dev_code });
  assert.equal(ok.status, 200);
  // Replaying the consumed challenge must fail.
  const replay = await fresh('POST', '/api/auth/login/verify', { challenge, code: setEmail.body.dev_code });
  assert.equal(replay.status, 400);
});

test('legacy web /login is blocked when 2FA is on (no bypass)', async () => {
  const res = await fetch(BASE + '/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: 'username=dave_t&password=password123',
    redirect: 'manual',
  });
  assert.equal(res.status, 403);
});
