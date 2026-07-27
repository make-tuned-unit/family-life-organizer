// Key dates and milestones can be kept to yourself: a reminder about your own
// anniversary shouldn't surface in your partner's feed. Covers the record, the
// feed row, and the celebration side-effects.

const { test, before, after } = require('node:test');
const assert = require('node:assert');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const PORT = 3992;
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
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'fl-keydates-'));
  server = spawn('node', ['dashboard.js'], {
    cwd: path.join(__dirname, '..'),
    env: {
      ...process.env, PORT: String(PORT), FAMILY_DB_DIR: tmpDir,
      SESSION_SECRET: 'test-secret', NODE_ENV: 'test', ANTHROPIC_API_KEY: '',
    },
    stdio: 'ignore',
  });
  await waitForHealth();
});

after(() => {
  if (server) server.kill('SIGKILL');
  if (tmpDir) fs.rmSync(tmpDir, { recursive: true, force: true });
});

async function member(username, name, inviteCode) {
  const c = makeClient();
  const reg = await c('POST', '/api/auth/register', {
    username, password: 'password123', name, ...(inviteCode ? { invite_code: inviteCode } : {}),
  });
  assert.equal(reg.status, 200, JSON.stringify(reg.body));
  return [c, reg.body.household?.invite_code];
}

// A date `days` from now, as YYYY-MM-DD, with the year forced back so the
// recurring-annual path is what gets exercised.
function upcoming(days, year = 2015) {
  const d = new Date(Date.now() + days * 86400000).toLocaleDateString('en-CA');
  return `${year}${d.slice(4)}`;
}

test('key dates: a private one is invisible to the rest of the household', async () => {
  const [jesse, invite] = await member('kd_jesse', 'Jesse KD');
  const [sophie] = await member('kd_sophie', 'Sophie KD', invite);

  const person = await jesse('POST', '/api/people', { name: 'Rowan KD' });
  const personId = person.body.id;

  const priv = await jesse('POST', '/api/gifts/events', {
    person_id: personId, title: 'Our anniversary', date: upcoming(6),
    is_recurring: true, event_type: 'anniversary', shared_scope: 'private',
  });
  assert.equal(priv.status, 200, JSON.stringify(priv.body));

  const shared = await jesse('POST', '/api/gifts/events', {
    person_id: personId, title: 'Rowan birthday', date: upcoming(5),
    is_recurring: true, event_type: 'birthday',
  });
  assert.equal(shared.status, 200);

  // The records themselves.
  const jesseSees = (await jesse('GET', '/api/gifts/events')).body.map(e => e.title);
  const sophieSees = (await sophie('GET', '/api/gifts/events')).body.map(e => e.title);
  assert.ok(jesseSees.includes('Our anniversary'), 'the owner sees their private date');
  assert.ok(jesseSees.includes('Rowan birthday'));
  assert.ok(!sophieSees.includes('Our anniversary'), 'a housemate does not');
  assert.ok(sophieSees.includes('Rowan birthday'), 'shared dates are unaffected');

  // …and the feed rows built from them.
  const jesseFeed = (await jesse('GET', '/api/activity')).body.filter(r => r.feed_type === 'key_date');
  const sophieFeed = (await sophie('GET', '/api/activity')).body.filter(r => r.feed_type === 'key_date');
  assert.ok(jesseFeed.some(r => r.title === 'Our anniversary'), 'upcoming key dates reach the feed');
  assert.ok(jesseFeed.some(r => r.title === 'Our anniversary' && r.is_private === 1),
    'the row is marked private so the owner sees a lock');
  assert.ok(!sophieFeed.some(r => r.title === 'Our anniversary'), 'not in the housemate feed');
  assert.ok(sophieFeed.some(r => r.title === 'Rowan birthday'));
});

test('key dates: only the two-week run-up reaches the feed', async () => {
  const [jesse] = await member('kd_win', 'Window KD');
  const person = await jesse('POST', '/api/people', { name: 'Jude KD' });

  await jesse('POST', '/api/gifts/events', {
    person_id: person.body.id, title: 'Soon date', date: upcoming(3),
    is_recurring: true, event_type: 'birthday',
  });
  await jesse('POST', '/api/gifts/events', {
    person_id: person.body.id, title: 'Far date', date: upcoming(90),
    is_recurring: true, event_type: 'birthday',
  });

  const feed = (await jesse('GET', '/api/activity')).body.filter(r => r.feed_type === 'key_date');
  const titles = feed.map(r => r.title);
  assert.ok(titles.includes('Soon date'), 'a date days away is flagged');
  assert.ok(!titles.includes('Far date'), 'a date months away is not');
});

test('key dates: privacy can be toggled after the fact', async () => {
  const [jesse, invite] = await member('kd_tog', 'Toggle KD');
  const [sophie] = await member('kd_tog2', 'Toggle2 KD', invite);
  const person = await jesse('POST', '/api/people', { name: 'Tog Person' });

  const created = await jesse('POST', '/api/gifts/events', {
    person_id: person.body.id, title: 'Toggling date', date: upcoming(4),
    is_recurring: true, event_type: 'custom',
  });
  const id = created.body.id;
  assert.ok((await sophie('GET', '/api/gifts/events')).body.some(e => e.id === id), 'shared at first');

  await jesse('PUT', `/api/gifts/events/${id}`, { shared_scope: 'private' });
  assert.ok(!(await sophie('GET', '/api/gifts/events')).body.some(e => e.id === id), 'now private');
  assert.ok((await jesse('GET', '/api/gifts/events')).body.some(e => e.id === id), 'still the owner\'s');

  await jesse('PUT', `/api/gifts/events/${id}`, { shared_scope: 'household' });
  assert.ok((await sophie('GET', '/api/gifts/events')).body.some(e => e.id === id), 'shared again');
});

test('milestones: a private one is celebrated nowhere', async () => {
  const [jesse, invite] = await member('ms_jesse', 'Jesse MS');
  const [sophie] = await member('ms_sophie', 'Sophie MS', invite);
  const person = await jesse('POST', '/api/people', { name: 'Jude MS' });

  const priv = await jesse('POST', '/api/milestones', {
    person_id: person.body.id, title: 'A private moment',
    milestone_date: '2026-07-20', shared_scope: 'private',
  });
  assert.equal(priv.status, 200, JSON.stringify(priv.body));

  const shared = await jesse('POST', '/api/milestones', {
    person_id: person.body.id, title: 'First steps', milestone_date: '2026-07-21',
  });
  assert.equal(shared.status, 200);

  const jesseSees = (await jesse('GET', '/api/milestones')).body.map(m => m.title);
  const sophieSees = (await sophie('GET', '/api/milestones')).body.map(m => m.title);
  assert.ok(jesseSees.includes('A private moment'));
  assert.ok(!sophieSees.includes('A private moment'), 'a housemate cannot see it');
  assert.ok(sophieSees.includes('First steps'), 'shared milestones still celebrate');

  // The whole point: no feed post either, for anyone — including the author.
  const feedTitles = (await jesse('GET', '/api/activity')).body.map(r => r.title || '');
  assert.ok(!feedTitles.some(t => t.includes('A private moment')), 'no feed post for a private milestone');
  assert.ok(feedTitles.some(t => t.includes('First steps')), 'a shared one does post');
});
