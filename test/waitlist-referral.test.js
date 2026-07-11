// Waitlist referral program: signup returns a ref_code + position, referrals
// move you up, self-referral and bogus codes are ignored, and the status
// endpoint refreshes standing.

const { test, before, after } = require('node:test');
const assert = require('node:assert');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const PORT = 3991;
const BASE = `http://127.0.0.1:${PORT}`;
let server, tmpDir;

async function post(p, body) {
  const res = await fetch(BASE + p, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  return { status: res.status, body: await res.json().catch(() => ({})) };
}
async function get(p) {
  const res = await fetch(BASE + p);
  return { status: res.status, body: await res.json().catch(() => ({})) };
}
async function waitForHealth(t = 15000) {
  const s = Date.now();
  while (Date.now() - s < t) { try { if ((await fetch(BASE + '/healthz')).ok) return; } catch {} await new Promise(r => setTimeout(r, 200)); }
  throw new Error('server did not become healthy');
}

before(async () => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'fl-wl-'));
  server = spawn('node', ['dashboard.js'], {
    cwd: path.join(__dirname, '..'),
    env: { ...process.env, PORT: String(PORT), FAMILY_DB_DIR: tmpDir, SESSION_SECRET: 'test', NODE_ENV: 'test', ANTHROPIC_API_KEY: '', RESEND_API_KEY: '' },
    stdio: 'ignore',
  });
  await waitForHealth();
});
after(() => { if (server) server.kill('SIGKILL'); if (tmpDir) fs.rmSync(tmpDir, { recursive: true, force: true }); });

test('signup returns a ref_code and a position', async () => {
  const r = await post('/api/waitlist', { email: 'a@example.com' });
  assert.equal(r.status, 200);
  assert.equal(r.body.success, true);
  assert.match(r.body.ref_code, /^[a-f0-9]{10}$/, 'ref_code is a 10-hex code');
  assert.equal(r.body.position, 1);
  assert.equal(r.body.referrals, 0);
});

test('referrals move the referrer up the queue', async () => {
  const a = (await post('/api/waitlist', { email: 'lead@example.com' })).body; // position 2
  // Three people sign up AFTER lead — normally lead sits behind them.
  await post('/api/waitlist', { email: 'x@example.com' });
  await post('/api/waitlist', { email: 'y@example.com' });
  await post('/api/waitlist', { email: 'z@example.com' });

  const beforeRefs = (await get('/api/waitlist/status?ref_code=' + a.ref_code)).body;
  // Two of them join via lead's link → lead's referral count rises, position improves.
  await post('/api/waitlist', { email: 'ref1@example.com', ref: a.ref_code });
  await post('/api/waitlist', { email: 'ref2@example.com', ref: a.ref_code });

  const afterRefs = (await get('/api/waitlist/status?ref_code=' + a.ref_code)).body;
  assert.equal(afterRefs.referrals, 2, 'two credited referrals');
  assert.ok(afterRefs.position < beforeRefs.position, `position improved (${beforeRefs.position} -> ${afterRefs.position})`);
});

test('self-referral and bogus codes are ignored', async () => {
  const me = (await post('/api/waitlist', { email: 'self@example.com' })).body;
  // Re-submit with own code as ref — must not credit self.
  await post('/api/waitlist', { email: 'self@example.com', ref: me.ref_code });
  const standing = (await get('/api/waitlist/status?ref_code=' + me.ref_code)).body;
  assert.equal(standing.referrals, 0, 'no self-referral');

  // Bogus ref code on a new signup is silently ignored (still succeeds).
  const bogus = await post('/api/waitlist', { email: 'newbie@example.com', ref: 'deadbeef99' });
  assert.equal(bogus.status, 200);
  assert.ok(bogus.body.ref_code);
});

test('re-submitting the same email returns the same code (idempotent) + already flag', async () => {
  const first = (await post('/api/waitlist', { email: 'dup@example.com' })).body;
  const again = await post('/api/waitlist', { email: 'dup@example.com' });
  assert.equal(again.body.already, true);
  assert.equal(again.body.ref_code, first.ref_code, 'same code on re-signup');
});

test('status endpoint rejects malformed codes', async () => {
  assert.equal((await get('/api/waitlist/status?ref_code=NOT-VALID')).status, 400);
  assert.equal((await get('/api/waitlist/status?ref_code=abcdef0000')).status, 404);
});
