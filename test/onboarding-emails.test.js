// Onboarding email drip: staged sequence with spacing from the previous send,
// idempotent send log, tier-tailored concierge content, and token-based
// unsubscribe (page + RFC 8058 one-click) that excludes users from the sweep.

const { test, before, after } = require('node:test');
const assert = require('node:assert');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const PORT = 3990;
const BASE = `http://127.0.0.1:${PORT}`;
let server, tmpDir, FamilyDB, onboarding;

async function post(p, body) {
  const res = await fetch(BASE + p, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body || {}) });
  return { status: res.status, body: await res.json().catch(() => ({})) };
}
async function waitForHealth(t = 15000) {
  const s = Date.now();
  while (Date.now() - s < t) { try { if ((await fetch(BASE + '/healthz')).ok) return; } catch {} await new Promise(r => setTimeout(r, 200)); }
  throw new Error('server did not become healthy');
}

// Small raw-SQL helpers over a FamilyDB instance (test-only backdoor).
const run = (db, sql, params = []) => new Promise((res, rej) => db.db.run(sql, params, (e) => e ? rej(e) : res()));
const get = (db, sql, params = []) => new Promise((res, rej) => db.db.get(sql, params, (e, r) => e ? rej(e) : res(r)));

before(async () => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'fl-onb-'));
  process.env.FAMILY_DB_DIR = tmpDir; // must precede require('../database')
  server = spawn('node', ['dashboard.js'], {
    cwd: path.join(__dirname, '..'),
    env: { ...process.env, PORT: String(PORT), FAMILY_DB_DIR: tmpDir, SESSION_SECRET: 'test', NODE_ENV: 'test', ANTHROPIC_API_KEY: '', RESEND_API_KEY: '' },
    stdio: 'ignore',
  });
  await waitForHealth();
  FamilyDB = require('../database');
  onboarding = require('../services/onboardingEmail');
});
after(() => { if (server) server.kill('SIGKILL'); if (tmpDir) fs.rmSync(tmpDir, { recursive: true, force: true }); });

// Registers a user via the real API, then marks a verified email directly.
async function makeVerifiedUser(username, email) {
  const r = await post('/api/auth/register', { username, password: 'hunter22!', name: `${username[0].toUpperCase()}${username.slice(1)} Test` });
  assert.equal(r.status, 200, `register ${username}`);
  const db = new FamilyDB();
  try {
    await run(db, 'UPDATE users SET email = ?, email_verified = 1 WHERE username = ?', [email, username]);
    const row = await get(db, 'SELECT id FROM users WHERE username = ?', [username]);
    return row.id;
  } finally { db.close(); }
}

function fakeSender() {
  const sent = [];
  const send = async (msg) => { sent.push(msg); return { ok: true, id: `fake-${sent.length}` }; };
  return { sent, send };
}

test('nextDueStage walks the sequence with per-stage spacing', () => {
  const { nextDueStage } = onboarding;
  const now = Date.parse('2026-08-04T12:00:00Z');
  const at = (iso) => ({ sent_at: iso.replace('T', ' ').replace('Z', '') });

  assert.equal(nextDueStage([], now).key, 'welcome', 'welcome is due immediately');
  assert.equal(nextDueStage([{ email_key: 'welcome', ...at('2026-08-04T11:00:00Z') }], now), null, 'household not due 1h after welcome');
  assert.equal(nextDueStage([{ email_key: 'welcome', ...at('2026-08-01T11:00:00Z') }], now).key, 'household', 'household due 3 days after welcome');
  const done = onboarding.STAGES.map(s => ({ email_key: s.key, ...at('2026-07-01T00:00:00Z') }));
  assert.equal(nextDueStage(done, now), null, 'complete sequence sends nothing');
});

test('sweep sends welcome once, with unsubscribe link, headers and invite code', async () => {
  await makeVerifiedUser('onbalice', 'alice@example.com');
  const db = new FamilyDB();
  try {
    const { sent, send } = fakeSender();
    const s1 = await onboarding.runOnboardingEmailSweep(db, { send });
    assert.equal(s1.sent, 1, 'first sweep sends the welcome');
    assert.equal(sent[0].to, 'alice@example.com');
    assert.match(sent[0].subject, /Welcome to Kinrows/);
    assert.match(sent[0].html, /api\/email\/unsubscribe\?token=/, 'html carries the unsubscribe link');
    assert.match(sent[0].text, /Unsubscribe: http/, 'text carries the unsubscribe link');
    assert.equal(sent[0].headers['List-Unsubscribe-Post'], 'List-Unsubscribe=One-Click');
    assert.match(sent[0].html, /household invite code/i, 'welcome surfaces the invite code');

    const s2 = await onboarding.runOnboardingEmailSweep(db, { send });
    assert.equal(s2.sent, 0, 'immediate re-sweep sends nothing (log guard)');
  } finally { db.close(); }
});

test('stages unlock in order as prior sends age', async () => {
  const db = new FamilyDB();
  try {
    const row = await get(db, 'SELECT id FROM users WHERE username = ?', ['onbalice']);
    // Backdate the welcome 3 days: household (+2d) becomes due, concierge is not.
    await run(db, `UPDATE onboarding_emails SET sent_at = datetime('now', '-3 days') WHERE user_id = ?`, [row.id]);
    const { sent, send } = fakeSender();
    const s = await onboarding.runOnboardingEmailSweep(db, { send });
    assert.equal(s.sent, 1);
    assert.match(sent[0].subject, /better with your people/i, 'household stage is next');

    const again = await onboarding.runOnboardingEmailSweep(db, { send });
    assert.equal(again.sent, 0, 'concierge stage still gated behind its spacing');
  } finally { db.close(); }
});

test('unverified emails and opted-out users are excluded', async () => {
  // Unverified: has an email but never proved it.
  await post('/api/auth/register', { username: 'onbbob', password: 'hunter22!', name: 'Bob Test' });
  const db = new FamilyDB();
  try {
    await run(db, `UPDATE users SET email = 'bob@example.com', email_verified = 0 WHERE username = 'onbbob'`);
    const { sent, send } = fakeSender();
    await onboarding.runOnboardingEmailSweep(db, { send });
    assert.ok(!sent.some(m => m.to === 'bob@example.com'), 'unverified address never emailed');
  } finally { db.close(); }
});

test('unsubscribe page and one-click POST both flip the opt-out and stop the drip', async () => {
  const carolId = await makeVerifiedUser('onbcarol', 'carol@example.com');
  const db = new FamilyDB();
  try {
    const token = await db.ensureUnsubscribeToken(carolId);
    assert.match(token, /^[a-f0-9]{48}$/);

    const page = await fetch(`${BASE}/api/email/unsubscribe?token=${token}`);
    assert.equal(page.status, 200);
    assert.match(await page.text(), /unsubscribed/i);

    const row = await get(db, 'SELECT email_opt_out FROM users WHERE id = ?', [carolId]);
    assert.equal(row.email_opt_out, 1, 'GET set the opt-out flag');

    const { sent, send } = fakeSender();
    await onboarding.runOnboardingEmailSweep(db, { send });
    assert.ok(!sent.some(m => m.to === 'carol@example.com'), 'opted-out user excluded from sweep');

    // One-click POST is also accepted (mail clients hit this for the header).
    const oneClick = await post(`/api/email/unsubscribe?token=${token}`);
    assert.equal(oneClick.status, 200);
    assert.equal(oneClick.body.success, true);
  } finally { db.close(); }
});

test('concierge stage tailors copy to the household tier', () => {
  const free = onboarding.TEMPLATES.concierge({ tier: null, firstName: 'Ada', inviteCode: null, unsubUrl: 'https://x/unsub' });
  assert.match(free.subject, /Meet the Concierge/);
  assert.match(free.sections, /More &rarr; AI Concierge/, 'free copy points at the opt-in switch');

  const paid = onboarding.TEMPLATES.concierge({ tier: 'premium', firstName: 'Ada', inviteCode: null, unsubUrl: 'https://x/unsub' });
  assert.match(paid.subject, /Getting the most/);
  assert.doesNotMatch(paid.sections, /optional assistant/, 'no upsell pitch for subscribed households');
});
