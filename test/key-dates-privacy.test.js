// Key dates and milestones can be kept to yourself: a reminder about your own
// anniversary shouldn't surface in your partner's feed. Covers the record, the
// feed row, and the celebration side-effects.

const { test, before, after } = require('node:test');
const assert = require('node:assert');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const sqlite3 = require('sqlite3');

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

// Reach past the API to forge the one state it can't produce: a row from before
// created_by existed. The server owns this file; a single short write is safe.
function clearOwner(table, id) {
  return new Promise((resolve, reject) => {
    const db = new sqlite3.Database(path.join(tmpDir, 'family.db'));
    db.run(`UPDATE ${table} SET created_by = NULL WHERE id = ?`, [id], function (err) {
      db.close();
      err ? reject(err) : resolve(this.changes);
    });
  });
}

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

test('milestones: privacy is the author\'s alone to change', async () => {
  const [jesse, invite] = await member('ms_own', 'Owner MS');
  const [sophie] = await member('ms_other', 'Other MS', invite);
  const person = await jesse('POST', '/api/people', { name: 'Guarded MS' });

  const priv = await jesse('POST', '/api/milestones', {
    person_id: person.body.id, title: 'Kept quiet',
    milestone_date: '2026-07-20', shared_scope: 'private',
  });
  const id = priv.body.id;

  // A housemate can't reach it by id — and gets 404, not 403, so the response
  // doesn't confirm the row exists.
  assert.equal((await sophie('PUT', `/api/milestones/${id}`, { shared_scope: 'household' })).status, 404);
  assert.equal((await sophie('DELETE', `/api/milestones/${id}`)).status, 404);
  assert.ok(!(await sophie('GET', '/api/milestones')).body.some(m => m.id === id), 'still hidden');

  // The author can share it, and then it's visible.
  assert.equal((await jesse('PUT', `/api/milestones/${id}`, { shared_scope: 'household' })).status, 200);
  assert.ok((await sophie('GET', '/api/milestones')).body.some(m => m.id === id), 'now shared');

  // A housemate can edit a SHARED milestone's content but cannot re-hide it.
  assert.equal((await sophie('PUT', `/api/milestones/${id}`, { title: 'Edited by Sophie' })).status, 200);
  await sophie('PUT', `/api/milestones/${id}`, { shared_scope: 'private' });
  const stillVisible = (await sophie('GET', '/api/milestones')).body.find(m => m.id === id);
  assert.ok(stillVisible, 'a housemate cannot make someone else\'s milestone private');
  assert.equal(stillVisible.title, 'Edited by Sophie', 'but their content edit stuck');
});

test('key dates: privatising a legacy row adopts it instead of losing it', async () => {
  // Key dates added before this feature existed have created_by = NULL. Making
  // one private without claiming it would hide it from EVERYONE, its author
  // included, with no way back — the guard 404s for all of them.
  const [jesse, invite] = await member('kd_leg', 'Legacy KD');
  const [sophie] = await member('kd_leg2', 'Legacy2 KD', invite);
  const person = await jesse('POST', '/api/people', { name: 'Legacy Person' });

  const created = await jesse('POST', '/api/gifts/events', {
    person_id: person.body.id, title: 'Old anniversary', date: upcoming(6),
    is_recurring: true, event_type: 'anniversary',
  });
  const id = created.body.id;
  // Simulate the pre-migration row. The API deliberately refuses to unset an
  // owner, so this has to go around it.
  assert.equal(await clearOwner('special_events', id), 1, 'owner cleared');

  const priv = await jesse('PUT', `/api/gifts/events/${id}`, { shared_scope: 'private' });
  assert.equal(priv.status, 200);

  const mine = (await jesse('GET', '/api/gifts/events')).body.find(e => e.id === id);
  assert.ok(mine, 'the person who privatised it can still see it');
  assert.ok(!(await sophie('GET', '/api/gifts/events')).body.some(e => e.id === id), 'the housemate cannot');

  // And it can be shared again — i.e. it isn't a one-way trip.
  assert.equal((await jesse('PUT', `/api/gifts/events/${id}`, { shared_scope: 'household' })).status, 200);
  assert.ok((await sophie('GET', '/api/gifts/events')).body.some(e => e.id === id), 'recoverable');
});

test('key dates: a housemate cannot privatise someone else\'s date', async () => {
  const [jesse, invite] = await member('kd_gd', 'Guard KD');
  const [sophie] = await member('kd_gd2', 'Guard2 KD', invite);
  const person = await jesse('POST', '/api/people', { name: 'Guard Person' });

  const created = await jesse('POST', '/api/gifts/events', {
    person_id: person.body.id, title: 'Shared date', date: upcoming(4),
    is_recurring: true, event_type: 'birthday',
  });
  const id = created.body.id;

  // Sophie can edit the content of a shared date...
  assert.equal((await sophie('PUT', `/api/gifts/events/${id}`, { title: 'Renamed' })).status, 200);
  // ...but cannot hide it from its owner.
  await sophie('PUT', `/api/gifts/events/${id}`, { shared_scope: 'private' });
  const stillShared = (await jesse('GET', '/api/gifts/events')).body.find(e => e.id === id);
  assert.ok(stillShared, 'the owner still sees it');
  assert.notEqual(stillShared.shared_scope, 'private', 'scope unchanged by a non-owner');
  assert.equal(stillShared.title, 'Renamed', 'the content edit still applied');

  // Junk scopes are normalised rather than stored verbatim.
  await jesse('PUT', `/api/gifts/events/${id}`, { shared_scope: 'nonsense' });
  const normalised = (await jesse('GET', '/api/gifts/events')).body.find(e => e.id === id);
  assert.equal(normalised.shared_scope, 'household');
});

test('going private retracts the feed post that announced it', async () => {
  const [jesse, invite] = await member('rt_ret', 'Retract RT');
  const [sophie] = await member('rt_ret2', 'Retract2 RT', invite);
  const person = await jesse('POST', '/api/people', { name: 'Retract Person' });

  // A shared milestone posts to the feed…
  const ms = await jesse('POST', '/api/milestones', {
    person_id: person.body.id, title: 'Announced moment', milestone_date: '2026-07-20',
  });
  assert.ok((await sophie('GET', '/api/activity')).body.some(r => (r.title || '').includes('Announced moment')),
    'the household sees the announcement');

  // …and making it private has to take the announcement with it, or the record
  // hides while the post about it stays in everyone's feed.
  assert.equal((await jesse('PUT', `/api/milestones/${ms.body.id}`, { shared_scope: 'private' })).status, 200);
  assert.ok(!(await sophie('GET', '/api/activity')).body.some(r => (r.title || '').includes('Announced moment')),
    'the feed post is retracted');
  assert.ok(!(await sophie('GET', '/api/milestones')).body.some(m => m.id === ms.body.id), 'and the record is hidden');

  // Same for a routine pulled back from shared.
  const routine = await jesse('POST', '/api/routines', { name: 'Retract routine', routine_type: 'baby_sleep' });
  await jesse('PUT', `/api/routines/${routine.body.id}/share`, { shared_scope: 'household' });
  assert.ok((await sophie('GET', '/api/activity')).body.some(r => (r.title || '').includes('Retract routine')));
  await jesse('PUT', `/api/routines/${routine.body.id}/share`, { shared_scope: 'private' });
  assert.ok(!(await sophie('GET', '/api/activity')).body.some(r => (r.title || '').includes('Retract routine')),
    'un-sharing retracts the routine post too');
});

test('a post feed row points at what it is ABOUT, not at itself', async () => {
  // ref_id on a post is the post's own id (reactions and comments need it), so
  // a deep link that used ref_id opened routine #<postId> — a routine that
  // doesn't exist. target_id carries the referenced thing.
  const [jesse] = await member('tgt_rt', 'Target RT');

  // Filler posts so the post id and the routine id can't coincide by accident.
  for (let i = 0; i < 3; i++) {
    await jesse('POST', '/api/feed', { body: `filler ${i}` });
  }

  const routine = await jesse('POST', '/api/routines', {
    name: 'Target routine', routine_type: 'baby_sleep', subject_name: 'Jude',
  });
  const routineId = routine.body.id;
  await jesse('PUT', `/api/routines/${routineId}/share`, { shared_scope: 'household' });

  const row = (await jesse('GET', '/api/activity')).body
    .find(r => r.feed_type === 'post' && r.status === 'routine');
  assert.ok(row, 'the share post is in the feed');
  assert.equal(row.target_id, routineId, 'target_id is the routine');
  assert.notEqual(row.ref_id, routineId, 'and ref_id is NOT (it is the post)');

  // Following the link has to actually load.
  assert.equal((await jesse('GET', `/api/routines/${row.target_id}`)).status, 200);
});

test('a forged reference cannot surface a private routine\'s subject', async () => {
  // The feed renders a routine's subject_name for share posts. reference_id was
  // client-settable, so an unscoped lookup would have let anyone point a post of
  // their own at someone else's private routine and read the subject out of it.
  const [jesse, invite] = await member('leak_a', 'Leak A');
  const [sophie] = await member('leak_b', 'Leak B', invite);

  const secret = await sophie('POST', '/api/routines', {
    name: 'Sophie cycle', routine_type: 'period', subject_name: 'SECRETNAME',
  });
  const secretId = secret.body.id;

  const groups = await jesse('GET', '/api/groups');
  const householdId = (groups.body || []).find(g => g.group_type === 'household').id;
  const forged = await jesse('POST', `/api/groups/${householdId}/feed`, {
    body: 'innocent looking post', post_type: 'routine',
    reference_type: 'routine', reference_id: secretId,
  });
  assert.equal(forged.status, 200, 'the post itself is allowed');

  const feed = (await jesse('GET', '/api/activity')).body;
  assert.ok(!JSON.stringify(feed).includes('SECRETNAME'),
    'the private routine\'s subject never appears in the feed');
  const row = feed.find(r => r.feed_type === 'post' && r.ref_id === forged.body.id);
  assert.ok(row, 'the forged post is there');
  assert.equal(row.detail, null, 'with no detail borrowed from the private routine');
  assert.equal(row.target_id, null, 'and no deep link into it');
});

test('deleting a routine or milestone retracts its feed post', async () => {
  const [jesse, invite] = await member('del_a', 'Delete A');
  const [sophie] = await member('del_b', 'Delete B', invite);
  const person = await jesse('POST', '/api/people', { name: 'Delete Person' });

  // A shared routine, announced, then deleted — the post must go too, or its
  // deep link opens a routine that no longer exists.
  const routine = await jesse('POST', '/api/routines', {
    name: 'Doomed routine', routine_type: 'baby_sleep',
  });
  await jesse('PUT', `/api/routines/${routine.body.id}/share`, { shared_scope: 'household' });
  assert.ok((await sophie('GET', '/api/activity')).body.some(r => (r.title || '').includes('Doomed routine')));
  await jesse('DELETE', `/api/routines/${routine.body.id}`);
  assert.ok(!(await sophie('GET', '/api/activity')).body.some(r => (r.title || '').includes('Doomed routine')),
    'the routine post is gone with the routine');

  const ms = await jesse('POST', '/api/milestones', {
    person_id: person.body.id, title: 'Doomed moment', milestone_date: '2026-07-20',
  });
  assert.ok((await sophie('GET', '/api/activity')).body.some(r => (r.title || '').includes('Doomed moment')));
  await jesse('DELETE', `/api/milestones/${ms.body.id}`);
  assert.ok(!(await sophie('GET', '/api/activity')).body.some(r => (r.title || '').includes('Doomed moment')),
    'the milestone post is gone with the milestone');
});

test('editing a clan-shared milestone keeps the clan share', async () => {
  // The edit sheet's toggle only says private/not-private. Taking "not private"
  // as 'household' downgraded a clan-shared milestone on an unrelated edit.
  const [jesse] = await member('clan_a', 'Clan A');
  const person = await jesse('POST', '/api/people', { name: 'Clan Person' });

  const clan = await jesse('POST', '/api/groups', { name: 'Sharratt Clan Test', group_type: 'family' });
  assert.equal(clan.status, 200, JSON.stringify(clan.body));

  const ms = await jesse('POST', '/api/milestones', {
    person_id: person.body.id, title: 'Clan moment', milestone_date: '2026-07-20',
    shared_group_id: clan.body.id,
  });
  const id = ms.body.id;
  const before = (await jesse('GET', '/api/milestones')).body.find(m => m.id === id);
  assert.equal(before.shared_scope, 'group', 'starts clan-shared');

  // A plain rename, exactly as the edit sheet sends it.
  assert.equal((await jesse('PUT', `/api/milestones/${id}`,
    { title: 'Clan moment!', shared_scope: 'household' })).status, 200);

  const after = (await jesse('GET', '/api/milestones')).body.find(m => m.id === id);
  assert.equal(after.title, 'Clan moment!', 'the rename applied');
  assert.equal(after.shared_scope, 'group', 'and the clan share survived it');
  assert.equal(after.shared_group_id, clan.body.id, 'still pointing at the clan');

  // Going private is still honoured, and coming back out does not resurrect
  // a stale 'household' in place of the clan.
  await jesse('PUT', `/api/milestones/${id}`, { shared_scope: 'private' });
  assert.equal((await jesse('GET', '/api/milestones')).body.find(m => m.id === id).shared_scope, 'private');
});

test('milestone and key-date rows point at the person they belong to', async () => {
  // target_id is "what tapping opens". Milestones and key dates live on a
  // person's card, so both rows carry that person — not the milestone id, which
  // would have no screen to land on.
  const [jesse] = await member('psn_rt', 'Person RT');
  const person = await jesse('POST', '/api/people', { name: 'Deep Person' });
  const personId = person.body.id;

  await jesse('POST', '/api/milestones', {
    person_id: personId, title: 'Pointed moment', milestone_date: '2026-07-20',
  });
  await jesse('POST', '/api/gifts/events', {
    person_id: personId, title: 'Pointed date', date: upcoming(5),
    is_recurring: true, event_type: 'birthday',
  });

  const feed = (await jesse('GET', '/api/activity')).body;
  const msRow = feed.find(r => r.feed_type === 'post' && r.status === 'milestone');
  assert.ok(msRow, 'the milestone post is in the feed');
  assert.equal(msRow.target_id, personId, 'and points at the person, not the milestone');

  const kdRow = feed.find(r => r.feed_type === 'key_date' && r.title === 'Pointed date');
  assert.equal(kdRow.target_id, personId, 'key dates point at their person too');

  // Following it has to load.
  assert.ok((await jesse('GET', '/api/people')).body.some(p => p.id === msRow.target_id));
});

test('feed rows carry a per-type detail', async () => {
  const [jesse] = await member('det_rt', 'Detail RT');
  const person = await jesse('POST', '/api/people', { name: 'Detail Person' });

  const tomorrow = new Date(Date.now() + 86400000).toLocaleDateString('en-CA');
  await jesse('POST', '/api/appointments', {
    title: 'Dentist', appointment_date: tomorrow, appointment_time: '09:30', location: '155 Water St',
  });
  await jesse('POST', '/api/gifts/events', {
    person_id: person.body.id, title: 'Anniversary', date: upcoming(6),
    is_recurring: true, event_type: 'anniversary',
  });

  const feed = (await jesse('GET', '/api/activity')).body;
  const event = feed.find(r => r.feed_type === 'event' && r.title === 'Dentist');
  assert.ok(event, 'the event is in the feed');
  assert.equal(event.detail, `${tomorrow} 09:30`, 'events carry date and time');

  const keyDate = feed.find(r => r.feed_type === 'key_date' && r.title === 'Anniversary');
  assert.ok(keyDate?.detail, 'key dates carry their next occurrence');
  assert.match(keyDate.detail, /^\d{4}-\d{2}-\d{2}$/);
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
