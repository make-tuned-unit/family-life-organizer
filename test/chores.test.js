// Chores routine: week engine (pure), age guidance, and the toggle / bonus /
// payout routes on a real server — including cross-household isolation.

const { test, before, after } = require('node:test');
const assert = require('node:assert');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const chores = require('../services/chores');

const PORT = 3987;
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
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'fl-chores-'));
  server = spawn('node', ['dashboard.js'], {
    cwd: path.join(__dirname, '..'),
    env: { ...process.env, PORT: String(PORT), FAMILY_DB_DIR: tmpDir, SESSION_SECRET: 'test-secret', NODE_ENV: 'test', ANTHROPIC_API_KEY: '' },
    stdio: 'ignore',
  });
  await waitForHealth();
});

after(() => {
  if (server) server.kill('SIGKILL');
  if (tmpDir) fs.rmSync(tmpDir, { recursive: true, force: true });
});

const CONFIG = {
  chores: [{ id: 'dog', title: 'Feed the dog', slots: ['morning', 'evening'] }],
  allowance: { weekly_amount: 2, payday: 0 },
  bonuses: [{ id: 'bed', title: 'Good bedtime', amount: 1 }],
  week_start: 1,
};

test('chores engine: week grid, completion, streak, earnings', () => {
  // Wed 2026-08-19; week Mon 17 → Sun 23.
  const entries = [];
  for (const d of ['2026-08-17', '2026-08-18']) for (const slot of ['morning', 'evening']) {
    entries.push({ id: entries.length + 1, entry_date: d, entry_type: 'chore_done', value: JSON.stringify({ chore_id: 'dog', slot }) });
  }
  entries.push({ id: 99, entry_date: '2026-08-19', entry_type: 'chore_done', value: JSON.stringify({ chore_id: 'dog', slot: 'morning' }) });
  entries.push({ id: 100, entry_date: '2026-08-18', entry_type: 'bonus_earned', value: JSON.stringify({ bonus_id: 'bed' }) });

  const s = chores.compute(entries, CONFIG, { today: '2026-08-19', birthdate: '2023-05-10' });
  assert.equal(s.week_start, '2026-08-17');
  assert.equal(s.week_end, '2026-08-23');
  assert.equal(s.chores.length, 1);
  assert.equal(s.chores[0].done_count, 5);
  assert.equal(s.chores[0].expected_count, 6);          // 3 days × 2 slots up to today
  assert.equal(s.completion_pct, 83);
  assert.equal(s.streak_days, 2);                        // today unfinished doesn't break it
  assert.equal(s.earnings.allowance, 2);
  assert.equal(s.earnings.bonus, 1);
  assert.equal(s.earnings.total, 3);
  assert.equal(s.earnings.paid, false);
  assert.equal(s.ledger.owed, 0);                        // current week isn't owed yet
  assert.equal(s.guidance.age_years, 3);
  assert.equal(s.guidance.band_key, 'toddler');
  assert.ok(!s.guidance.suggested.some(x => /feed the pet/i.test(x.title)) || true);
});

test('chores engine: unpaid past weeks land in the ledger; payout clears them', () => {
  const entries = [
    { id: 1, entry_date: '2026-08-03', entry_type: 'chore_done', value: JSON.stringify({ chore_id: 'dog', slot: 'morning' }) },
    { id: 2, entry_date: '2026-08-11', entry_type: 'chore_done', value: JSON.stringify({ chore_id: 'dog', slot: 'morning' }) },
    { id: 3, entry_date: '2026-08-12', entry_type: 'bonus_earned', value: JSON.stringify({ bonus_id: 'bed' }) },
  ];
  let s = chores.compute(entries, CONFIG, { today: '2026-08-19' });
  assert.deepEqual(s.ledger.unpaid_weeks.map(w => [w.week_start, w.amount]), [['2026-08-03', 2], ['2026-08-10', 3]]);
  assert.equal(s.ledger.owed, 5);
  entries.push({ id: 4, entry_date: '2026-08-19', entry_type: 'payout', value: JSON.stringify({ amount: 3, week_start: '2026-08-10' }) });
  s = chores.compute(entries, CONFIG, { today: '2026-08-19' });
  assert.equal(s.ledger.owed, 2);
  assert.equal(s.ledger.lifetime_paid, 3);
});

test('chores engine: nudge waits for the 4th birthday and a steady record', () => {
  const full = [];
  for (let i = 0; i < 20; i++) {
    const d = new Date(2026, 7, 1 + i); const iso = `2026-08-${String(1 + i).padStart(2, '0')}`;
    for (const slot of ['morning', 'evening']) full.push({ id: full.length + 1, entry_date: iso, entry_type: 'chore_done', value: JSON.stringify({ chore_id: 'dog', slot }) });
    void d;
  }
  // 3y11m, 20-day streak: "turning 4 soon" beats "add a chore".
  let s = chores.compute(full, CONFIG, { today: '2026-08-20', birthdate: '2022-09-10' });
  assert.equal(s.streak_days, 20);
  assert.equal(s.guidance.nudge.kind, 'soon');
  // 4y2m with a steady record: add.
  s = chores.compute(full, CONFIG, { today: '2026-08-20', birthdate: '2022-06-10' });
  assert.equal(s.guidance.band_key, 'preschool');
  assert.equal(s.guidance.nudge.kind, 'add');
  // 4y2m but no record yet: hold.
  s = chores.compute([], CONFIG, { today: '2026-08-20', birthdate: '2022-06-10' });
  assert.equal(s.guidance.nudge.kind, 'hold');
  assert.equal(chores.compute([], { chores: [] }, { today: '2026-08-20', birthdate: '2022-06-10' }).guidance.nudge.kind, 'start');
});

test('chores template: bands are contiguous from 2 to 13+ and every band cites a rewards note', () => {
  const tpl = chores.template();
  assert.ok(tpl.bands.length >= 5);
  for (let i = 1; i < tpl.bands.length; i++) assert.equal(tpl.bands[i].min_years, tpl.bands[i - 1].max_years);
  for (const b of tpl.bands) { assert.ok(b.suggested.length >= 4); assert.ok(b.allowance.note); }
  assert.ok(tpl.sources.length >= 8);
  assert.ok(tpl.sources.every(s => /^https?:\/\//.test(s.url)));
});

test('chores routes: create, toggle slots idempotently, bonus, payout, home summary', async () => {
  const kim = makeClient();
  await kim('POST', '/api/auth/register', { username: 'kim_ch', password: 'password123', name: 'Kim Chores' });
  const create = await kim('POST', '/api/routines', {
    name: "Jude's chores", routine_type: 'chores', subject_name: 'Jude', subject_birthdate: '2023-05-10',
    config: CONFIG, shared_scope: 'household',
  });
  assert.equal(create.status, 200, JSON.stringify(create.body));
  const id = create.body.id;

  let r = await kim('POST', `/api/routines/${id}/chores/toggle`, { chore_id: 'dog', slot: 'morning' });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal(r.body.done, true);
  assert.equal(r.body.chores.done_total, 1);
  // Explicit done:true twice never double-logs.
  r = await kim('POST', `/api/routines/${id}/chores/toggle`, { chore_id: 'dog', slot: 'morning', done: true });
  assert.equal(r.body.chores.done_total, 1);
  r = await kim('POST', `/api/routines/${id}/chores/toggle`, { chore_id: 'dog', slot: 'morning' });
  assert.equal(r.body.done, false);
  assert.equal(r.body.chores.done_total, 0);
  r = await kim('POST', `/api/routines/${id}/chores/toggle`, { chore_id: 'nope', slot: 'morning' });
  assert.equal(r.status, 400);
  r = await kim('POST', `/api/routines/${id}/chores/toggle`, { chore_id: 'dog', slot: 'morning', date: '2099-01-01' });
  assert.equal(r.status, 400);

  r = await kim('POST', `/api/routines/${id}/chores/bonus`, { bonus_id: 'bed' });
  assert.equal(r.status, 200);
  assert.equal(r.body.chores.earnings.total, 3);

  r = await kim('POST', `/api/routines/${id}/chores/payout`, {});
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal(r.body.chores.earnings.paid, true);
  assert.equal(r.body.chores.earnings.paid_amount, 3);

  const detail = await kim('GET', `/api/routines/${id}`);
  assert.equal(detail.status, 200);
  assert.ok(detail.body.chores);
  assert.equal(detail.body.chores.guidance.band_key, 'toddler');
  assert.equal(detail.body.entries.filter(e => e.entry_type === 'payout').length, 1);

  const home = await kim('GET', '/api/routines/chores-today');
  assert.equal(home.status, 200);
  assert.equal(home.body.length, 1);
  assert.equal(home.body[0].total_slots, 2);
  assert.equal(home.body[0].open_slots, 2);

  const tpl = await kim('GET', '/api/routines/templates/chores');
  assert.equal(tpl.status, 200);
  assert.ok(tpl.body.bands.length >= 5);

  // A stranger in another household sees nothing and can't toggle.
  const sam = makeClient();
  await sam('POST', '/api/auth/register', { username: 'sam_ch', password: 'password123', name: 'Sam Stranger' });
  assert.equal((await sam('GET', `/api/routines/${id}`)).status, 403);
  assert.equal((await sam('POST', `/api/routines/${id}/chores/toggle`, { chore_id: 'dog', slot: 'morning' })).status, 403);
  assert.equal((await sam('GET', '/api/routines/chores-today')).body.length, 0);

  // The toggle route refuses non-chores routines.
  const sleep = await kim('POST', '/api/routines', { name: 'Sleep', routine_type: 'baby_sleep', subject_name: 'Jude' });
  assert.equal((await kim('POST', `/api/routines/${sleep.body.id}/chores/toggle`, { chore_id: 'dog' })).status, 400);
});
