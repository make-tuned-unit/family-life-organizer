// Household invite emails: founder types family addresses, server sends the
// invite code. Boots a real server; delivery is injected at the mailer.

const { test, before, after } = require('node:test');
const assert = require('node:assert');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('os');
const path = require('path');

const { parseEmails, householdInviteEmail, sendHouseholdInvites, MAX_PER_REQUEST } = require('../services/householdInvite');

const PORT = 3996;
const BASE = `http://127.0.0.1:${PORT}`;
let server, tmpDir;

function makeClient() {
  let cookie = '';
  return async (method, pathname, body) => {
    const res = await fetch(BASE + pathname, {
      method,
      headers: {
        'Content-Type': 'application/json',
        ...(cookie ? { Cookie: cookie } : {}),
      },
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

async function waitForHealth(t = 15000) {
  const s = Date.now();
  while (Date.now() - s < t) {
    try { if ((await fetch(BASE + '/healthz')).ok) return; } catch {}
    await new Promise(r => setTimeout(r, 200));
  }
  throw new Error('server did not become healthy');
}

before(async () => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'fl-hinv-'));
  server = spawn('node', ['dashboard.js'], {
    cwd: path.join(__dirname, '..'),
    env: {
      ...process.env,
      PORT: String(PORT),
      FAMILY_DB_DIR: tmpDir,
      SESSION_SECRET: 'test',
      NODE_ENV: 'test',
      ANTHROPIC_API_KEY: '',
      RESEND_API_KEY: '',
    },
    stdio: 'ignore',
  });
  await waitForHealth();
});
after(() => {
  if (server) server.kill('SIGKILL');
  if (tmpDir) fs.rmSync(tmpDir, { recursive: true, force: true });
});

test('parseEmails splits, lowercases, and dedupes', () => {
  assert.deepEqual(parseEmails('Ada@Example.com,  ada@example.com; bob@x.co'), ['ada@example.com', 'bob@x.co']);
  assert.deepEqual(parseEmails(['  Cam@Y.co ']), ['cam@y.co']);
});

test('parseEmails rejects empty, invalid, and oversized batches', () => {
  assert.throws(() => parseEmails(''), /at least one/i);
  assert.throws(() => parseEmails('not-an-email'), /valid email/i);
  const tooMany = Array.from({ length: MAX_PER_REQUEST + 1 }, (_, i) => `p${i}@x.co`);
  assert.throws(() => parseEmails(tooMany), /up to/i);
});

test('householdInviteEmail includes the code and join steps', () => {
  const msg = householdInviteEmail({
    inviterName: 'Jesse',
    householdName: 'The Fairbanks',
    inviteCode: 'ABCD12EF',
  });
  assert.match(msg.subject, /Jesse/);
  assert.match(msg.html, /ABCD12EF/);
  assert.match(msg.html, /I have an invite code/);
  assert.match(msg.text, /ABCD12EF/);
  assert.doesNotMatch(msg.html, /<script/i);
});

test('sendHouseholdInvites uses the injectable sender and reports per address', async () => {
  const sent = [];
  const send = async (msg) => {
    sent.push(msg);
    return { ok: msg.to !== 'fail@x.co', error: 'boom' };
  };
  const result = await sendHouseholdInvites({
    inviterName: 'Ada',
    householdName: 'Ada\'s Home',
    inviteCode: 'CODE1234',
    emails: ['ok@x.co', 'fail@x.co'],
    send,
  });
  assert.deepEqual(result.sent, ['ok@x.co']);
  assert.equal(result.failed.length, 1);
  assert.equal(result.failed[0].email, 'fail@x.co');
  assert.equal(sent.length, 2);
  assert.match(sent[0].subject, /Ada/);
  assert.match(sent[0].html, /CODE1234/);
});

test('POST /api/household/invite requires auth', async () => {
  const res = await fetch(BASE + '/api/household/invite', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ emails: ['a@b.co'] }),
  });
  assert.equal(res.status, 401);
});

test('POST /api/household/invite validates emails and needs mail configured', async () => {
  const c = makeClient();
  const reg = await c('POST', '/api/auth/register', {
    username: 'host_inv', password: 'password123', name: 'Host',
  });
  assert.equal(reg.status, 200);
  assert.ok(reg.body.household.invite_code);

  const bad = await c('POST', '/api/household/invite', { emails: ['nope'] });
  assert.equal(bad.status, 400);

  const empty = await c('POST', '/api/household/invite', { emails: [] });
  assert.equal(empty.status, 400);

  // Tests run without RESEND_API_KEY — founder still gets a clear fallback.
  const unconfigured = await c('POST', '/api/household/invite', { emails: ['partner@example.com'] });
  assert.equal(unconfigured.status, 503);
  assert.match(unconfigured.body.error, /copy the code/i);
});

test('POST /api/household/invite is forbidden without a household', async () => {
  const c = makeClient();
  const reg = await c('POST', '/api/auth/register', {
    username: 'solo_inv', password: 'password123', name: 'Solo',
  });
  assert.equal(reg.status, 200);
  const hid = reg.body.household.id;
  const left = await c('POST', `/api/groups/${hid}/leave`, {});
  assert.equal(left.status, 200);
  const invite = await c('POST', '/api/household/invite', { emails: ['x@y.co'] });
  assert.equal(invite.status, 403);
});
