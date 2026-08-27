// Daily Concierge brief on the household feed: opt-in flag, one post per
// household per local day, and the activity-feed shape the iOS Home feed reads.

const { test, before, after } = require('node:test');
const assert = require('node:assert');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const PORT = 3983;
const BASE = `http://127.0.0.1:${PORT}`;
const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'fl-brief-'));
process.env.FAMILY_DB_DIR = tmpDir;

const FamilyDB = require('../database');
const { runDailyBriefSweep, briefTitle, fallbackSummary } = require('../services/conciergeBrief');

let server, db;
const get = (sql, params = []) => new Promise((res, rej) => db.db.get(sql, params, (e, r) => e ? rej(e) : res(r)));

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

let seq = 0;
async function seedHousehold(name, { enabled = false } = {}) {
  seq += 1;
  const username = `${name.replace(/\W/g, '').toLowerCase()}_${seq}_${Date.now()}`;
  const u = await db.createUser({ username, password_hash: 'x', name });
  const g = await db.createGroup({ name: `${name} House`, group_type: 'household', created_by: u.id });
  await db.addGroupMember(g.id, { user_id: u.id, role: 'admin', added_by: u.id });
  if (enabled) await db.setConciergeEnabled(u.id, true);
  return { userId: u.id, groupId: g.id, username };
}

before(async () => {
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
  db = new FamilyDB();
  await new Promise(r => setTimeout(r, 200));
});

after(() => {
  if (server) server.kill('SIGKILL');
  try { db.close(); } catch {}
  fs.rmSync(tmpDir, { recursive: true, force: true });
});

test('briefTitle uses the weekday', () => {
  assert.equal(briefTitle('2026-08-27'), "Thursday's brief");
});

test('fallbackSummary is a readable digest', () => {
  const empty = fallbackSummary({ counts: {} });
  assert.match(empty, /caught up/i);
  const busy = fallbackSummary({
    counts: { overdueTasks: 2, upcomingAppointments: 1, openDecisions: 0, pendingCoverage: 0, budgetAlerts: 1, upcomingEvents: 0, expiringPantry: 0 },
  });
  assert.match(busy, /2 overdue tasks/);
  assert.match(busy, /budget alert/);
});

test('sweep skips households that have not opted into Concierge', async () => {
  const h = await seedHousehold('Off');
  await runDailyBriefSweep(db);
  const posts = await db.getFeedPosts(h.groupId);
  assert.equal(posts.filter(p => p.post_type === 'brief').length, 0);
});

test('sweep posts one brief per opted-in household per day', async () => {
  const h = await seedHousehold('On', { enabled: true });
  const first = await runDailyBriefSweep(db);
  assert.ok(first.posted >= 1, JSON.stringify(first));
  const posts = (await db.getFeedPosts(h.groupId)).filter(p => p.post_type === 'brief');
  assert.equal(posts.length, 1);
  assert.equal(posts[0].author_name, 'Concierge');
  assert.match(posts[0].title, /brief$/i);
  assert.ok(posts[0].body && posts[0].body.length > 0);

  await runDailyBriefSweep(db);
  const again = (await db.getFeedPosts(h.groupId)).filter(p => p.post_type === 'brief');
  assert.equal(again.length, 1, 'second sweep the same day must not duplicate');
});

test('PUT /api/users/me/concierge persists the opt-in and the brief shows on the feed', async () => {
  const client = makeClient();
  const username = `brief_http_${Date.now()}`;
  const reg = await client('POST', '/api/auth/register', {
    username, password: 'password123', name: 'Brief User',
  });
  assert.equal(reg.status, 200, JSON.stringify(reg.body));
  const groupId = reg.body.household.id;

  const before = (await db.getFeedPosts(groupId)).filter(p => p.post_type === 'brief');
  assert.equal(before.length, 0, 'no brief before opt-in');

  const put = await client('PUT', '/api/users/me/concierge', { enabled: true });
  assert.equal(put.status, 200, JSON.stringify(put.body));
  assert.equal(put.body.enabled, true);
  const row = await get('SELECT concierge_enabled FROM users WHERE username = ?', [username]);
  assert.equal(row.concierge_enabled, 1);

  const posted = await runDailyBriefSweep(db);
  assert.ok(posted.posted >= 1, JSON.stringify(posted));

  const feed = await client('GET', '/api/activity?limit=50');
  assert.equal(feed.status, 200);
  const brief = (feed.body || []).find(p => p.feed_type === 'post' && p.status === 'brief');
  assert.ok(brief, 'brief appears on the activity feed');
  assert.equal(brief.author, 'Concierge');
  assert.match(brief.title, /brief$/i);
  assert.ok(brief.body);

  const putOff = await client('PUT', '/api/users/me/concierge', { enabled: false });
  assert.equal(putOff.body.enabled, false);
});
