// Runtime exercise of the concierge's full-CRUD tool surface against a real
// SQLite DB: tasks edit/delete/move-date, list create/rename/move-item/delete,
// expense logging, poll create/delete, gift status, and DM sending.
// (Tool-selection accuracy is covered by scripts/concierge-tool-eval.js.)

const { test, before, after } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

let tmpDir;
let db;
let tools;
let ctx;
let quinnId;

function run(sql, params = []) {
  return new Promise((resolve, reject) => {
    db.db.run(sql, params, function (err) { err ? reject(err) : resolve(this); });
  });
}
function get(sql, params = []) {
  return new Promise((resolve, reject) => {
    db.db.get(sql, params, (err, row) => err ? reject(err) : resolve(row));
  });
}

before(async () => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'fl-tools-'));
  process.env.FAMILY_DB_DIR = tmpDir;
  const FamilyDB = require('../database.js');
  tools = require('../services/conciergeTools.js');
  db = new FamilyDB();
  await db.initSchema();
  // Migrations queue behind initSchema on the same connection; give them a beat.
  await new Promise(r => setTimeout(r, 400));

  // Seed: two users sharing a household.
  const u1 = await run("INSERT INTO users (username, name, password_hash) VALUES ('pam_t', 'Pam Tool', 'x')");
  const u2 = await run("INSERT INTO users (username, name, password_hash) VALUES ('quinn_t', 'Quinn Tool', 'x')");
  quinnId = u2.lastID;
  const g = await run("INSERT INTO groups (name, group_type, invite_code, created_by) VALUES ('Tools', 'household', 'TOOLTEST1', ?)", [u1.lastID]);
  await run('INSERT INTO group_members (group_id, user_id, role) VALUES (?, ?, ?)', [g.lastID, u1.lastID, 'admin']);
  await run('INSERT INTO group_members (group_id, user_id, role) VALUES (?, ?, ?)', [g.lastID, u2.lastID, 'member']);

  ctx = {
    db,
    userId: u1.lastID,
    userName: 'Pam Tool',
    groupId: g.lastID,
    push: { pushToUser() {} },  // no-op push in tests
    today: '2026-07-11',
  };
});

after(() => {
  try { db.close(); } catch {}
  if (tmpDir) fs.rmSync(tmpDir, { recursive: true, force: true });
});

test('tasks: create, move to another day, delete', async () => {
  const add = await tools.run('tasks', ctx, { action: 'add', title: 'Renew insurance', due_date: '2026-07-15' });
  assert.equal(add.result.ok, true);
  const list = await tools.run('tasks', ctx, { action: 'list' });
  const task = list.result.find(t => t.title === 'Renew insurance');
  assert.ok(task, 'task listed');

  const move = await tools.run('tasks', ctx, { action: 'update', id: task.id, due_date: '2026-07-18', priority: 'high' });
  assert.equal(move.result.ok, true);
  assert.equal((await get('SELECT due_date, priority FROM tasks WHERE id = ?', [task.id])).due_date, '2026-07-18');

  const del = await tools.run('tasks', ctx, { action: 'delete', id: task.id });
  assert.equal(del.result.ok, true);
  assert.equal(await get('SELECT id FROM tasks WHERE id = ?', [task.id]), undefined);

  // Household scoping: bogus id is a polite error, not a write.
  const miss = await tools.run('tasks', ctx, { action: 'delete', id: 99999 });
  assert.equal(miss.result.ok, false);
});

test('lists: create, add, move item across lists, rename, delete', async () => {
  assert.equal((await tools.run('lists', ctx, { action: 'create', name: 'Cottage Packing' })).result.ok, true);
  assert.equal((await tools.run('lists', ctx, { action: 'add', list: 'Cottage Packing', item: 'Batteries' })).result.ok, true);

  const items = await tools.run('lists', ctx, { action: 'get', list: 'Cottage Packing' });
  const batteries = items.result.find(i => i.item.startsWith('Batteries'));
  assert.ok(batteries, 'item on list');

  const move = await tools.run('lists', ctx, { action: 'move_item', id: batteries.id, to_list: 'Costco' });
  assert.equal(move.result.ok, true, JSON.stringify(move.result));
  const costco = await tools.run('lists', ctx, { action: 'get', list: 'Costco' });
  assert.ok(costco.result.some(i => i.item.startsWith('Batteries')), 'item moved to Costco');

  const renamed = await tools.run('lists', ctx, { action: 'rename', list: 'Cottage Packing', new_name: 'Lake House' });
  assert.equal(renamed.result.ok, true);
  const del = await tools.run('lists', ctx, { action: 'delete', list: 'Lake House' });
  assert.equal(del.result.ok, true);

  // update + delete item on the surviving list
  const c2 = await tools.run('lists', ctx, { action: 'get', list: 'Costco' });
  const item = c2.result[0];
  assert.equal((await tools.run('lists', ctx, { action: 'update_item', id: item.id, title: 'AA Batteries' })).result.ok, true);
  assert.equal((await tools.run('lists', ctx, { action: 'delete_item', id: item.id })).result.ok, true);
});

test('budget: log expense with $-string, list, delete', async () => {
  const log = await tools.run('budget', ctx, { action: 'log_expense', amount: 42.5, merchant: 'Costco', category: 'Groceries' });
  assert.equal(log.result.ok, true);
  const list = await tools.run('budget', ctx, { action: 'list_expenses' });
  const receipt = list.result.find(r => r.merchant === 'Costco');
  assert.ok(receipt && Math.abs(receipt.amount - 42.5) < 0.001, 'amount stored numerically');
  assert.equal((await tools.run('budget', ctx, { action: 'delete_expense', id: receipt.id })).result.ok, true);
});

test('decisions: create poll, delete it', async () => {
  const create = await tools.run('decisions', ctx, { action: 'create', title: 'Pizza or tacos?', options: ['Pizza', 'Tacos'] });
  assert.equal(create.result.ok, true);
  const list = await tools.run('decisions', ctx, { action: 'list' });
  const poll = list.result.find(d => d.title === 'Pizza or tacos?');
  assert.ok(poll, 'poll listed');
  assert.equal((await tools.run('decisions', ctx, { action: 'delete', id: poll.id })).result.ok, true);
});

test('gifts: idea lifecycle to purchased', async () => {
  const person = await tools.run('gifts', ctx, { action: 'add_person', name: 'Jude', relationship: 'son' });
  assert.equal(person.result.ok, true, JSON.stringify(person.result));
  const people = await tools.run('gifts', ctx, { action: 'list_people' });
  const jude = people.result.find(p => p.name === 'Jude');
  const idea = await tools.run('gifts', ctx, { action: 'add_idea', person_id: jude.id, title: 'Lego set' });
  assert.equal(idea.result.ok, true, JSON.stringify(idea.result));
  const ideas = await tools.run('gifts', ctx, { action: 'list_ideas', person_id: jude.id });
  const lego = ideas.result.find(i => i.title === 'Lego set');
  const bought = await tools.run('gifts', ctx, { action: 'update_idea', id: lego.id, status: 'purchased' });
  assert.equal(bought.result.ok, true);
  assert.equal((await get('SELECT status FROM gift_ideas WHERE id = ?', [lego.id])).status, 'purchased');
  assert.equal((await tools.run('gifts', ctx, { action: 'delete_idea', id: lego.id })).result.ok, true);
});

test('key dates: a named person is resolved onto their People card', async () => {
  const person = await tools.run('add_person', ctx, { name: 'Rowan', relationship: 'son' });
  assert.equal(person.result.ok, true, JSON.stringify(person.result));

  const added = await tools.run('add_special_event', ctx, {
    title: 'School concert', date: '2026-12-14', person_name: 'rowan', is_recurring: false,
  });
  assert.equal(added.result.ok, true, JSON.stringify(added.result));
  assert.equal(added.action.person_name, 'Rowan');
  assert.equal(added.action.person_id, person.result.id);
  assert.match(added.action.summary, /for Rowan/);

  const row = await get('SELECT person_id FROM special_events WHERE id = ?', [added.result.id]);
  assert.equal(row.person_id, person.result.id, 'the date appears in Rowan\'s People key dates');

  const missing = await tools.run('add_special_event', ctx, {
    title: 'Mystery date', date: '2026-12-15', person_name: 'Not In Household',
  });
  assert.equal(missing.result.ok, false);
  assert.equal(await get("SELECT id FROM special_events WHERE title = 'Mystery date'"), undefined);
});

test('routines: concierge logs a nap and an overnight sleep', async () => {
  const created = await run(
    "INSERT INTO routines (group_id, created_by, name, routine_type, subject_name, shared_scope) VALUES (?, ?, 'Jude sleep', 'baby_sleep', 'Jude', 'private')",
    [ctx.groupId, ctx.userId]);
  const routineId = created.lastID;

  const listed = await tools.run('routines', ctx, { action: 'list' });
  assert.ok(listed.result.some(r => r.id === routineId), 'own routine is listed');

  // A nap inside one day.
  const nap = await tools.run('routines', ctx, {
    action: 'log_sleep', routine_id: routineId, kind: 'nap', start_time: '13:00', end_time: '14:20',
  });
  assert.equal(nap.result.ok, true, JSON.stringify(nap.result));
  assert.equal(nap.result.duration_minutes, 80);

  // A night that crosses midnight — the end must land on the NEXT day.
  const night = await tools.run('routines', ctx, {
    action: 'log_sleep', routine_id: routineId, kind: 'night_sleep',
    start_time: '19:30', end_time: '06:45', date: '2026-07-10', wake_count: 2,
  });
  assert.equal(night.result.duration_minutes, 675, '7:30pm→6:45am is 11h15m');
  const nightRow = await get('SELECT * FROM routine_entries WHERE id = ?', [night.result.id]);
  const value = JSON.parse(nightRow.value);
  assert.equal(value.sleep_start, '2026-07-10 19:30');
  assert.equal(value.sleep_end, '2026-07-11 06:45', 'end rolls to the next day');
  assert.equal(value.wake_count, 2);
  assert.equal(nightRow.entry_date, '2026-07-10', 'filed under the evening it started');

  // Reading it back.
  const read = await tools.run('routines', ctx, { action: 'get', routine_id: routineId });
  assert.equal(read.result.entries.length, 2);
  assert.ok(read.result.entries.some(e => e.duration_minutes === 675));

  // A garbled time is refused rather than stored as a zero-length sleep.
  const bad = await tools.run('routines', ctx, {
    action: 'log_sleep', routine_id: routineId, kind: 'nap', start_time: 'lunchtime', end_time: '2pm',
  });
  assert.ok(bad.result.ok !== true, 'unparseable times are refused');
});

test('routines: concierge runs a live sleep and can correct its start', async () => {
  const created = await run(
    "INSERT INTO routines (group_id, created_by, name, routine_type, shared_scope) VALUES (?, ?, 'Live tool', 'baby_sleep', 'private')",
    [ctx.groupId, ctx.userId]);
  const routineId = created.lastID;
  const liveCtx = { ...ctx, nowTime: '20:00' };

  const started = await tools.run('routines', liveCtx, {
    action: 'start_sleep', routine_id: routineId, kind: 'night_sleep', date: '2026-07-22',
  });
  assert.equal(started.result.ok, true, JSON.stringify(started.result));

  // Only one at a time.
  const again = await tools.run('routines', liveCtx, {
    action: 'start_sleep', routine_id: routineId, kind: 'nap',
  });
  assert.ok(again.result.ok !== true, 'a second concurrent sleep is refused');

  // "He actually went down at 7:30."
  const fixed = await tools.run('routines', liveCtx, {
    action: 'set_start', routine_id: routineId, time: '19:30',
  });
  assert.equal(fixed.result.ok, true, JSON.stringify(fixed.result));

  const ended = await tools.run('routines', { ...ctx, nowTime: '06:45' }, {
    action: 'end_sleep', routine_id: routineId, wake_count: 1,
  });
  assert.equal(ended.result.duration_minutes, 675, 'the correction fed through to the duration');

  const row = await get('SELECT * FROM routine_entries WHERE id = ?', [ended.result.id]);
  const value = JSON.parse(row.value);
  assert.equal(value.sleep_start, '2026-07-22 19:30');
  assert.equal(value.sleep_end, '2026-07-23 06:45', 'overnight end lands the next day');
  assert.equal(value.in_progress, undefined, 'no longer running');
});

test('routines: the concierge cannot read a housemate\'s private routine', async () => {
  // Quinn shares Pam's household but the routine is Quinn's and unshared.
  const priv = await run(
    "INSERT INTO routines (group_id, created_by, name, routine_type, shared_scope) VALUES (?, ?, 'Quinn cycle', 'period', 'private')",
    [ctx.groupId, quinnId]);
  const id = priv.lastID;

  assert.ok(!(await tools.run('routines', ctx, { action: 'list' })).result.some(r => r.id === id),
    'a housemate\'s private routine is not listed');
  const read = await tools.run('routines', ctx, { action: 'get', routine_id: id });
  assert.ok(read.result.ok !== true && !read.result.entries, 'reading it is refused');
  const write = await tools.run('routines', ctx, {
    action: 'log_entry', routine_id: id, entry_type: 'period_start',
  });
  assert.ok(write.result.ok !== true, 'logging to it is refused');
  assert.equal((await get('SELECT COUNT(*) AS n FROM routine_entries WHERE routine_id = ?', [id])).n, 0);

  // Once Quinn shares it, the household can log to it.
  await run("UPDATE routines SET shared_scope = 'household' WHERE id = ?", [id]);
  const shared = await tools.run('routines', ctx, {
    action: 'log_entry', routine_id: id, entry_type: 'period_start',
  });
  assert.equal(shared.result.ok, true, JSON.stringify(shared.result));
});

test('concierge: private key dates and milestones stay private', async () => {
  const person = await run("INSERT INTO gift_people (name, group_id) VALUES ('Kid Tool', ?)", [ctx.groupId]);
  const personId = person.lastID;

  // "Add our anniversary, privately."
  const kd = await tools.run('special_events', ctx, {
    action: 'add', title: 'Our anniversary', date: '2026-08-02',
    event_type: 'anniversary', private: true,
  });
  assert.equal(kd.result.ok, true, JSON.stringify(kd.result));
  const kdRow = await get("SELECT shared_scope, created_by FROM special_events WHERE title = 'Our anniversary'");
  assert.equal(kdRow.shared_scope, 'private');
  assert.equal(kdRow.created_by, ctx.userId, 'owned, or it would be unreachable to everyone');

  // A housemate must not see it.
  const otherCtx = { ...ctx, userId: quinnId, userName: 'Quinn Tool' };
  const theirs = await tools.run('special_events', otherCtx, { action: 'list' });
  assert.ok(!theirs.result.some(e => e.title === 'Our anniversary'), 'invisible to the housemate');
  assert.ok((await tools.run('special_events', ctx, { action: 'list' }))
    .result.some(e => e.title === 'Our anniversary'), 'but visible to its author');

  // A private milestone is celebrated nowhere.
  const before = (await get('SELECT COUNT(*) AS n FROM feed_posts')).n;
  const ms = await tools.run('people', ctx, {
    action: 'log_milestone', person_id: personId, title: 'A quiet moment',
    milestone_date: '2026-07-20', private: true,
  });
  assert.equal(ms.result.ok, true, JSON.stringify(ms.result));
  assert.equal((await get('SELECT COUNT(*) AS n FROM feed_posts')).n, before,
    'no feed post for a private milestone');
  assert.match(ms.result.summary, /private/i, 'the confirmation says so');

  // …while a normal one still is.
  await tools.run('people', ctx, {
    action: 'log_milestone', person_id: personId, title: 'A loud moment', milestone_date: '2026-07-21',
  });
  assert.equal((await get('SELECT COUNT(*) AS n FROM feed_posts')).n, before + 1,
    'a shared milestone still posts');
});

test('cross-household: tools refuse to touch another household\'s rows', async () => {
  // Second household with its own task, receipt, and decision.
  const u3 = await run("INSERT INTO users (username, name, password_hash) VALUES ('rex_t', 'Rex Other', 'x')");
  const g2 = await run("INSERT INTO groups (name, group_type, invite_code, created_by) VALUES ('Others', 'household', 'OTHERHH01', ?)", [u3.lastID]);
  await run('INSERT INTO group_members (group_id, user_id, role) VALUES (?, ?, ?)', [g2.lastID, u3.lastID, 'admin']);
  const otherCtx = { db, userId: u3.lastID, userName: 'Rex Other', groupId: g2.lastID, push: { pushToUser() {} }, today: '2026-07-11' };

  // Rex creates a real task + decision in his household.
  await tools.run('tasks', otherCtx, { action: 'add', title: 'Rex private task' });
  const rexTaskId = (await get("SELECT id FROM tasks WHERE title = 'Rex private task'")).id;
  await tools.run('decisions', otherCtx, { action: 'create', title: 'Rex private poll', options: ['A', 'B'] });
  const rexDecId = (await get("SELECT id FROM decisions WHERE title = 'Rex private poll'")).id;

  // Pam (ctx = first household) must NOT be able to update/delete them.
  // Refusal surfaces either as {ok:false} (guard returns) or {error} (guard
  // throws through run()); both mean "not done".
  const refused = (r) => r.result.ok !== true;
  assert.ok(refused(await tools.run('tasks', ctx, { action: 'update', id: rexTaskId, title: 'HACKED' })), 'cross-household task update refused');
  assert.ok(refused(await tools.run('tasks', ctx, { action: 'delete', id: rexTaskId })), 'cross-household task delete refused');
  assert.ok(refused(await tools.run('decisions', ctx, { action: 'delete', id: rexDecId })), 'cross-household decision delete refused');

  // The rows are untouched.
  assert.equal((await get('SELECT title FROM tasks WHERE id = ?', [rexTaskId])).title, 'Rex private task');
  assert.ok(await get('SELECT id FROM decisions WHERE id = ?', [rexDecId]), 'decision still exists');
});

test('send_message: resolves by first name, refuses strangers', async () => {
  const sent = await tools.run('send_message', ctx, { to: 'Quinn', text: 'Home late tonight' });
  assert.equal(sent.result.ok, true, JSON.stringify(sent.result));
  const row = await get('SELECT sender_id, recipient_id, text FROM direct_messages ORDER BY id DESC LIMIT 1');
  assert.equal(row.recipient_id, quinnId);
  assert.equal(row.text, 'Home late tonight');

  const stranger = await tools.run('send_message', ctx, { to: 'Zorp', text: 'hi' });
  assert.equal(stranger.result.ok, false);
});

test('routines: the concierge analyses a 4am waking rather than just counting it', async () => {
  const created = await run(
    "INSERT INTO routines (group_id, created_by, name, routine_type, subject_name, subject_birthdate, shared_scope) VALUES (?, ?, 'Jude nights', 'baby_sleep', 'Jude', '2025-10-02', 'private')",
    [ctx.groupId, ctx.userId]);
  const routineId = created.lastID;

  // A fortnight where every second night breaks at 4am, and on those days the
  // last nap runs an hour late — logged the way the app logs it.
  // Fourteen nights ending the day before ctx.today (2026-07-11).
  const day = (i) => new Date(Date.UTC(2026, 5, 27 + i)).toISOString().slice(0, 10);
  for (let i = 0; i < 14; i++) {
    const d = day(i);
    if (i % 2 === 1) {
      await tools.run('routines', ctx, { action: 'log_sleep', routine_id: routineId,
        kind: 'night_sleep', date: d, start_time: '19:40', end_time: '04:00' });
      await tools.run('routines', ctx, { action: 'log_sleep', routine_id: routineId,
        kind: 'night_sleep', date: d, start_time: '04:25', end_time: '06:45' });
      await tools.run('routines', ctx, { action: 'log_sleep', routine_id: routineId,
        kind: 'nap', date: d, start_time: '14:30', end_time: '16:00' });
    } else {
      await tools.run('routines', ctx, { action: 'log_sleep', routine_id: routineId,
        kind: 'night_sleep', date: d, start_time: '19:15', end_time: '06:40' });
      await tools.run('routines', ctx, { action: 'log_sleep', routine_id: routineId,
        kind: 'nap', date: d, start_time: '13:45', end_time: '15:00' });
    }
    await tools.run('routines', ctx, { action: 'log_sleep', routine_id: routineId,
      kind: 'nap', date: d, start_time: '09:15', end_time: '10:30' });
  }

  const out = await tools.run('routines', ctx, { action: 'analyze', routine_id: routineId });
  const r = out.result;
  assert.equal(r.subject, 'Jude');
  assert.equal(r.wakings.cluster.typical_time, '4:00am', 'the clock time, not just a count');
  assert.equal(r.wakings.rhythm.pattern, 'alternating');
  assert.equal(r.wakings.differences[0].key, 'last_nap_end');
  assert.ok(r.recommendations.items.length, 'something concrete to try');
  // The research travels with the data so the model can only cite what we ship.
  assert.ok(r.sources.length >= 5, 'the source list rides along');
  assert.ok(r.current_phase.method.name, 'the age-appropriate method is named');
  assert.match(r.answer_guidance, /not medical advice/i);
});

test('routines: analyse is refused on a housemate\'s private sleep log', async () => {
  // Quinn's own baby-sleep routine, unshared: a sleep analysis is exactly the
  // kind of personal detail the private scope exists to protect.
  const created = await run(
    "INSERT INTO routines (group_id, created_by, name, routine_type, shared_scope) VALUES (?, ?, 'Quinn baby', 'baby_sleep', 'private')",
    [ctx.groupId, quinnId]);
  const out = await tools.run('routines', ctx, { action: 'analyze', routine_id: created.lastID });
  assert.ok(out.result.ok !== true && !out.result.wakings, 'analysing it is refused');
});
