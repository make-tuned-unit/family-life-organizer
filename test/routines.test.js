// Routines feature: household-scoped CRUD, entry logging, cross-household
// isolation, and the guided sleep-training template + age-based guidance.

const { test, before, after } = require('node:test');
const assert = require('node:assert');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const PORT = 3994;
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
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'fl-routines-'));
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

test('routines: create, log entries, list, and delete (household-scoped)', async () => {
  const rio = makeClient();
  await rio('POST', '/api/auth/register', { username: 'rio_rt', password: 'password123', name: 'Rio Routine' });

  // A period tracker.
  const create = await rio('POST', '/api/routines', {
    name: 'My cycle', routine_type: 'period', subject_name: 'Rio',
    config: { avg_cycle_days: 28 },
  });
  assert.equal(create.status, 200, JSON.stringify(create.body));
  const routineId = create.body.id;

  // Log a couple of entries with JSON payloads.
  const e1 = await rio('POST', `/api/routines/${routineId}/entries`, {
    entry_date: '2026-07-01', entry_type: 'period_start', value: { flow: 'medium' },
  });
  assert.equal(e1.status, 200);
  const e2 = await rio('POST', `/api/routines/${routineId}/entries`, {
    entry_date: '2026-07-05', entry_type: 'period_end', notes: 'lighter today',
  });
  assert.equal(e2.status, 200);

  // Detail returns the routine with its entries (newest first).
  const detail = await rio('GET', `/api/routines/${routineId}`);
  assert.equal(detail.status, 200);
  assert.equal(detail.body.routine_type, 'period');
  assert.equal(detail.body.entries.length, 2);
  assert.equal(detail.body.entries[0].entry_date, '2026-07-05');
  assert.equal(detail.body.guidance, null, 'period routines have no sleep guidance');

  // List shows the routine with an entry count.
  const list = await rio('GET', '/api/routines');
  assert.equal(list.status, 200);
  assert.equal(list.body.length, 1);
  assert.equal(list.body[0].entry_count, 2);

  // Delete an entry, then the routine.
  const del = await rio('DELETE', `/api/routines/${routineId}/entries/${e1.body.id}`);
  assert.equal(del.status, 200);
  const after1 = await rio('GET', `/api/routines/${routineId}/entries`);
  assert.equal(after1.body.length, 1);

  const delR = await rio('DELETE', `/api/routines/${routineId}`);
  assert.equal(delR.status, 200);
  const listAfter = await rio('GET', '/api/routines');
  assert.equal(listAfter.body.length, 0);
});

test('routines: sleep-training routine attaches age-based guidance', async () => {
  const sky = makeClient();
  await sky('POST', '/api/auth/register', { username: 'sky_rt', password: 'password123', name: 'Sky Sleep' });

  // A baby born ~6 weeks ago is a newborn — NOT ready for formal training.
  const now = new Date();
  const sixWeeksAgo = new Date(now.getTime() - 42 * 86400000).toLocaleDateString('en-CA');
  const create = await sky('POST', '/api/routines', {
    name: "Baby Wren's sleep", routine_type: 'sleep_training',
    subject_name: 'Wren', subject_birthdate: sixWeeksAgo,
  });
  assert.equal(create.status, 200, JSON.stringify(create.body));

  const detail = await sky('GET', `/api/routines/${create.body.id}`);
  assert.equal(detail.status, 200);
  assert.ok(detail.body.guidance, 'sleep_training routine carries guidance');
  assert.equal(detail.body.guidance.current_phase.key, 'newborn');
  assert.equal(detail.body.guidance.ready_for_training, false);
  assert.ok(detail.body.guidance.safe_sleep.length > 0);
});

test('routines: sleep-training guidance picks the right phase across ages', async () => {
  const pat = makeClient();
  await pat('POST', '/api/auth/register', { username: 'pat_rt', password: 'password123', name: 'Pat Phase' });
  const daysAgo = (d) => new Date(Date.now() - d * 86400000).toLocaleDateString('en-CA');

  // (age in days) -> expected phase key + whether formal training is age-appropriate.
  // Ages sit clear of the band edges so a ±1-day wall-clock/timezone boundary
  // between the test's daysAgo() and the server's own "today" can't flip a phase.
  // The exact ~4-month readiness boundary is pinned deterministically below.
  const cases = [
    [30, 'newborn', false], [105, 'newborn', false], [121, 'foundations', true],
    [200, 'consolidate', true], [400, 'toddler_transition', true],
    [700, 'preschool_routine', true], [1300, 'big_kid', true], [3000, 'big_kid', true],
  ];
  for (const [days, phase, ready] of cases) {
    const c = await pat('POST', '/api/routines', {
      name: 'st', routine_type: 'sleep_training', subject_birthdate: daysAgo(days),
    });
    const d = await pat('GET', `/api/routines/${c.body.id}`);
    const g = d.body.guidance;
    assert.ok(g, `age ${days}d has guidance`);
    assert.equal(g.current_phase.key, phase, `age ${days}d -> phase ${phase}`);
    assert.equal(g.ready_for_training, ready, `age ${days}d -> ready=${ready}`);
    // Contract: guidance phases OMIT min_days/max_days (iOS SleepPhase marks them
    // optional). If the server ever added them here it wouldn't break decode, but
    // this documents the shape the app relies on.
    assert.ok(!('min_days' in g.current_phase), `age ${days}d guidance phase omits min_days`);
    await pat('DELETE', `/api/routines/${c.body.id}`);
  }
});

test('routines: template age bands are contiguous and cover 0..~5yr', async () => {
  const con = makeClient();
  await con('POST', '/api/auth/register', { username: 'con_rt', password: 'password123', name: 'Con Tiguous' });
  const tpl = await con('GET', '/api/routines/templates/sleep-training');
  const phases = [...tpl.body.phases].sort((a, b) => a.min_days - b.min_days);
  assert.equal(phases[0].min_days, 0, 'first band starts at day 0');
  for (let i = 1; i < phases.length; i++) {
    assert.equal(phases[i].min_days, phases[i - 1].max_days + 1,
      `band ${phases[i].key} is contiguous with ${phases[i - 1].key}`);
    assert.ok(phases[i].method && phases[i].method.name, `${phases[i].key} names a method`);
  }
  assert.ok(phases[phases.length - 1].max_days >= 1826, 'coverage extends to ~5 years');
  // Pin the ~4-month readiness boundary deterministically (pure band data, no
  // now-dependency): day 112 is still 'newborn', day 113 opens 'foundations'.
  const bandFor = (day) => phases.find(p => day >= p.min_days && day <= p.max_days)?.key;
  assert.equal(bandFor(112), 'newborn', 'day 112 is the last newborn day');
  assert.equal(bandFor(113), 'foundations', 'day 113 opens the foundations band (~4 months)');
});

test('routines: sleep-training template is served with phases and sources', async () => {
  const t = makeClient();
  await t('POST', '/api/auth/register', { username: 'tem_rt', password: 'password123', name: 'Tem Plate' });
  const tpl = await t('GET', '/api/routines/templates/sleep-training');
  assert.equal(tpl.status, 200);
  assert.equal(tpl.body.phases.length, 6);
  assert.ok(tpl.body.disclaimer.length > 0, 'has a medical disclaimer');
  assert.ok(tpl.body.safe_sleep.length > 0, 'has safe-sleep rules');
  assert.ok(tpl.body.sources.length > 0, 'is sourced');
  // Every phase names a recommended method and has steps.
  for (const p of tpl.body.phases) {
    assert.ok(p.method && p.method.name, `phase ${p.key} has a method`);
    assert.ok(p.steps.length > 0, `phase ${p.key} has steps`);
  }
});

test('routines: another household cannot read or delete your routine', async () => {
  const owner = makeClient();
  await owner('POST', '/api/auth/register', { username: 'own_rt', password: 'password123', name: 'Owner RT' });
  const mine = await owner('POST', '/api/routines', { name: 'Private', routine_type: 'custom' });
  const routineId = mine.body.id;

  const stranger = makeClient();
  await stranger('POST', '/api/auth/register', { username: 'str_rt', password: 'password123', name: 'Stranger RT' });

  const read = await stranger('GET', `/api/routines/${routineId}`);
  assert.equal(read.status, 403, 'stranger is forbidden from reading');
  const del = await stranger('DELETE', `/api/routines/${routineId}`);
  assert.equal(del.status, 403, 'stranger is forbidden from deleting');
  const entry = await stranger('POST', `/api/routines/${routineId}/entries`, { entry_type: 'note', notes: 'x' });
  assert.equal(entry.status, 403, 'stranger cannot log entries');

  // The routine is untouched for the owner.
  const stillThere = await owner('GET', `/api/routines/${routineId}`);
  assert.equal(stillThere.status, 200);
});

// "2026-07-18" + "06:30" -> "2026-07-19 06:30" — the morning after a night that
// started on the given date.
function nextDay(date, time) {
  const d = new Date(`${date}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + 1);
  return `${d.toISOString().slice(0, 10)} ${time}`;
}

// Registers `username` and returns [client, inviteCode]; pass an invite code to
// join an existing household instead of getting a fresh one.
async function member(username, name, inviteCode) {
  const c = makeClient();
  const reg = await c('POST', '/api/auth/register', {
    username, password: 'password123', name, ...(inviteCode ? { invite_code: inviteCode } : {}),
  });
  assert.equal(reg.status, 200, JSON.stringify(reg.body));
  return [c, reg.body.household?.invite_code];
}

test('routines: private by default — a household member cannot see or reach it', async () => {
  const [owner, invite] = await member('priv_rt', 'Private RT');
  const [partner] = await member('prpt_rt', 'Partner Priv RT', invite);

  const created = await owner('POST', '/api/routines', { name: 'My cycle', routine_type: 'period' });
  const routineId = created.body.id;

  // Not opted in → private, even though they share a household.
  const mine = await owner('GET', '/api/routines');
  assert.equal(mine.body.find(r => r.id === routineId)?.shared_scope, 'private',
    'routines are created private');

  const list = await partner('GET', '/api/routines');
  assert.ok(!list.body.some(r => r.id === routineId), 'household member does not see a private routine');
  assert.equal((await partner('GET', `/api/routines/${routineId}`)).status, 403);
  assert.equal((await partner('GET', `/api/routines/${routineId}/entries`)).status, 403);
  assert.equal((await partner('POST', `/api/routines/${routineId}/entries`,
    { entry_type: 'note', notes: 'x' })).status, 403, 'cannot log to a private routine');
  assert.equal((await partner('PUT', `/api/routines/${routineId}`, { name: 'nope' })).status, 403);
  assert.equal((await partner('DELETE', `/api/routines/${routineId}`)).status, 403);

  // The owner still has full access to their own private routine.
  assert.equal((await owner('GET', `/api/routines/${routineId}`)).status, 200);
});

test('routines: sharing opts a routine in, and un-sharing takes it back', async () => {
  const [owner, invite] = await member('shr_rt', 'Sharer RT');
  const [partner] = await member('prt_rt', 'Partner RT', invite);

  const created = await owner('POST', '/api/routines', {
    name: 'Jude bedtime', routine_type: 'baby_sleep', subject_name: 'Jude',
  });
  const routineId = created.body.id;
  assert.equal((await partner('GET', `/api/routines/${routineId}`)).status, 403, 'private first');

  // Toggle on.
  const share = await owner('PUT', `/api/routines/${routineId}/share`, { shared_scope: 'household' });
  assert.equal(share.status, 200);
  assert.equal(share.body.shared_scope, 'household');

  const list = await partner('GET', '/api/routines');
  assert.ok(list.body.some(r => r.id === routineId), 'partner now sees it');
  assert.equal((await partner('GET', `/api/routines/${routineId}`)).status, 200);

  // A shared routine is genuinely collaborative: the partner can log and edit.
  const entry = await partner('POST', `/api/routines/${routineId}/entries`, {
    entry_date: '2026-07-10', entry_type: 'night_sleep', value: { wake_count: 2 },
  });
  assert.equal(entry.status, 200, 'partner can log entries');
  const ownerSees = await owner('GET', `/api/routines/${routineId}/entries`);
  assert.ok(ownerSees.body.some(e => e.id === entry.body.id), 'owner sees the partner entry');
  const rename = await partner('PUT', `/api/routines/${routineId}`, { name: 'Jude bedtime v2' });
  assert.equal(rename.status, 200, 'partner can edit a shared routine');
  assert.equal((await owner('GET', `/api/routines/${routineId}`)).body.name, 'Jude bedtime v2');

  // …but sharing and deleting stay with the creator.
  assert.equal((await partner('PUT', `/api/routines/${routineId}/share`, { shared_scope: 'private' })).status,
    403, 'partner cannot un-share someone else\'s routine');
  assert.equal((await partner('DELETE', `/api/routines/${routineId}`)).status,
    403, 'partner cannot delete someone else\'s routine');

  // Sharing announces itself — the household finds out from the feed.
  // (Feed posts surface as feed_type 'post' with post_type carried in `status`.)
  const feed = await partner('GET', '/api/activity');
  const post = (feed.body || []).find(p => p.feed_type === 'post' && p.status === 'routine');
  assert.ok(post, 'sharing posts to the household feed');
  assert.match(post.title, /Jude bedtime/, 'the post names the routine');

  // Toggle back off — the partner loses access, entries survive for the owner.
  assert.equal((await owner('PUT', `/api/routines/${routineId}/share`, { shared_scope: 'private' })).status, 200);
  assert.equal((await partner('GET', `/api/routines/${routineId}`)).status, 403, 'un-shared again');
  assert.ok(!(await partner('GET', '/api/routines')).body.some(r => r.id === routineId));
  assert.equal((await owner('GET', `/api/routines/${routineId}`)).body.entries.length, 1,
    'the partner-logged entry is still there for the owner');
});

test('routines: shared_scope cannot ride in on a plain update', async () => {
  const [owner, invite] = await member('mass_rt', 'Mass RT');
  const [partner] = await member('mspt_rt', 'Partner Mass RT', invite);
  const created = await owner('POST', '/api/routines', { name: 'Sneaky', routine_type: 'custom' });
  const routineId = created.body.id;

  // The owner's own PUT must not be a back door into the sharing flag either.
  const put = await owner('PUT', `/api/routines/${routineId}`, { shared_scope: 'household' });
  assert.equal(put.status, 200, 'the update itself succeeds');
  assert.equal((await partner('GET', `/api/routines/${routineId}`)).status, 403,
    'but shared_scope is ignored outside /share');
});

test('routines: a sleep entry round-trips its span, duration and wakings', async () => {
  const [parent] = await member('slp_rt', 'Sleep RT');
  const created = await parent('POST', '/api/routines', {
    name: "Wren's sleep", routine_type: 'baby_sleep', subject_name: 'Wren',
  });
  const routineId = created.body.id;

  // A night that crosses midnight: the client resolves the end date and sends
  // precomputed minutes, filed under the evening it started.
  const night = await parent('POST', `/api/routines/${routineId}/entries`, {
    entry_date: '2026-07-20', entry_time: '19:30', entry_type: 'night_sleep',
    value: { sleep_start: '2026-07-20 19:30', sleep_end: '2026-07-21 06:45', duration_minutes: 675, wake_count: 2 },
    notes: 'teething',
  });
  assert.equal(night.status, 200);

  const nap = await parent('POST', `/api/routines/${routineId}/entries`, {
    entry_date: '2026-07-21', entry_time: '13:00', entry_type: 'nap',
    value: { sleep_start: '2026-07-21 13:00', sleep_end: '2026-07-21 14:20', duration_minutes: 80 },
  });
  assert.equal(nap.status, 200);

  const entries = (await parent('GET', `/api/routines/${routineId}/entries`)).body;
  const nightRow = entries.find(e => e.id === night.body.id);
  assert.equal(nightRow.entry_time, '19:30', 'start time is kept');
  assert.equal(nightRow.notes, 'teething');
  const nightValue = JSON.parse(nightRow.value);
  assert.equal(nightValue.sleep_start, '2026-07-20 19:30');
  assert.equal(nightValue.sleep_end, '2026-07-21 06:45', 'overnight end lands on the next day');
  assert.equal(nightValue.duration_minutes, 675);
  assert.equal(nightValue.wake_count, 2);

  const napValue = JSON.parse(entries.find(e => e.id === nap.body.id).value);
  assert.equal(napValue.duration_minutes, 80);
  assert.equal(napValue.wake_count, undefined, 'naps carry no wake count');
});

test('routines: a live sleep starts open and closes with a duration', async () => {
  const [parent] = await member('live_rt', 'Live RT');
  const created = await parent('POST', '/api/routines', {
    name: 'Jude live', routine_type: 'baby_sleep', subject_name: 'Jude',
  });
  const id = created.body.id;

  const start = await parent('POST', `/api/routines/${id}/sleep/start`,
    { kind: 'nap', date: '2026-07-22', time: '13:00' });
  assert.equal(start.status, 200, JSON.stringify(start.body));

  // While it's running it has no duration — stats must not count it yet.
  const openEntry = (await parent('GET', `/api/routines/${id}/entries`)).body[0];
  const openValue = JSON.parse(openEntry.value);
  assert.equal(openValue.in_progress, true);
  assert.equal(openValue.duration_minutes, undefined);
  const midStats = await parent('GET', `/api/routines/${id}/sleep-stats`);
  assert.equal(midStats.body.totals.days_logged, 0, 'an open sleep is not counted');

  // Only one at a time.
  const second = await parent('POST', `/api/routines/${id}/sleep/start`, { kind: 'nap' });
  assert.equal(second.status, 409, 'a second concurrent sleep is refused');

  const end = await parent('PUT', `/api/routines/${id}/sleep/end`, { time: '14:20' });
  assert.equal(end.status, 200);
  assert.equal(end.body.duration_minutes, 80);

  const closed = JSON.parse((await parent('GET', `/api/routines/${id}/entries`)).body[0].value);
  assert.equal(closed.sleep_end, '2026-07-22 14:20');
  assert.equal(closed.in_progress, undefined, 'the in-progress flag is cleared');

  // Ending with nothing running is a 404, not a silent no-op.
  assert.equal((await parent('PUT', `/api/routines/${id}/sleep/end`, {})).status, 404);

  // An overnight live sleep still rolls the end onto the next day.
  await parent('POST', `/api/routines/${id}/sleep/start`,
    { kind: 'night_sleep', date: '2026-07-22', time: '19:30' });
  const night = await parent('PUT', `/api/routines/${id}/sleep/end`, { time: '06:45', wake_count: 2 });
  assert.equal(night.body.duration_minutes, 675);
});

test('routines: the start of a running sleep can be corrected', async () => {
  const [parent] = await member('adj_rt', 'Adjust RT');
  const created = await parent('POST', '/api/routines', {
    name: 'Jude adjust', routine_type: 'baby_sleep', subject_name: 'Jude',
  });
  const id = created.body.id;

  // Tapped "down for the night" at 20:00, but he actually went down at 19:30.
  await parent('POST', `/api/routines/${id}/sleep/start`,
    { kind: 'night_sleep', date: '2026-07-22', time: '20:00' });

  const fixed = await parent('PUT', `/api/routines/${id}/sleep/start`, { time: '19:30' });
  assert.equal(fixed.status, 200, JSON.stringify(fixed.body));

  const entry = (await parent('GET', `/api/routines/${id}/entries`)).body[0];
  const value = JSON.parse(entry.value);
  assert.equal(value.sleep_start, '2026-07-22 19:30', 'the start moved');
  assert.equal(value.in_progress, true, 'and it is still running');
  assert.equal(entry.entry_time, '19:30', 'the entry time moved with it');
  assert.equal(entry.entry_date, '2026-07-22', 'but the day it is filed under did not');

  // The correction has to feed through to the duration, which is the point.
  const ended = await parent('PUT', `/api/routines/${id}/sleep/end`, { time: '06:45' });
  assert.equal(ended.body.duration_minutes, 675, '7:30pm to 6:45am, not 8pm');

  // Correcting with nothing running is a 404, and junk times are refused.
  assert.equal((await parent('PUT', `/api/routines/${id}/sleep/start`, { time: '19:30' })).status, 404);
  await parent('POST', `/api/routines/${id}/sleep/start`, { kind: 'nap', time: '13:00' });
  assert.equal((await parent('PUT', `/api/routines/${id}/sleep/start`, { time: 'bedtime' })).status, 400);
});

test('routines: a finished sleep can have its end time corrected', async () => {
  const [parent] = await member('endfix_rt', 'EndFix RT');
  const created = await parent('POST', '/api/routines', {
    name: 'Jude endfix', routine_type: 'baby_sleep', subject_name: 'Jude',
  });
  const id = created.body.id;

  // Nap started 13:00; "Awake" was tapped at 14:40, twenty minutes late.
  await parent('POST', `/api/routines/${id}/sleep/start`,
    { kind: 'nap', date: '2026-07-22', time: '13:00' });
  const ended = await parent('PUT', `/api/routines/${id}/sleep/end`, { time: '14:40' });
  assert.equal(ended.body.duration_minutes, 100);
  const entryId = ended.body.id;

  // Correct it to when he actually woke.
  const fixed = await parent('PUT', `/api/routines/${id}/entries/${entryId}`, {
    start_time: '13:00', end_time: '14:20', entry_date: '2026-07-22',
  });
  assert.equal(fixed.status, 200, JSON.stringify(fixed.body));

  const entry = (await parent('GET', `/api/routines/${id}/entries`)).body.find(e => e.id === entryId);
  const value = JSON.parse(entry.value);
  assert.equal(value.sleep_end, '2026-07-22 14:20', 'the end moved');
  assert.equal(value.duration_minutes, 80, 'and the duration was recomputed, not left stale');
  assert.equal(entry.entry_date, '2026-07-22', 'still filed under the same day');

  // Stats have to reflect the correction, not the original stamp.
  const stats = await parent('GET', `/api/routines/${id}/sleep-stats?window_days=30`);
  assert.equal(stats.body.totals.longest_stretch_minutes, 80);

  // A night correction that crosses midnight still lands on the next day.
  await parent('POST', `/api/routines/${id}/sleep/start`,
    { kind: 'night_sleep', date: '2026-07-22', time: '19:30' });
  const night = await parent('PUT', `/api/routines/${id}/sleep/end`, { time: '06:00' });
  const nightFix = await parent('PUT', `/api/routines/${id}/entries/${night.body.id}`, {
    start_time: '19:30', end_time: '06:45', entry_date: '2026-07-22', wake_count: 2,
  });
  assert.equal(nightFix.status, 200);
  const nightRow = (await parent('GET', `/api/routines/${id}/entries`)).body.find(e => e.id === night.body.id);
  const nightValue = JSON.parse(nightRow.value);
  assert.equal(nightValue.sleep_end, '2026-07-23 06:45', 'overnight end rolls forward');
  assert.equal(nightValue.duration_minutes, 675);
  assert.equal(nightValue.wake_count, 2);

  // Junk times are refused rather than stored, and an entry from another
  // routine cannot be edited through this one.
  assert.equal((await parent('PUT', `/api/routines/${id}/entries/${entryId}`,
    { start_time: 'lunch', end_time: '2pm' })).status, 400);
  const other = await parent('POST', '/api/routines', { name: 'Other', routine_type: 'baby_sleep' });
  assert.equal((await parent('PUT', `/api/routines/${other.body.id}/entries/${entryId}`,
    { start_time: '13:00', end_time: '13:30' })).status, 404, 'entry belongs to another routine');
});

test('routines: the next-nap window is worked back from the last wake', async () => {
  const [parent] = await member('wake_rt', 'Wake RT');
  // ~10 months old on the test dates → the 3–4 hour wake-window band.
  const created = await parent('POST', '/api/routines', {
    name: 'Jude windows', routine_type: 'baby_sleep', subject_name: 'Jude',
    subject_birthdate: '2025-09-20',
  });
  const id = created.body.id;

  // Nothing logged yet: no wake to measure from, so no guess.
  assert.equal((await parent('GET', `/api/routines/${id}`)).body.next_sleep, null,
    'no finished sleep means no prediction');

  await parent('POST', `/api/routines/${id}/entries`, {
    entry_date: '2026-07-28', entry_type: 'nap', entry_time: '13:00',
    value: { sleep_start: '2026-07-28 13:00', sleep_end: '2026-07-28 14:20', duration_minutes: 80 },
  });

  const next = (await parent('GET', `/api/routines/${id}`)).body.next_sleep;
  assert.ok(next, 'a finished sleep gives us something to work from');
  assert.equal(next.last_wake_at, '2026-07-28 14:20');
  assert.equal(next.wake_window_min_minutes, 180, '3 hours at this age');
  assert.equal(next.due_from, '2026-07-28 17:20', 'wake + 3h');
  assert.equal(next.due_by, '2026-07-28 18:20', 'wake + 4h');
  assert.equal(next.prepare_at, '2026-07-28 17:05', 'nudge lands 15 min before, not after');
  assert.match(next.basis, /rule of thumb/i, 'the basis is stated, not implied');

  // A later wake moves the window with it.
  await parent('POST', `/api/routines/${id}/entries`, {
    entry_date: '2026-07-28', entry_type: 'nap', entry_time: '17:30',
    value: { sleep_start: '2026-07-28 17:30', sleep_end: '2026-07-28 18:10', duration_minutes: 40 },
  });
  const moved = (await parent('GET', `/api/routines/${id}`)).body.next_sleep;
  assert.equal(moved.last_wake_at, '2026-07-28 18:10', 'measured from the most recent wake');
  assert.equal(moved.due_from, '2026-07-28 21:10');

  // A sleep in progress has no end, so it cannot move the window.
  await parent('POST', `/api/routines/${id}/sleep/start`, { kind: 'nap', date: '2026-07-29', time: '09:00' });
  const running = (await parent('GET', `/api/routines/${id}`)).body.next_sleep;
  assert.equal(running.last_wake_at, '2026-07-28 18:10', 'a running sleep is ignored until it ends');
});

test('routines: the age falls back to the child\'s People record', async () => {
  const [parent] = await member('ppl_rt', 'People RT');
  // Jude's birthday lives on his People card, not on the routine.
  const person = await parent('POST', '/api/people', { name: 'Jude', birthday: '2025-09-20' });
  assert.equal(person.status, 200, JSON.stringify(person.body));

  const created = await parent('POST', '/api/routines', {
    name: "Jude's sleep", routine_type: 'baby_sleep', subject_name: 'Jude',
  });
  const id = created.body.id;
  await parent('POST', `/api/routines/${id}/entries`, {
    entry_date: '2026-07-28', entry_type: 'nap', entry_time: '13:00',
    value: { sleep_start: '2026-07-28 13:00', sleep_end: '2026-07-28 14:20', duration_minutes: 80 },
  });

  const detail = (await parent('GET', `/api/routines/${id}`)).body;
  assert.equal(detail.resolved_birthdate, '2025-09-20', 'found via People');
  assert.equal(detail.birthdate_source, 'people', 'and says where it came from');
  assert.ok(detail.next_sleep, 'so the nap window can be worked out');
  assert.equal(detail.next_sleep.wake_window_min_minutes, 180);

  // Stats get the same resolution — the age band should not be blank.
  const stats = await parent('GET', `/api/routines/${id}/sleep-stats`);
  assert.equal(stats.body.guidance.age_label, '4–12 months');
});

test('routines: a birthday key date works, and ambiguous names do not', async () => {
  const [parent] = await member('kdage_rt', 'KeyDate RT');
  // No birthday on the card — only a birthday key date filed against them.
  const person = await parent('POST', '/api/people', { name: 'Wren' });
  await parent('POST', '/api/gifts/events', {
    person_id: person.body.id, title: "Wren's birthday", date: '2025-09-20',
    is_recurring: true, event_type: 'birthday',
  });

  const created = await parent('POST', '/api/routines', {
    name: 'Wren sleep', routine_type: 'baby_sleep', subject_name: 'Wren',
  });
  await parent('POST', `/api/routines/${created.body.id}/entries`, {
    entry_date: '2026-07-28', entry_type: 'nap', entry_time: '13:00',
    value: { sleep_start: '2026-07-28 13:00', sleep_end: '2026-07-28 14:20', duration_minutes: 80 },
  });
  const detail = (await parent('GET', `/api/routines/${created.body.id}`)).body;
  assert.equal(detail.resolved_birthdate, '2025-09-20', 'a birthday key date is enough');

  // Two people called Wren: refuse to guess rather than pick one.
  await parent('POST', '/api/people', { name: 'Wren Cousin', birthday: '2020-01-01' });
  const second = await parent('POST', '/api/people', { name: 'Wren' });
  assert.equal(second.status, 200);
  const ambiguous = (await parent('GET', `/api/routines/${created.body.id}`)).body;
  assert.equal(ambiguous.resolved_birthdate, null, 'two exact matches -> no guess');
  assert.equal(ambiguous.next_sleep, null, 'and therefore no prediction');
});

test('routines: a private birthday key date does not leak through the age lookup', async () => {
  const [jesse, invite] = await member('leakage_a', 'Leak Age A');
  const [sophie] = await member('leakage_b', 'Leak Age B', invite);

  // Sophie records the birthday privately; the person card carries no birthday.
  const person = await jesse('POST', '/api/people', { name: 'Quiet Kid' });
  await sophie('POST', '/api/gifts/events', {
    person_id: person.body.id, title: 'Quiet Kid birthday', date: '2025-09-20',
    is_recurring: true, event_type: 'birthday', shared_scope: 'private',
  });

  // Jesse's routine must not resolve an age through a key date he cannot see.
  const routine = await jesse('POST', '/api/routines', {
    name: 'Quiet sleep', routine_type: 'baby_sleep', subject_name: 'Quiet Kid',
  });
  await jesse('POST', `/api/routines/${routine.body.id}/entries`, {
    entry_date: '2026-07-28', entry_type: 'nap', entry_time: '13:00',
    value: { sleep_start: '2026-07-28 13:00', sleep_end: '2026-07-28 14:20', duration_minutes: 80 },
  });
  const forJesse = (await jesse('GET', `/api/routines/${routine.body.id}`)).body;
  assert.equal(forJesse.resolved_birthdate, null, 'a private key date is not a source for someone else');
  assert.equal(forJesse.next_sleep, null, 'and no age means no prediction');

  // Sophie owns it, so for her it resolves — the date is hers to use.
  await jesse('PUT', `/api/routines/${routine.body.id}/share`, { shared_scope: 'household' });
  const forSophie = (await sophie('GET', `/api/routines/${routine.body.id}`)).body;
  assert.equal(forSophie.resolved_birthdate, '2025-09-20', 'the owner can still use her own key date');
});

test('routines: the bedtime reminder comes from the bedtime actually kept', async () => {
  const [parent] = await member('bed_rt', 'Bedtime RT');
  const created = await parent('POST', '/api/routines', {
    name: 'Jude bedtime prep', routine_type: 'baby_sleep', subject_birthdate: '2025-09-20',
  });
  const id = created.body.id;

  // Two nights is not enough to set a nightly reminder.
  for (const day of ['2026-07-25', '2026-07-26']) {
    await parent('POST', `/api/routines/${id}/entries`, {
      entry_date: day, entry_type: 'night_sleep', entry_time: '19:30',
      value: { sleep_start: `${day} 19:30`, sleep_end: nextDay(day, '06:30'), duration_minutes: 660 },
    });
  }
  assert.equal((await parent('GET', `/api/routines/${id}`)).body.bedtime_prep, null,
    'under three nights it says nothing');

  await parent('POST', `/api/routines/${id}/entries`, {
    entry_date: '2026-07-27', entry_type: 'night_sleep', entry_time: '19:30',
    value: { sleep_start: '2026-07-27 19:30', sleep_end: nextDay('2026-07-27', '06:30'), duration_minutes: 660 },
  });

  const prep = (await parent('GET', `/api/routines/${id}`)).body.bedtime_prep;
  assert.ok(prep, 'three nights is enough');
  assert.equal(prep.bedtime, '7:30pm', 'the bedtime they actually keep');
  assert.equal(prep.start_time, '19:00', 'reminder 30 minutes before it');
  assert.equal(prep.based_on_nights, 3);
  assert.match(prep.basis, /Mindell/, 'the evidence is cited, not implied');
});

test('routines: no birthdate means no next-nap guess', async () => {
  const [parent] = await member('nowin_rt', 'NoWindow RT');
  const created = await parent('POST', '/api/routines', {
    name: 'No birthdate', routine_type: 'baby_sleep',
  });
  await parent('POST', `/api/routines/${created.body.id}/entries`, {
    entry_date: '2026-07-28', entry_type: 'nap', entry_time: '13:00',
    value: { sleep_start: '2026-07-28 13:00', sleep_end: '2026-07-28 14:20', duration_minutes: 80 },
  });
  assert.equal((await parent('GET', `/api/routines/${created.body.id}`)).body.next_sleep, null,
    'without an age there is no wake window to apply');

  // And past the last band (a 5-year-old) there is no nap to predict.
  const older = await parent('POST', '/api/routines', {
    name: 'Older kid', routine_type: 'baby_sleep', subject_birthdate: '2021-01-01',
  });
  await parent('POST', `/api/routines/${older.body.id}/entries`, {
    entry_date: '2026-07-28', entry_type: 'night_sleep', entry_time: '19:30',
    value: { sleep_start: '2026-07-28 19:30', sleep_end: '2026-07-29 06:30', duration_minutes: 660 },
  });
  assert.equal((await parent('GET', `/api/routines/${older.body.id}`)).body.next_sleep, null,
    'past the nap years we extrapolate nothing');
});

test('routines: sleep stats average the window and earn their tips', async () => {
  const [parent] = await member('stat_rt', 'Stat RT');
  // ~10 months old, so the 4–12 month band (12–16h) applies.
  const created = await parent('POST', '/api/routines', {
    name: 'Jude sleep', routine_type: 'baby_sleep', subject_name: 'Jude',
    subject_birthdate: '2025-09-20',
  });
  const id = created.body.id;

  const empty = await parent('GET', `/api/routines/${id}/sleep-stats`);
  assert.equal(empty.status, 200);
  assert.equal(empty.body.tips[0].key, 'no_data', 'no entries earns no advice');

  // Four nights of 11h + a 1h30 nap each day = 12.5h/day, inside the band.
  // Bedtimes deliberately steady at 19:30.
  for (const day of ['2026-07-18', '2026-07-19', '2026-07-20', '2026-07-21']) {
    await parent('POST', `/api/routines/${id}/entries`, {
      entry_date: day, entry_type: 'night_sleep', entry_time: '19:30',
      value: { sleep_start: `${day} 19:30`, sleep_end: nextDay(day, '06:30'), duration_minutes: 660, wake_count: 1 },
    });
    await parent('POST', `/api/routines/${id}/entries`, {
      entry_date: day, entry_type: 'nap', entry_time: '13:00',
      value: { sleep_start: `${day} 13:00`, sleep_end: `${day} 14:30`, duration_minutes: 90 },
    });
  }

  const stats = (await parent('GET', `/api/routines/${id}/sleep-stats`)).body;
  assert.equal(stats.totals.days_logged, 4);
  assert.equal(stats.totals.avg_daily_minutes, 750, '11h night + 1h30 nap');
  assert.equal(stats.totals.avg_naps_per_day, 1);
  assert.equal(stats.totals.avg_wakings, 1);
  assert.equal(stats.totals.longest_stretch_minutes, 660);
  assert.equal(stats.bedtime.average, '7:30pm');
  assert.equal(stats.bedtime.spread_minutes, 0, 'identical bedtimes have no spread');
  assert.equal(stats.guidance.age_label, '4–12 months');
  assert.equal(stats.guidance.recommended_min_minutes, 720);

  const keys = stats.tips.map(t => t.key);
  assert.ok(keys.includes('in_range'), '12.5h/day sits inside 12–16h');
  assert.ok(keys.includes('bedtime_consistent'), 'a steady bedtime is called out');
  assert.ok(!keys.includes('below_range') && !keys.includes('above_range'));
  assert.ok(stats.tips.every(t => t.title && t.detail), 'every tip says something concrete');
});

test('routines: the night average ignores days with no night logged', async () => {
  // A day with only a nap used to contribute a zero-length night, so two 11h
  // nights plus one nap-only day reported the nights as 7h20m.
  const [parent] = await member('avg_rt', 'Average RT');
  const created = await parent('POST', '/api/routines', {
    name: 'Jude averages', routine_type: 'baby_sleep', subject_birthdate: '2025-09-20',
  });
  const id = created.body.id;

  for (const day of ['2026-07-20', '2026-07-21']) {
    await parent('POST', `/api/routines/${id}/entries`, {
      entry_date: day, entry_type: 'night_sleep', entry_time: '19:30',
      value: { sleep_start: `${day} 19:30`, sleep_end: nextDay(day, '06:30'), duration_minutes: 660, wake_count: 1 },
    });
  }
  // A third day where only a nap was logged — no night at all.
  await parent('POST', `/api/routines/${id}/entries`, {
    entry_date: '2026-07-22', entry_type: 'nap', entry_time: '13:00',
    value: { sleep_start: '2026-07-22 13:00', sleep_end: '2026-07-22 14:30', duration_minutes: 90 },
  });

  const t = (await parent('GET', `/api/routines/${id}/sleep-stats?window_days=30`)).body.totals;
  assert.equal(t.avg_night_minutes, 660, 'both nights were 11h, so the night average is 11h');
  assert.equal(t.avg_wakings, 1, 'wakings average over nights, not over every day');
  assert.equal(t.avg_nap_minutes, 90, 'nap length averages over days that had a nap');
  assert.equal(t.days_logged, 3, 'all three days still count as logged');
  assert.equal(t.nights_logged, 2, 'but only two of them had a night');
  // Daily total is deliberately still over every logged day — a day with less
  // sleep is a real observation, not a missing one.
  assert.equal(t.avg_daily_minutes, 470);
});

test('routines: sleep stats flag a short sleeper and a roaming bedtime', async () => {
  const [parent] = await member('shrt_rt', 'Short RT');
  const created = await parent('POST', '/api/routines', {
    name: 'Short sleeper', routine_type: 'baby_sleep', subject_birthdate: '2025-09-20',
  });
  const id = created.body.id;

  // 9h nights, no naps, bedtime swinging between 6:30pm and 10:30pm.
  const bedtimes = ['18:30', '22:30', '19:00', '21:45'];
  const dates = ['2026-07-18', '2026-07-19', '2026-07-20', '2026-07-21'];
  for (let i = 0; i < dates.length; i++) {
    await parent('POST', `/api/routines/${id}/entries`, {
      entry_date: dates[i], entry_type: 'night_sleep', entry_time: bedtimes[i],
      value: { sleep_start: `${dates[i]} ${bedtimes[i]}`, sleep_end: nextDay(dates[i], '05:00'),
               duration_minutes: 540, wake_count: 4 },
    });
  }

  const stats = (await parent('GET', `/api/routines/${id}/sleep-stats`)).body;
  const keys = stats.tips.map(t => t.key);
  assert.ok(keys.includes('below_range'), '9h/day is under the 12–16h band');
  assert.ok(keys.includes('bedtime_variable'), 'a 4-hour bedtime swing is flagged');
  assert.ok(keys.includes('wakings_high'), '4 wakings a night is flagged');
  assert.ok(stats.bedtime.spread_minutes >= 45);
  const belowTip = stats.tips.find(t => t.key === 'below_range');
  assert.match(belowTip.title, /9h/, 'the tip names the observed number');
  assert.ok(belowTip.source, 'the range is attributed');
});

test('routines: a newborn gets no invented sleep-duration range', async () => {
  const [parent] = await member('nb_rt', 'Newborn RT');
  const today = new Date().toLocaleDateString('en-CA');
  const created = await parent('POST', '/api/routines', {
    name: 'Newborn', routine_type: 'baby_sleep', subject_birthdate: today,
  });
  const stats = (await parent('GET', `/api/routines/${created.body.id}/sleep-stats`)).body;
  assert.equal(stats.guidance.age_label, 'Under 4 months');
  assert.equal(stats.guidance.recommended_min_minutes, null, 'no consensus range below 4 months');
  assert.match(stats.guidance.note, /no expert-agreed range/i);
});

test('routines: a household-less caller cannot create a routine', async () => {
  const loner = makeClient();
  await loner('POST', '/api/auth/register', { username: 'lon_rt', password: 'password123', name: 'Loner RT' });
  // Leaving the auto-created household removes group membership.
  const me = await loner('GET', '/api/auth/me');
  const groups = await loner('GET', '/api/groups');
  const household = (groups.body || []).find(g => g.group_type === 'household');
  if (household) await loner('POST', `/api/groups/${household.id}/leave`);

  const create = await loner('POST', '/api/routines', { name: 'orphan', routine_type: 'custom' });
  assert.equal(create.status, 403, 'no household -> 403');
  const list = await loner('GET', '/api/routines');
  assert.equal(list.status, 200);
  assert.deepEqual(list.body, [], 'no household -> empty list, never a leak');
  assert.ok(me.body.user, 'sanity: caller was authenticated');
});

const daysAgo = (d) => new Date(Date.now() - d * 86400000).toLocaleDateString('en-CA');

test('routines: activity — sessions accumulate into achievement milestones', async () => {
  const av = makeClient();
  await av('POST', '/api/auth/register', { username: 'act_rt', password: 'password123', name: 'Ava Activity' });
  const r = await av('POST', '/api/routines', {
    name: "Mia's violin", routine_type: 'activity', subject_name: 'Mia',
    config: { activity_kind: 'Violin', calendar_keyword: 'violin', goal_per_week: 1 },
  });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  const rid = r.body.id;

  // Log five weekly sessions.
  for (let w = 5; w >= 1; w--) {
    const e = await av('POST', `/api/routines/${rid}/entries`, { entry_type: 'session', entry_date: daysAgo(w * 7) });
    assert.equal(e.status, 200);
  }
  const detail = await av('GET', `/api/routines/${rid}`);
  assert.equal(detail.status, 200);
  assert.ok(detail.body.achievements, 'activity routine carries achievements');
  const a = detail.body.achievements;
  assert.equal(a.total_sessions, 5);
  assert.ok(a.earned.some(m => m.count === 5), 'earned the 5-session milestone');
  assert.ok(a.earned.some(m => m.count === 1), 'earned the first-session milestone');
  assert.equal(a.next_milestone.count, 10, 'next milestone is 10');
  assert.equal(a.next_milestone.remaining, 5);
  // A skipped session does not count toward the total.
  await av('POST', `/api/routines/${rid}/entries`, { entry_type: 'session', entry_date: daysAgo(1), value: { status: 'skipped' } });
  const after = await av('GET', `/api/routines/${rid}`);
  assert.equal(after.body.achievements.total_sessions, 5, 'skipped session not counted');
});

test('routines: activity — occurrences link to calendar events and flag confirmations', async () => {
  const cl = makeClient();
  await cl('POST', '/api/auth/register', { username: 'cal_rt', password: 'password123', name: 'Cal Endar' });
  // A weekly "Violin lesson" on the calendar, starting 4 weeks ago.
  const appt = await cl('POST', '/api/appointments', {
    title: 'Violin lesson', appointment_date: daysAgo(28), appointment_time: '16:00', recurrence_rule: 'weekly',
  });
  assert.equal(appt.status, 200, JSON.stringify(appt.body));
  const r = await cl('POST', '/api/routines', {
    name: 'Violin', routine_type: 'activity', config: { calendar_keyword: 'violin' },
  });
  const rid = r.body.id;

  const occ1 = await cl('GET', `/api/routines/${rid}/occurrences`);
  assert.equal(occ1.status, 200);
  assert.equal(occ1.body.keyword, 'violin');
  assert.ok(occ1.body.scheduled >= 4, `weekly recurrence expands to several occurrences (got ${occ1.body.scheduled})`);
  assert.equal(occ1.body.attended, 0, 'nothing confirmed yet');
  assert.ok(occ1.body.pending.length >= 1, 'past unconfirmed occurrences are pending');

  // Confirm attendance on the earliest pending occurrence by logging a session that day.
  const target = occ1.body.pending[0].date;
  await cl('POST', `/api/routines/${rid}/entries`, { entry_type: 'session', entry_date: target });
  const occ2 = await cl('GET', `/api/routines/${rid}/occurrences`);
  assert.equal(occ2.body.attended, 1, 'the confirmed occurrence is now attended');
  assert.ok(occ2.body.occurrences.find(o => o.date === target).confirmed, 'that date is marked confirmed');
});

test('routines: cycle — period routine predicts next period and phase', async () => {
  const cy = makeClient();
  await cy('POST', '/api/auth/register', { username: 'cyc_rt', password: 'password123', name: 'Cy Cle' });
  const r = await cy('POST', '/api/routines', { name: 'My cycle', routine_type: 'period', config: { mode: 'period' } });
  const rid = r.body.id;
  // Four period starts ~28 days apart.
  for (const d of [daysAgo(84), daysAgo(56), daysAgo(28), daysAgo(0)]) {
    await cy('POST', `/api/routines/${rid}/entries`, { entry_type: 'period_start', entry_date: d });
  }
  const detail = await cy('GET', `/api/routines/${rid}`);
  assert.ok(detail.body.cycle, 'period routine carries cycle prediction');
  const c = detail.body.cycle;
  assert.equal(c.mode, 'period');
  assert.equal(c.average_cycle_length, 28, `avg cycle ~28 (got ${c.average_cycle_length})`);
  // Tolerate a ±1 wall-clock boundary between the test's daysAgo() and the
  // server's own "today" — cycle day is 1 (or 2 right at midnight).
  assert.ok(c.current_cycle_day >= 1 && c.current_cycle_day <= 2, `cycle just started (got day ${c.current_cycle_day})`);
  assert.ok(c.next_period_date, 'has a next-period estimate');
  assert.equal(c.current_phase, 'menstrual', 'early cycle -> menstrual');
  assert.ok(!('fertile_window' in c), 'period mode never surfaces a fertile window');
  assert.ok(c.disclaimer.toLowerCase().includes('not a form of birth control'), 'carries the non-contraception disclaimer');
});

test('routines: cycle — TTC mode surfaces a fertile-window RANGE with enough history', async () => {
  const ttc = makeClient();
  await ttc('POST', '/api/auth/register', { username: 'ttc_rt', password: 'password123', name: 'Tara TTC' });
  const r = await ttc('POST', '/api/routines', { name: 'TTC', routine_type: 'period', config: { mode: 'ttc' } });
  const rid = r.body.id;
  // Regular ~28-day cycles (need >=3 cycles = 4 starts), last period 14 days ago.
  for (const d of [daysAgo(98), daysAgo(70), daysAgo(42), daysAgo(14)]) {
    await ttc('POST', `/api/routines/${rid}/entries`, { entry_type: 'period_start', entry_date: d });
  }
  const detail = await ttc('GET', `/api/routines/${rid}`);
  const c = detail.body.cycle;
  assert.equal(c.mode, 'ttc');
  assert.ok(c.fertile_window && c.fertile_window.start && c.fertile_window.end, 'TTC + >=3 cycles -> a fertile window range');
  assert.ok(c.predicted_ovulation_date, 'has a predicted ovulation date');
  // Ovulation is anchored to next period - 14 (luteal), so it sits before next period.
  assert.ok(c.predicted_ovulation_date < c.next_period_date, 'ovulation precedes the next period');
  assert.ok(c.fertile_window.start <= c.predicted_ovulation_date && c.predicted_ovulation_date <= c.fertile_window.end,
    'ovulation falls inside the fertile window');
});

test('routines: cycle — one logged period is insufficient for predictions', async () => {
  const one = makeClient();
  await one('POST', '/api/auth/register', { username: 'one_rt', password: 'password123', name: 'One Cycle' });
  const r = await one('POST', '/api/routines', { name: 'New cycle', routine_type: 'period', config: { mode: 'ttc' } });
  const rid = r.body.id;
  await one('POST', `/api/routines/${rid}/entries`, { entry_type: 'period_start', entry_date: daysAgo(3) });
  const c = (await one('GET', `/api/routines/${rid}`)).body.cycle;
  assert.equal(c.insufficient, true, 'one period -> insufficient');
  // ~3 days ago -> day 4, ±1 for a wall-clock/timezone boundary.
  assert.ok(c.current_cycle_day >= 3 && c.current_cycle_day <= 5, `still shows the current cycle day (got ${c.current_cycle_day})`);
  assert.ok(!c.fertile_window, 'no fertile window from a single period');
});

// ---------------------------------------------------------------------------
// Home-screen sleep bar + the deep analysis behind the concierge's answers.
// ---------------------------------------------------------------------------

test('routines: sleep-now reports awake-since and the next nap for Home', async () => {
  const [parent] = await member('now_rt', 'Now RT');
  const created = await parent('POST', '/api/routines', {
    name: 'Jude sleep', routine_type: 'baby_sleep', subject_name: 'Jude',
    subject_birthdate: '2025-09-20', // ~10 months → the 3–4 hour band
  });
  const id = created.body.id;

  // Nothing logged: the routine is listed, but with nothing to count from.
  const empty = await parent('GET', '/api/routines/sleep-now');
  assert.equal(empty.status, 200);
  assert.equal(empty.body.length, 1, 'the sleep routine is listed');
  assert.equal(empty.body[0].state, 'awake');
  assert.equal(empty.body[0].awake_since, null, 'nothing to count from yet');
  assert.equal(empty.body[0].next_sleep, null);

  await parent('POST', `/api/routines/${id}/entries`, {
    entry_date: '2026-07-28', entry_type: 'nap', entry_time: '13:00',
    value: { sleep_start: '2026-07-28 13:00', sleep_end: '2026-07-28 14:20', duration_minutes: 80 },
  });

  const awake = (await parent('GET', '/api/routines/sleep-now')).body[0];
  assert.equal(awake.state, 'awake');
  assert.equal(awake.awake_since, '2026-07-28 14:20', 'the bar counts from the last wake');
  assert.equal(awake.next_sleep.due_from, '2026-07-28 17:20', 'and names when the next one is due');
  assert.equal(awake.subject_name, 'Jude');

  // With a sleep running the bar flips, and the stale next-nap guess is dropped.
  await parent('POST', `/api/routines/${id}/sleep/start`, { kind: 'nap', date: '2026-07-29', time: '09:10' });
  const asleep = (await parent('GET', '/api/routines/sleep-now')).body[0];
  assert.equal(asleep.state, 'asleep');
  assert.equal(asleep.asleep_since, '2026-07-29 09:10');
  assert.equal(asleep.asleep_kind, 'nap');
  assert.equal(asleep.next_sleep, null, 'no next-nap guess while one is running');
});

test('routines: sleep-now does not leak a housemate\'s private routine', async () => {
  const [owner, invite] = await member('nowp_rt', 'Now Private RT');
  const [partner] = await member('nowq_rt', 'Now Partner RT', invite);
  const created = await owner('POST', '/api/routines', {
    name: 'Private sleep', routine_type: 'baby_sleep', subject_name: 'Quiet',
    subject_birthdate: '2025-09-20',
  });
  assert.equal(created.status, 200);

  assert.equal((await partner('GET', '/api/routines/sleep-now')).body.length, 0,
    'private by default — the housemate sees nothing');
  assert.equal((await owner('GET', '/api/routines/sleep-now')).body.length, 1);

  await owner('PUT', `/api/routines/${created.body.id}/share`, { shared: true });
  assert.equal((await partner('GET', '/api/routines/sleep-now')).body.length, 1,
    'sharing opts the housemate in');
});

test('routines: sleep-stats explains a 4am waking that comes every second night', async () => {
  const [parent] = await member('why_rt', 'Why RT');
  const created = await parent('POST', '/api/routines', {
    name: 'Jude nights', routine_type: 'baby_sleep', subject_name: 'Jude',
    subject_birthdate: '2025-10-02',
  });
  const id = created.body.id;

  const entry = (date, type, startStamp, endStamp, minutes) =>
    parent('POST', `/api/routines/${id}/entries`, {
      entry_date: date, entry_type: type, entry_time: startStamp.slice(11),
      value: { sleep_start: startStamp, sleep_end: endStamp, duration_minutes: minutes },
    });

  const day = (i) => new Date(Date.UTC(2026, 7, 5 + i)).toISOString().slice(0, 10);
  const next = (d) => {
    const x = new Date(`${d}T00:00:00Z`);
    x.setUTCDate(x.getUTCDate() + 1);
    return x.toISOString().slice(0, 10);
  };
  for (let i = 0; i < 14; i++) {
    const d = day(i);
    if (i % 2 === 1) {
      // Broken night: down at 7:40, up at 4:00, back down at 4:25.
      await entry(d, 'night_sleep', `${d} 19:40`, `${next(d)} 04:00`, 500);
      await entry(d, 'night_sleep', `${next(d)} 04:25`, `${next(d)} 06:45`, 140);
      await entry(d, 'nap', `${d} 14:30`, `${d} 16:00`, 90);   // the late nap
    } else {
      await entry(d, 'night_sleep', `${d} 19:15`, `${next(d)} 06:40`, 685);
      await entry(d, 'nap', `${d} 13:45`, `${d} 15:00`, 75);
    }
    await entry(d, 'nap', `${d} 09:15`, `${d} 10:30`, 75);
  }

  const stats = (await parent('GET', `/api/routines/${id}/sleep-stats?window_days=14`)).body;
  assert.ok(stats.wakings, 'the analysis rides along with the stats');
  assert.equal(stats.wakings.cluster.typical_time, '4:00am');
  assert.equal(stats.wakings.cluster.nights_affected, 7);
  assert.equal(stats.wakings.rhythm.pattern, 'alternating');
  assert.equal(stats.wakings.differences[0].key, 'last_nap_end',
    'the late last nap is named as what differs');

  const keys = stats.recommendations.items.map(i => i.key);
  assert.ok(keys.includes('alternating_pattern'));
  assert.ok(keys.includes('early_morning_waking'));
  for (const item of stats.recommendations.items) {
    assert.ok(item.source, 'every recommendation is attributed');
    assert.ok(item.because, 'and states the observation behind it');
  }
  assert.match(stats.recommendations.note, /not medical advice/i);
});
