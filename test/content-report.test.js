// In-app UGC report (Guideline 1.2). Participants can report a DM or a feed
// post they can already see; outsiders cannot.

const { test, before, after } = require('node:test');
const assert = require('node:assert');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const PORT = 3979;
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
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'fl-report-'));
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

test('report requires auth', async () => {
  const res = await fetch(BASE + '/api/content/report', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ content_type: 'message', ref_id: 1, reason: 'spam' }),
  });
  assert.equal(res.status, 401);
});

test('empty reason is 400', async () => {
  const a = makeClient();
  await a('POST', '/api/auth/register', { username: 'rep_empty', password: 'password123', name: 'Empty' });
  const res = await a('POST', '/api/content/report', { content_type: 'message', ref_id: 1, reason: '   ' });
  assert.equal(res.status, 400);
});

test('a DM participant can report; a stranger cannot', async () => {
  const owner = makeClient();
  const reg = await owner('POST', '/api/auth/register', {
    username: 'rep_dm_a', password: 'password123', name: 'DM A',
  });
  const invite = reg.body.household.invite_code;
  const peer = makeClient();
  const peerReg = await peer('POST', '/api/auth/register', {
    username: 'rep_dm_b', password: 'password123', name: 'DM B', invite_code: invite,
  });
  const peerId = peerReg.body.user.id;

  const sent = await owner('POST', '/api/messages', { recipient_id: peerId, text: 'hello there' });
  assert.equal(sent.status, 200, JSON.stringify(sent.body));
  const msgId = sent.body.id;

  const ok = await peer('POST', '/api/content/report', {
    content_type: 'message', ref_id: msgId, reason: 'harassment',
  });
  assert.equal(ok.status, 200, JSON.stringify(ok.body));
  assert.equal(ok.body.success, true);

  const stranger = makeClient();
  await stranger('POST', '/api/auth/register', {
    username: 'rep_dm_x', password: 'password123', name: 'Stranger',
  });
  const blocked = await stranger('POST', '/api/content/report', {
    content_type: 'message', ref_id: msgId, reason: 'harassment',
  });
  assert.ok(blocked.status === 403 || blocked.status === 404, JSON.stringify(blocked.body));
});

test('a household member can report a feed post; another household cannot', async () => {
  const owner = makeClient();
  await owner('POST', '/api/auth/register', {
    username: 'rep_feed_a', password: 'password123', name: 'Feed A',
  });
  const groups = await owner('GET', '/api/groups');
  const householdId = (groups.body || []).find(g => g.group_type === 'household').id;
  const post = await owner('POST', `/api/groups/${householdId}/feed`, { body: 'family news' });
  assert.equal(post.status, 200, JSON.stringify(post.body));
  const postId = post.body.id;

  const ok = await owner('POST', '/api/content/report', {
    content_type: 'feed', ref_id: postId, reason: 'spam',
  });
  assert.equal(ok.status, 200, JSON.stringify(ok.body));

  const outsider = makeClient();
  await outsider('POST', '/api/auth/register', {
    username: 'rep_feed_x', password: 'password123', name: 'Outsider',
  });
  const blocked = await outsider('POST', '/api/content/report', {
    content_type: 'feed', ref_id: postId, reason: 'spam',
  });
  assert.ok(blocked.status === 403 || blocked.status === 404, JSON.stringify(blocked.body));
});
