// End-to-end authorization & household-isolation tests.
// Boots the real server against a throwaway SQLite DB and exercises the auth +
// IDOR guards over HTTP. Run: npm test
//
// These lock in the multi-round IDOR/isolation work so a careless edit can't
// silently reintroduce a cross-household hole.

const { test, before, after } = require('node:test');
const assert = require('node:assert');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const PORT = 3999;
const BASE = `http://127.0.0.1:${PORT}`;
let server;
let tmpDir;

// Minimal cookie-aware fetch: tracks one session cookie per "agent".
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

async function waitForHealth(timeoutMs = 15000) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    try {
      const res = await fetch(BASE + '/healthz');
      if (res.ok) return;
    } catch {}
    await new Promise(r => setTimeout(r, 200));
  }
  throw new Error('server did not become healthy');
}

before(async () => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'fl-test-'));
  server = spawn('node', ['dashboard.js'], {
    cwd: path.join(__dirname, '..'),
    env: {
      ...process.env,
      PORT: String(PORT),
      FAMILY_DB_DIR: tmpDir,
      SESSION_SECRET: 'test-secret',
      NODE_ENV: 'test',
      ANTHROPIC_API_KEY: '',
      // 2FA is off by default; this suite covers password/IDOR (2FA has its own suite).
    },
    stdio: 'ignore',
  });
  await waitForHealth();
});

after(() => {
  if (server) server.kill('SIGKILL');
  if (tmpDir) fs.rmSync(tmpDir, { recursive: true, force: true });
});

test('healthz responds ok', async () => {
  const res = await fetch(BASE + '/healthz');
  assert.equal(res.status, 200);
});

test('register enforces an 8+ char password', async () => {
  const c = makeClient();
  const res = await c('POST', '/api/auth/register', { username: 'shortpw', password: 'abc', name: 'Short' });
  assert.equal(res.status, 400);
});

test('login rejects bad credentials with 401', async () => {
  const c = makeClient();
  const res = await c('POST', '/api/auth/login', { username: 'nobody', password: 'wrongpassword' });
  assert.equal(res.status, 401);
});

test('cross-household IDOR: user B cannot read/edit/delete user A\'s appointment', async () => {
  const a = makeClient();
  const b = makeClient();

  // Two separate registrations => two separate households.
  const ra = await a('POST', '/api/auth/register', { username: 'alice_t', password: 'password123', name: 'Alice' });
  assert.equal(ra.status, 200, 'alice registers');
  const rb = await b('POST', '/api/auth/register', { username: 'bob_t', password: 'password123', name: 'Bob' });
  assert.equal(rb.status, 200, 'bob registers');

  // Alice creates an appointment in her household.
  const created = await a('POST', '/api/appointments', {
    title: 'Alice private event', appointment_date: '2026-07-01', appointment_time: '10:00',
  });
  assert.ok([200, 201].includes(created.status), 'appointment created');

  // Resolve its id from Alice's own list (the create route returns {success}).
  const aListInit = await a('GET', '/api/appointments');
  assert.equal(aListInit.status, 200);
  const mine = (aListInit.body || []).find(x => x.title === 'Alice private event');
  assert.ok(mine && mine.id, 'appointment id resolved from list');
  const apptId = mine.id;

  // Bob (different household) must NOT be able to touch it.
  const bGet = await b('GET', `/api/appointments/${apptId}`);
  assert.ok([403, 404].includes(bGet.status), `bob GET blocked (got ${bGet.status})`);

  const bPut = await b('PUT', `/api/appointments/${apptId}`, { title: 'hijacked' });
  assert.ok([403, 404].includes(bPut.status), `bob PUT blocked (got ${bPut.status})`);

  const bDel = await b('DELETE', `/api/appointments/${apptId}`);
  assert.ok([403, 404].includes(bDel.status), `bob DELETE blocked (got ${bDel.status})`);

  // Alice still sees it in her list (isolation didn't lock her out).
  const aList = await a('GET', '/api/appointments');
  assert.equal(aList.status, 200);
  assert.ok(JSON.stringify(aList.body).includes('Alice private event'), 'alice sees her own event');
});

test('unauthenticated API requests are rejected', async () => {
  const anon = makeClient();
  const res = await anon('GET', '/api/appointments');
  assert.equal(res.status, 401);
});

test('change-password: rejects wrong current password, then rotates and re-logins', async () => {
  const c = makeClient();
  const reg = await c('POST', '/api/auth/register', { username: 'carol_t', password: 'password123', name: 'Carol' });
  assert.equal(reg.status, 200);

  // Wrong current password → 401.
  const bad = await c('POST', '/api/auth/change-password', { current_password: 'nope', new_password: 'newpassword456' });
  assert.equal(bad.status, 401);

  // Too-short new password → 400.
  const short = await c('POST', '/api/auth/change-password', { current_password: 'password123', new_password: 'short' });
  assert.equal(short.status, 400);

  // Correct change → 200.
  const ok = await c('POST', '/api/auth/change-password', { current_password: 'password123', new_password: 'newpassword456' });
  assert.equal(ok.status, 200);

  // Old password no longer works; new one does.
  const oldLogin = await makeClient()('POST', '/api/auth/login', { username: 'carol_t', password: 'password123' });
  assert.equal(oldLogin.status, 401);
  const newLogin = await makeClient()('POST', '/api/auth/login', { username: 'carol_t', password: 'newpassword456' });
  assert.equal(newLogin.status, 200);
});

test('DM to a non-shared user is forbidden', async () => {
  const a = makeClient();
  const b = makeClient();
  await a('POST', '/api/auth/login', { username: 'alice_t', password: 'password123' });
  const rb = await b('POST', '/api/auth/login', { username: 'bob_t', password: 'password123' });
  const bobId = rb.body?.user?.id;
  assert.ok(bobId, 'bob id resolved');
  // Alice and Bob share no group → DM must be blocked.
  const res = await a('POST', '/api/messages', { recipient_id: bobId, text: 'hi' });
  assert.equal(res.status, 403);
});

test('people & milestones: dependents and milestones are household-scoped', async () => {
  const a = makeClient();
  const b = makeClient();
  // Reuse the two existing single-household users (the register limiter is
  // 5/hour/IP and earlier tests already spent most of that budget).
  const ra = await a('POST', '/api/auth/login', { username: 'alice_t', password: 'password123' });
  assert.equal(ra.status, 200, 'alice logs in');
  const rb = await b('POST', '/api/auth/login', { username: 'bob_t', password: 'password123' });
  assert.equal(rb.status, 200, 'bob logs in');

  // Alice's people list auto-includes herself as a linked person row.
  const listA = await a('GET', '/api/people');
  assert.equal(listA.status, 200);
  assert.ok((listA.body || []).some(p => p.name === 'Alice' && p.user_id), 'self auto-linked as a person');

  // Alice adds a dependent (a kid without an account).
  const kid = await a('POST', '/api/people', { name: 'Kiddo', relationship: 'son', is_dependent: true, birthday: '2020-04-01' });
  assert.equal(kid.status, 200, 'dependent created');
  const kidId = kid.body.id;
  assert.ok(kidId, 'dependent id returned');

  // Erin (another household) can't see, edit or delete Dave's dependent.
  const bList = await b('GET', '/api/people');
  assert.ok(!(bList.body || []).some(p => p.id === kidId), 'dependent hidden from other household');
  const bPut = await b('PUT', `/api/people/${kidId}`, { name: 'hijack' });
  assert.ok([403, 404].includes(bPut.status), `PUT person blocked (got ${bPut.status})`);
  const bDel = await b('DELETE', `/api/people/${kidId}`);
  assert.ok([403, 404].includes(bDel.status), `DELETE person blocked (got ${bDel.status})`);

  // Dave logs a milestone for the kid; it shows in his household list.
  const ms = await a('POST', '/api/milestones', { person_id: kidId, title: 'First steps', milestone_date: '2026-07-01', category: 'first' });
  assert.equal(ms.status, 200, 'milestone created');
  const msId = ms.body.id;
  const msList = await a('GET', `/api/milestones?person_id=${kidId}`);
  assert.ok((msList.body || []).some(m => m.id === msId && m.person_name === 'Kiddo'), 'milestone listed with person name');

  // Erin can't read, edit, delete, or create milestones across households.
  const bMs = await b('GET', '/api/milestones');
  assert.ok(!(bMs.body || []).some(m => m.id === msId), 'milestone hidden from other household');
  const bMsPut = await b('PUT', `/api/milestones/${msId}`, { title: 'nope' });
  assert.ok([403, 404].includes(bMsPut.status), `PUT milestone blocked (got ${bMsPut.status})`);
  const bMsDel = await b('DELETE', `/api/milestones/${msId}`);
  assert.ok([403, 404].includes(bMsDel.status), `DELETE milestone blocked (got ${bMsDel.status})`);
  const bMsPost = await b('POST', '/api/milestones', { person_id: kidId, title: 'x', milestone_date: '2026-07-01' });
  assert.equal(bMsPost.status, 403, 'milestone for foreign person blocked');

  // A decision tagged to the kid appears on his card; Erin can't tag him.
  const dec = await a('POST', '/api/decisions', { title: 'Improv class for Kiddo', decision_type: 'text', person_id: kidId });
  assert.ok([200, 201].includes(dec.status), 'tagged decision created');
  const cardDecisions = await a('GET', `/api/people/${kidId}/decisions`);
  assert.equal(cardDecisions.status, 200);
  assert.ok((cardDecisions.body || []).some(d => d.title === 'Improv class for Kiddo'), 'decision shows on person card');
  const bDec = await b('POST', '/api/decisions', { title: 'evil', decision_type: 'text', person_id: kidId });
  assert.equal(bDec.status, 403, 'tagging a foreign person blocked');
});
