// Pre-launch security audit (2026-08-26): presence opt-in, notes mass-assignment,
// coverage token validation, account export, DMs after leaving a group, and
// api_keys wiped on account delete.

const { test, before, after } = require('node:test');
const assert = require('node:assert');
const { spawn } = require('node:child_process');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const sqlite3 = require('sqlite3');

const PORT = 3984;
const BASE = `http://127.0.0.1:${PORT}`;
let server, tmpDir;

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
    return { status: res.status, body: json, headers: res.headers };
  };
}

async function waitForHealth(t = 15000) {
  const s = Date.now();
  while (Date.now() - s < t) {
    try { if ((await fetch(BASE + '/healthz')).ok) return; } catch {}
    await new Promise(r => setTimeout(r, 200));
  }
  throw new Error('server did not become healthy');
}

before(async () => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'fl-sec-'));
  server = spawn('node', ['dashboard.js'], {
    cwd: path.join(__dirname, '..'),
    env: {
      ...process.env,
      PORT: String(PORT),
      FAMILY_DB_DIR: tmpDir,
      SESSION_SECRET: 'test',
      NODE_ENV: 'test',
      ANTHROPIC_API_KEY: '',
    },
    stdio: 'ignore',
  });
  await waitForHealth();
});
after(() => { if (server) server.kill('SIGKILL'); if (tmpDir) fs.rmSync(tmpDir, { recursive: true, force: true }); });

test('presence: posting GPS is refused until the user opts in server-side', async () => {
  const c = makeClient();
  await c('POST', '/api/auth/register', { username: 'sec_loc', password: 'password123', name: 'Loc' });
  const off = await c('POST', '/api/location', { lat: 44.65, lng: -63.57 });
  assert.equal(off.status, 403);
  const enable = await c('POST', '/api/account/presence', { enabled: true });
  assert.equal(enable.status, 200);
  const on = await c('POST', '/api/location', { lat: 44.65, lng: -63.57 });
  assert.equal(on.status, 200);
  const presence = await c('GET', '/api/household/presence');
  assert.equal(presence.status, 200);
  const me = presence.body.find(p => p.name === 'Loc');
  assert.ok(me);
  assert.equal(me.last_lat, 44.65);
  await c('POST', '/api/account/presence', { enabled: false });
  const after = await c('GET', '/api/household/presence');
  const me2 = after.body.find(p => p.name === 'Loc');
  assert.equal(me2.last_lat, null);
});

test('notes: owner cannot retarget group_id without going through shared_scope', async () => {
  const a = makeClient();
  const b = makeClient();
  const ra = await a('POST', '/api/auth/register', { username: 'sec_note_a', password: 'password123', name: 'NoteA' });
  const rb = await b('POST', '/api/auth/register', { username: 'sec_note_b', password: 'password123', name: 'NoteB' });
  const bHid = rb.body.household.id;
  await a('POST', '/api/notes', { title: 'Private', body: 'secret' });
  const list = await a('GET', '/api/notes');
  const note = list.body.find(n => n.title === 'Private');
  assert.ok(note);
  const sneak = await a('PUT', `/api/notes/${note.id}`, { group_id: bHid, title: 'Private' });
  assert.equal(sneak.status, 200);
  const bNotes = await b('GET', '/api/notes');
  assert.ok(!bNotes.body.some(n => n.id === note.id), 'B must not see A\'s note after a forged group_id');
});

test('coverage: non-hex tokens are 404 on the JSON approve routes', async () => {
  const anon = makeClient();
  const res = await anon('GET', '/api/coverage/approve/not-a-token');
  assert.equal(res.status, 404);
  const post = await anon('POST', '/api/coverage/approve/../../../etc/passwd', { window_id: 1 });
  assert.equal(post.status, 404);
});

test('coverage HTML sets CSP and robots.txt disallows /c/', async () => {
  const page = await fetch(`${BASE}/c/deadbeefdeadbeefdeadbeefdeadbeef`);
  assert.equal(page.status, 200);
  assert.ok((page.headers.get('content-security-policy') || '').includes("default-src 'self'"));
  const robots = await (await fetch(`${BASE}/robots.txt`)).text();
  assert.match(robots, /Disallow: \/c\//);
});

test('account export returns the caller\'s data and no password hash', async () => {
  const c = makeClient();
  await c('POST', '/api/auth/register', { username: 'sec_export', password: 'password123', name: 'Exporter' });
  await c('POST', '/api/notes', { title: 'Export me', body: 'hello' });
  const exp = await c('GET', '/api/account/export');
  assert.equal(exp.status, 200);
  assert.equal(exp.body.user.username, 'sec_export');
  assert.equal(exp.body.user.password_hash, undefined);
  assert.ok(exp.body.notes.some(n => n.title === 'Export me'));
  assert.match(exp.headers.get('content-disposition') || '', /kinrows-export\.json/);
});

test('DMs are unreadable after the partner leaves the shared group', async () => {
  const a = makeClient();
  const b = makeClient();
  const ra = await a('POST', '/api/auth/register', { username: 'sec_dm_a', password: 'password123', name: 'Dma' });
  const invite = ra.body.household.invite_code;
  const rb = await b('POST', '/api/auth/register', { username: 'sec_dm_b', password: 'password123', name: 'Dmb', invite_code: invite });
  const aId = ra.body.user.id;
  const bId = rb.body.user.id;
  const hid = ra.body.household.id;
  const sent = await a('POST', '/api/messages', { recipient_id: bId, text: 'hi from a' });
  assert.ok([200, 201].includes(sent.status), JSON.stringify(sent.body));
  const before = await a('GET', `/api/messages/${bId}`);
  assert.equal(before.status, 200);
  assert.ok(before.body.some(m => m.text === 'hi from a'));
  const left = await b('POST', `/api/groups/${hid}/leave`);
  assert.equal(left.status, 200, JSON.stringify(left.body));
  const after = await a('GET', `/api/messages/${bId}`);
  assert.equal(after.status, 403);
});

test('coverage: cancelled and expired share tokens 404', async () => {
  const c = makeClient();
  await c('POST', '/api/auth/register', { username: 'sec_cov', password: 'password123', name: 'Cov' });
  await c('POST', '/api/contacts', { name: 'Helper', relationship: 'friend' });
  const contacts = await c('GET', '/api/contacts');
  const contactId = contacts.body[0].id;
  const created = await c('POST', '/api/coverage', {
    reason: 'Need a sitter',
    windows: [{ window_date: '2026-09-01', start_time: '09:00', end_time: '12:00' }],
    contact_ids: [contactId],
  });
  assert.equal(created.status, 200, JSON.stringify(created.body));
  const token = created.body.recipients[0].invite_token;
  assert.match(token, /^[a-f0-9]{32}$/i);
  const live = await fetch(`${BASE}/api/coverage/approve/${token}`);
  assert.equal(live.status, 200);

  const cancelled = await c('POST', `/api/coverage/${created.body.id}/cancel`);
  assert.equal(cancelled.status, 200);
  const afterCancel = await fetch(`${BASE}/api/coverage/approve/${token}`);
  assert.equal(afterCancel.status, 404);

  const created2 = await c('POST', '/api/coverage', {
    reason: 'Need a sitter again',
    windows: [{ window_date: '2026-09-02', start_time: '09:00', end_time: '12:00' }],
    contact_ids: [contactId],
  });
  const token2 = created2.body.recipients[0].invite_token;
  await new Promise((resolve, reject) => {
    const db = new sqlite3.Database(path.join(tmpDir, 'family.db'));
    db.run(
      `UPDATE coverage_recipients SET created_at = datetime('now', '-31 days') WHERE invite_token = ?`,
      [token2],
      (err) => { db.close(); err ? reject(err) : resolve(); }
    );
  });
  const expired = await fetch(`${BASE}/api/coverage/approve/${token2}`);
  assert.equal(expired.status, 404);
});

test('admin diagnostic is fail-closed without ADMIN_USER_IDS', async () => {
  const c = makeClient();
  await c('POST', '/api/auth/register', { username: 'sec_admin', password: 'password123', name: 'Adminish' });
  const res = await c('GET', '/api/admin/diagnostic');
  assert.equal(res.status, 403);
  assert.ok(!res.body?.users);
});

test('v1 read-scope prefix does not classify write handlers as read', () => {
  const tools = require('../services/conciergeTools');
  assert.equal(tools.isReadOnly('calendar', { action: 'list' }), true);
  assert.equal(tools.isReadOnly('calendar', { action: 'add' }), false);
  assert.equal(tools.isReadOnly('routines', { action: 'chores' }), true);
  assert.equal(tools.isReadOnly('routines', { action: 'log_chore' }), false);
  assert.equal(tools.isReadOnly('routines', { action: 'analyze' }), true);
  assert.equal(tools.isReadOnly('budget', { action: 'log_expense' }), false);
  assert.equal(tools.isReadOnly('lists', { action: 'add' }), false);
  assert.equal(tools.isReadOnly('notes', { action: 'list' }), true);
  assert.equal(tools.isReadOnly('notes', { action: 'add' }), false);
});

test('account delete wipes api_keys so a leftover bearer cannot act', async () => {
  const c = makeClient();
  const reg = await c('POST', '/api/auth/register', { username: 'sec_keys', password: 'password123', name: 'Keyful' });
  assert.equal(reg.status, 200);
  const userId = reg.body.user.id;
  const raw = 'kr_live_' + crypto.randomBytes(32).toString('hex');
  const hash = crypto.createHash('sha256').update(raw).digest('hex');
  await new Promise((resolve, reject) => {
    const db = new sqlite3.Database(path.join(tmpDir, 'family.db'));
    db.run(
      `INSERT INTO api_keys (user_id, name, key_hash, key_prefix, scope) VALUES (?, 'agent', ?, 'kr_live_', 'write')`,
      [userId, hash],
      (err) => { db.close(); err ? reject(err) : resolve(); }
    );
  });
  const before = await fetch(BASE + '/v1/me', { headers: { Authorization: `Bearer ${raw}` } });
  // Key is valid until delete (may 402 without premium — either 200 or 402 means the key resolved)
  assert.ok([200, 402].includes(before.status), `key should resolve before delete, got ${before.status}`);
  const del = await c('POST', '/api/account/delete', { current_password: 'password123' });
  assert.equal(del.status, 200);
  const v1 = await fetch(BASE + '/v1/me', { headers: { Authorization: `Bearer ${raw}` } });
  assert.equal(v1.status, 401);
});
