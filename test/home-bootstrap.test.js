// GET /api/home is the Home cold-load: one payload, household-scoped, no
// inline images. Run: npm test

const { test, before, after } = require('node:test');
const assert = require('node:assert');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('path');

const PORT = 3977;
const BASE = `http://127.0.0.1:${PORT}`;
let server;
let tmpDir;

const HOME_KEYS = [
  'summary', 'groceries', 'tasks', 'appointments_today', 'next_appointment',
  'week_event_count', 'month_event_count', 'feed', 'trips', 'sleep', 'chores',
  'presence', 'groups',
];

function todayLocal() {
  return new Date().toLocaleDateString('en-CA');
}

function fromLocalDate(offsetDays) {
  return new Date(Date.now() + offsetDays * 86400000).toLocaleDateString('en-CA');
}

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

function assertNoInlineImage(obj, label) {
  const raw = JSON.stringify(obj);
  assert.doesNotMatch(raw, /data:image/, `${label} must not contain a data:image URI`);
  assert.doesNotMatch(raw, /profile_image/, `${label} must not include profile_image`);
  assert.doesNotMatch(raw, /partner_image/, `${label} must not include partner_image`);
  assert.doesNotMatch(raw, /image_data/, `${label} must not include image_data`);
}

async function waitForHealth(timeoutMs = 15000) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    try {
      if ((await fetch(BASE + '/healthz')).ok) return;
    } catch {}
    await new Promise((r) => setTimeout(r, 200));
  }
  throw new Error('server did not become healthy');
}

before(async () => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'fl-home-'));
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

test('GET /api/home requires auth', async () => {
  const res = await fetch(BASE + '/api/home');
  assert.equal(res.status, 401);
});

test('GET /api/home shape, no images, feed cap, cheap routes still work', async () => {
  const a = makeClient();
  const ra = await a('POST', '/api/auth/register', {
    username: 'home_shape', password: 'password123', name: 'Home Shape',
  });
  assert.equal(ra.status, 200, JSON.stringify(ra.body));

  const tomorrowFill = fromLocalDate(1);
  for (let i = 0; i < 22; i++) {
    const created = await a('POST', '/api/appointments', {
      title: `Home filler event ${i}`,
      appointment_date: tomorrowFill,
      appointment_time: '10:00',
    });
    assert.ok([200, 201].includes(created.status), JSON.stringify(created.body));
  }

  const home = await a('GET', '/api/home');
  assert.equal(home.status, 200, JSON.stringify(home.body));
  assert.equal(typeof home.body, 'object');
  assert.ok(!Array.isArray(home.body), '/api/home must not be captured as a param sibling');
  for (const key of HOME_KEYS) {
    assert.ok(key in home.body, `missing key ${key}`);
  }
  assert.ok(home.body.summary && typeof home.body.summary === 'object');
  assert.ok(Array.isArray(home.body.groceries));
  assert.ok(Array.isArray(home.body.tasks));
  assert.ok(Array.isArray(home.body.appointments_today));
  assert.ok(Array.isArray(home.body.feed));
  assert.ok(Array.isArray(home.body.trips));
  assert.ok(Array.isArray(home.body.sleep));
  assert.ok(Array.isArray(home.body.chores));
  assert.ok(Array.isArray(home.body.presence));
  assert.ok(Array.isArray(home.body.groups));
  assert.equal(typeof home.body.week_event_count, 'number');
  assert.equal(typeof home.body.month_event_count, 'number');
  assert.ok(home.body.feed.length <= 20, `default feed cap is 20, got ${home.body.feed.length}`);
  assertNoInlineImage(home.body, 'GET /api/home');

  for (const g of home.body.groups) {
    assert.ok(g.has_avatar === 0 || g.has_avatar === 1, 'groups has_avatar is 0/1');
  }

  const uncapped = await a('GET', '/api/home?limit=999');
  assert.equal(uncapped.status, 200);
  assert.ok(uncapped.body.feed.length <= 50, `hard cap is 50, got ${uncapped.body.feed.length}`);
  assert.ok(uncapped.body.feed.length >= 22, 'limit=999 still returns the posts under the cap');

  const chores = await a('GET', '/api/routines/chores-today');
  assert.equal(chores.status, 200);
  assert.ok(Array.isArray(chores.body));
  const sleep = await a('GET', '/api/routines/sleep-now');
  assert.equal(sleep.status, 200);
  assert.ok(Array.isArray(sleep.body));
});

test('GET /api/home does not leak another household\'s feed, events, or tasks', async () => {
  const alice = makeClient();
  const bob = makeClient();
  const ra = await alice('POST', '/api/auth/register', {
    username: 'home_alice', password: 'password123', name: 'Home Alice',
  });
  const rb = await bob('POST', '/api/auth/register', {
    username: 'home_bob', password: 'password123', name: 'Home Bob',
  });
  assert.equal(ra.status, 200, JSON.stringify(ra.body));
  assert.equal(rb.status, 200, JSON.stringify(rb.body));

  const today = todayLocal();
  const tomorrow = fromLocalDate(1);
  const secretEvent = 'ALICE_HH_EVENT_ZX9';
  const secretTask = 'ALICE_HH_TASK_ZX9';
  const secretFeed = 'ALICE_HH_NEXT_ZX9';

  const created = await alice('POST', '/api/appointments', {
    title: secretEvent, appointment_date: today, appointment_time: '10:00',
  });
  assert.ok([200, 201].includes(created.status), JSON.stringify(created.body));
  const upcoming = await alice('POST', '/api/appointments', {
    title: secretFeed, appointment_date: tomorrow, appointment_time: '11:00',
  });
  assert.ok([200, 201].includes(upcoming.status));

  const task = await alice('POST', '/api/add', {
    type: 'task', data: { title: secretTask },
  });
  assert.equal(task.status, 200, JSON.stringify(task.body));

  const aGroups = await alice('GET', '/api/groups');
  const aHh = (aGroups.body || []).find((g) => g.group_type === 'household');
  assert.ok(aHh);

  const bobEvent = await bob('POST', '/api/appointments', {
    title: 'BOB_OWN_EVENT_ZX9', appointment_date: today, appointment_time: '09:00',
  });
  assert.ok([200, 201].includes(bobEvent.status));

  const aliceHome = await alice('GET', '/api/home');
  const bobHome = await bob('GET', '/api/home');
  assert.equal(aliceHome.status, 200);
  assert.equal(bobHome.status, 200);

  const aliceRaw = JSON.stringify(aliceHome.body);
  const bobRaw = JSON.stringify(bobHome.body);
  assert.match(aliceRaw, new RegExp(secretEvent));
  assert.match(aliceRaw, new RegExp(secretTask));
  assert.match(aliceRaw, new RegExp(secretFeed));
  assert.doesNotMatch(bobRaw, new RegExp(secretEvent));
  assert.doesNotMatch(bobRaw, new RegExp(secretTask));
  assert.doesNotMatch(bobRaw, new RegExp(secretFeed));
  assert.match(bobRaw, /BOB_OWN_EVENT_ZX9/);

  const aliceFeedTitles = (aliceHome.body.feed || []).map((r) => r.title);
  const bobFeedTitles = (bobHome.body.feed || []).map((r) => r.title);
  assert.ok(aliceFeedTitles.includes(secretFeed), 'Alice sees her upcoming event in the feed');
  assert.ok(!bobFeedTitles.includes(secretFeed), 'Bob must not see Alice\'s feed event');
  assert.ok(!bobFeedTitles.includes(secretEvent));

  const aliceGroupIds = (aliceHome.body.groups || []).map((g) => g.id);
  const bobGroupIds = (bobHome.body.groups || []).map((g) => g.id);
  assert.ok(aliceGroupIds.includes(aHh.id));
  assert.ok(!bobGroupIds.includes(aHh.id), 'Bob must not see Alice\'s household in groups');

  const aliceToday = (aliceHome.body.appointments_today || []).map((a) => a.title);
  const bobToday = (bobHome.body.appointments_today || []).map((a) => a.title);
  assert.ok(aliceToday.includes(secretEvent));
  assert.ok(!bobToday.includes(secretEvent));
  assert.ok(bobToday.includes('BOB_OWN_EVENT_ZX9'));
});
