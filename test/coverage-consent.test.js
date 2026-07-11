// Coverage + group-member consent guards, including the household
// pseudo-contact path (the iOS roster sends id = -(user_id) for group
// members who aren't contact rows). Regression coverage for the guard
// that must NOT 403 asking your own household for help.

const { test, before, after } = require('node:test');
const assert = require('node:assert');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const PORT = 3995;
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
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'fl-consent-'));
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

test('coverage: household pseudo-contact (negative id) resolves and reaches the helper', async () => {
  // Pam registers and gets a household; Quinn joins it via invite code.
  const pam = makeClient();
  const regPam = await pam('POST', '/api/auth/register', { username: 'pam_c', password: 'password123', name: 'Pam Consent' });
  const invite = regPam.body.household.invite_code;
  const quinn = makeClient();
  const regQuinn = await quinn('POST', '/api/auth/register', { username: 'quinn_c', password: 'password123', name: 'Quinn Consent', invite_code: invite });
  const quinnId = regQuinn.body.user.id;

  // Pam asks Quinn for coverage using the pseudo-contact id the iOS roster
  // sends for household members who are not contact rows.
  const cov = await pam('POST', '/api/coverage', {
    reason: 'Watch the kids',
    windows: [{ window_date: '2026-07-14', start_time: '09:00', end_time: '12:00' }],
    contact_ids: [-quinnId],
  });
  assert.equal(cov.status, 200, `pseudo-contact coverage should succeed: ${JSON.stringify(cov.body)}`);
  assert.equal(cov.body.recipients.length, 1);

  // The materialized contact row makes the request visible to Quinn in-app.
  const incoming = await quinn('GET', '/api/coverage/incoming');
  assert.equal(incoming.status, 200);
  assert.ok(incoming.body.some(r => r.requester_name === 'Pam Consent'),
    'Quinn sees the incoming request');

  // And Quinn can approve it in-app — after picking a window, like the sheet does.
  const reqId = incoming.body.find(r => r.requester_name === 'Pam Consent').id;
  const detail = await quinn('GET', `/api/coverage/${reqId}`);
  const windowId = detail.body.windows[0].id;

  // Approving without a window is a clear 400, not a 500.
  const noWindow = await quinn('POST', `/api/coverage/incoming/${reqId}/approve`, {
    approved_date: '2026-07-14', approved_start: '09:00', approved_end: '12:00',
  });
  assert.equal(noWindow.status, 400);

  const approve = await quinn('POST', `/api/coverage/incoming/${reqId}/approve`, {
    window_id: windowId,
    approved_date: '2026-07-14', approved_start: '09:00', approved_end: '12:00',
  });
  assert.equal(approve.status, 200, `approve: ${JSON.stringify(approve.body)}`);
});

test('coverage: strangers are rejected on both paths', async () => {
  const sam = makeClient();
  await sam('POST', '/api/auth/register', { username: 'sam_c', password: 'password123', name: 'Sam Stranger' });
  const samMe = await sam('GET', '/api/auth/me');
  const samId = samMe.body.user.id;

  const pam = makeClient();
  await pam('POST', '/api/auth/login', { username: 'pam_c', password: 'password123' });
  // Pseudo-id for a user in NO shared group → 403.
  const covPseudo = await pam('POST', '/api/coverage', { reason: 't', windows: [], contact_ids: [-samId] });
  assert.equal(covPseudo.status, 403);
  // Someone else's positive contact id → 403 (Sam owns no contacts; use an
  // id owned by Pam but presented by Sam).
  await pam('POST', '/api/contacts', { name: 'Nana Pam', relationship: 'mom' });
  const pamContacts = await pam('GET', '/api/contacts');
  const nanaId = pamContacts.body[0].id;
  const covForeign = await sam('POST', '/api/coverage', { reason: 't', windows: [], contact_ids: [nanaId] });
  assert.equal(covForeign.status, 403);
});

test('group member-add: shared-group users allowed, strangers rejected, pseudo-ids translated', async () => {
  const pam = makeClient();
  await pam('POST', '/api/auth/login', { username: 'pam_c', password: 'password123' });
  const quinnMe = makeClient();
  await quinnMe('POST', '/api/auth/login', { username: 'quinn_c', password: 'password123' });
  const quinnId = (await quinnMe('GET', '/api/auth/me')).body.user.id;
  const samClient = makeClient();
  await samClient('POST', '/api/auth/login', { username: 'sam_c', password: 'password123' });
  const samId = (await samClient('GET', '/api/auth/me')).body.user.id;

  // Pam creates a clan; she can add Quinn (shares her household) by user_id
  // and by pseudo-contact id, but not stranger Sam.
  const clan = await pam('POST', '/api/groups', { name: 'Book Club', group_type: 'family' });
  const clanId = clan.body.id ?? clan.body.group?.id;
  assert.ok(clanId, `clan created: ${JSON.stringify(clan.body)}`);

  const addQuinn = await pam('POST', `/api/groups/${clanId}/members`, { user_id: quinnId });
  assert.equal(addQuinn.status, 200, `shared-group add allowed: ${JSON.stringify(addQuinn.body)}`);

  const addQuinnPseudo = await pam('POST', `/api/groups/${clanId}/members`, { contact_id: -quinnId });
  assert.equal(addQuinnPseudo.status, 200, 'pseudo-contact id translated to user add (idempotent)');

  const addSam = await pam('POST', `/api/groups/${clanId}/members`, { user_id: samId });
  assert.equal(addSam.status, 403, 'stranger rejected');
});
