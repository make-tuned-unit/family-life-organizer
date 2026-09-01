// Coverage visibility end-to-end: requests must reach their recipients by
// user identity, never by display-name string luck. Regression for the
// spouse-to-spouse bug where a nickname contact ("Sarah" vs user "Sarah
// Sharratt") made requests invisible in both directions. Also covers the new
// person (user_ids), household (group_id), and calendar-event attachment paths.

const { test, before, after } = require('node:test');
const assert = require('node:assert');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const PORT = 3981;
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
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'fl-covvis-'));
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

// Shared cast: Jo + Sam share a household; Kit joins later; Zed is a stranger.
let jo, sam, kit, zed;
let joId, samId, kitId, zedId, householdId, inviteCode;

test('setup: household with three members and one stranger', async () => {
  jo = makeClient();
  const regJo = await jo('POST', '/api/auth/register', { username: 'jo_v', password: 'password123', name: 'Jo Vis Sharratt' });
  joId = regJo.body.user.id;
  householdId = regJo.body.household.id;
  inviteCode = regJo.body.household.invite_code;

  sam = makeClient();
  const regSam = await sam('POST', '/api/auth/register', { username: 'sam_v', password: 'password123', name: 'Sam Vis Sharratt', invite_code: inviteCode });
  samId = regSam.body.user.id;

  kit = makeClient();
  const regKit = await kit('POST', '/api/auth/register', { username: 'kit_v', password: 'password123', name: 'Kit Vis', invite_code: inviteCode });
  kitId = regKit.body.user.id;

  zed = makeClient();
  const regZed = await zed('POST', '/api/auth/register', { username: 'zed_v', password: 'password123', name: 'Zed Stranger' });
  zedId = regZed.body.user.id;
  assert.ok(joId && samId && kitId && zedId && householdId);
});

test('nickname contact: request still reaches the spouse (the original bug)', async () => {
  // Jo saved Sam under a first-name-only contact — exactly the shape the iOS
  // roster prefers over the pseudo-id. The old name-equality match went dark.
  await jo('POST', '/api/contacts', { name: 'Sam', relationship: 'partner' });
  const contacts = await jo('GET', '/api/contacts');
  const nick = contacts.body.find(c => c.name === 'Sam');
  assert.ok(nick, 'nickname contact exists');

  const cov = await jo('POST', '/api/coverage', {
    reason: 'School pickup',
    windows: [{ window_date: '2026-09-03', start_time: '15:00', end_time: '17:00' }],
    contact_ids: [nick.id],
  });
  assert.equal(cov.status, 200, JSON.stringify(cov.body));

  const incoming = await sam('GET', '/api/coverage/incoming');
  assert.equal(incoming.status, 200);
  const mine = incoming.body.find(r => r.reason === 'School pickup');
  assert.ok(mine, `Sam sees the nickname-contact request: ${JSON.stringify(incoming.body)}`);

  // And can open + approve it in-app.
  const detail = await sam('GET', `/api/coverage/${mine.id}`);
  assert.equal(detail.status, 200);
  const approve = await sam('POST', `/api/coverage/incoming/${mine.id}/approve`, {
    window_id: detail.body.windows[0].id,
  });
  assert.equal(approve.status, 200, JSON.stringify(approve.body));
});

test('user_ids: person-targeted request is visible both ways', async () => {
  const cov = await sam('POST', '/api/coverage', {
    reason: 'Dog walk',
    windows: [{ window_date: '2026-09-04', start_time: '08:00', end_time: '09:00' }],
    user_ids: [joId],
  });
  assert.equal(cov.status, 200, JSON.stringify(cov.body));
  assert.equal(cov.body.recipients.length, 1);
  assert.equal(cov.body.recipients[0].client_contact_id, -joId);

  // Recipient sees it incoming; requester sees it outgoing. Both at once —
  // the exact symmetry that was broken.
  const joIncoming = await jo('GET', '/api/coverage/incoming');
  assert.ok(joIncoming.body.some(r => r.reason === 'Dog walk'), 'Jo sees incoming');
  const samOutgoing = await sam('GET', '/api/coverage');
  assert.ok(samOutgoing.body.some(r => r.reason === 'Dog walk'), 'Sam sees outgoing');

  // A stranger cannot be targeted by user id.
  const bad = await sam('POST', '/api/coverage', { reason: 'x', windows: [], user_ids: [zedId] });
  assert.equal(bad.status, 403);
});

test('group_id: household-targeted request fans out to every other member', async () => {
  const cov = await jo('POST', '/api/coverage', {
    reason: 'Weekend away',
    windows: [{ window_date: '2026-09-06', start_time: '09:00', end_time: '18:00' }],
    group_id: householdId,
  });
  assert.equal(cov.status, 200, JSON.stringify(cov.body));
  // Sam + Kit, never the requester.
  assert.equal(cov.body.recipients.length, 2);

  for (const [client, label] of [[sam, 'Sam'], [kit, 'Kit']]) {
    const inc = await client('GET', '/api/coverage/incoming');
    assert.ok(inc.body.some(r => r.reason === 'Weekend away'), `${label} sees the household request`);
  }
  const joInc = await jo('GET', '/api/coverage/incoming');
  assert.ok(!joInc.body.some(r => r.reason === 'Weekend away'), 'requester is not their own recipient');

  const zedInc = await zed('GET', '/api/coverage/incoming');
  assert.equal(zedInc.body.length, 0, 'stranger sees nothing');

  // A group you do not belong to is rejected.
  const bad = await zed('POST', '/api/coverage', { reason: 'x', windows: [], group_id: householdId });
  assert.equal(bad.status, 403);
});

test('appointment attachment: event carries into the request, window derived', async () => {
  const appt = await jo('POST', '/api/appointments', {
    title: 'Dentist for the kids',
    appointment_date: '2026-09-10',
    appointment_time: '14:30',
  });
  assert.equal(appt.status, 200, JSON.stringify(appt.body));
  const apptId = appt.body.id;

  // No windows sent — the event's slot becomes the proposed window.
  const cov = await jo('POST', '/api/coverage', {
    reason: 'kids',
    user_ids: [samId],
    appointment_id: apptId,
  });
  assert.equal(cov.status, 200, JSON.stringify(cov.body));

  const inc = await sam('GET', '/api/coverage/incoming');
  const row = inc.body.find(r => r.event_title === 'Dentist for the kids');
  assert.ok(row, `incoming row carries the event title: ${JSON.stringify(inc.body)}`);
  assert.equal(row.appointment_id, apptId);

  const detail = await sam('GET', `/api/coverage/${row.id}`);
  assert.equal(detail.status, 200);
  assert.equal(detail.body.windows.length, 1);
  assert.equal(detail.body.windows[0].window_date, '2026-09-10');
  assert.equal(detail.body.windows[0].start_time, '14:30');

  // An appointment outside the caller's household cannot be attached.
  const zedCov = await zed('POST', '/api/coverage', { reason: 'x', windows: [], appointment_id: apptId });
  assert.ok([403, 404].includes(zedCov.status), `foreign appointment refused: ${zedCov.status}`);
});

test('external event attachment: EventKit id + title round-trip', async () => {
  const cov = await sam('POST', '/api/coverage', {
    reason: 'kids',
    windows: [{ window_date: '2026-09-12', start_time: '10:00', end_time: '12:00' }],
    user_ids: [joId],
    external_event_id: 'EK:ABC-123',
    event_title: 'Football tournament',
  });
  assert.equal(cov.status, 200, JSON.stringify(cov.body));

  const inc = await jo('GET', '/api/coverage/incoming');
  const row = inc.body.find(r => r.event_title === 'Football tournament');
  assert.ok(row, 'external-event request visible with its title');

  const detail = await jo('GET', `/api/coverage/${row.id}`);
  assert.equal(detail.body.external_event_id, 'EK:ABC-123');
});
