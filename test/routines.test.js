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
  // The 112/113-day pair pins the ~4-month readiness boundary exactly.
  const cases = [
    [30, 'newborn', false], [112, 'newborn', false], [113, 'foundations', true],
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
  assert.equal(c.current_cycle_day, 1, 'just started -> day 1');
  assert.ok(c.next_period_date, 'has a next-period estimate');
  assert.equal(c.current_phase, 'menstrual', 'day 1 -> menstrual');
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
  assert.equal(c.current_cycle_day, 4, 'still shows the current cycle day');
  assert.ok(!c.fertile_window, 'no fertile window from a single period');
});
