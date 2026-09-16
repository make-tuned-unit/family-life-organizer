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

test('budget: renaming a category keeps existing expenses and updates the allowance', async () => {
  const category = await db.addBudgetCategory('Gas/Transport', 200, '#4facfe', ctx.groupId);
  const receipt = await db.addReceipt({
    group_id: ctx.groupId,
    merchant: 'Fuel station',
    date: '2026-07-11',
    amount: 64.25,
    category: 'Gas/Transport',
  });

  await db.updateBudgetCategory(category.id, { name: 'Car', monthly_limit: 300 });

  const stored = await get('SELECT category FROM receipts WHERE id = ?', [receipt.id]);
  assert.equal(stored.category, 'Car', 'the existing expense follows the category rename');

  const summary = await db.getBudgetSummary('2026-07', ctx.groupId);
  const car = summary.find(row => row.category === 'Car');
  assert.ok(car, 'renamed category remains in the budget');
  assert.equal(car.monthly_limit, 300);
  assert.equal(car.spent, 64.25);
  assert.equal(summary.some(row => row.category === 'Gas/Transport'), false);
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

  // No person_name, but the title leads with a household person's name →
  // attach it so it shows up on their People card, not just in the feed.
  const inferred = await tools.run('special_events', ctx, {
    action: 'add', title: 'Rowan violin anniversary', date: '2026-09-01',
  });
  assert.equal(inferred.result.ok, true, JSON.stringify(inferred.result));
  assert.equal(inferred.action.person_id, person.result.id, 'inferred from the title');
  assert.match(inferred.action.summary, /for Rowan/);

  // A genuinely household-wide date stays unattached.
  const shared = await tools.run('special_events', ctx, {
    action: 'add', title: 'Dating anniversary', date: '2026-08-28',
  });
  assert.equal(shared.result.ok, true);
  assert.equal((await get('SELECT person_id FROM special_events WHERE id = ?', [shared.result.id])).person_id, null);

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

test('calendar: Rowan weekly violin persists time, attendee, address and future occurrences', async () => {
  const input = { action: 'add', title: 'Violin', appointment_date: '2026-09-12', appointment_time: '09:20',
    with_person: 'Rowan', person_tags: 'Rowan', location: 'Example Music School, 123 Test Street, Halifax',
    recurrence_rule: 'weekly', recurrence_end: '2026-10-03' };
  const saved = await tools.run('calendar', { ...ctx, push: null }, input);
  assert.equal(saved.result.ok, true, JSON.stringify(saved));
  const row = await get('SELECT * FROM appointments WHERE id = ?', [saved.result.id]);
  for (const key of ['appointment_time', 'with_person', 'person_tags', 'location', 'recurrence_rule', 'recurrence_end']) assert.equal(row[key], input[key]);
  const upcoming = await tools.run('calendar', ctx, { action: 'list', date_from: '2026-09-19', date_to: '2026-10-10' });
  assert.deepEqual(upcoming.result.filter(e => e.id === row.id).map(e => e.date), ['2026-09-19', '2026-09-26', '2026-10-03']);
  const update = await tools.run('calendar', ctx, { action: 'update', id: row.id, appointment_time: '10:20', recurrence_rule: 'biweekly' });
  assert.equal(update.result.ok, true);
  const unchanged = await get('SELECT * FROM appointments WHERE id = ?', [row.id]);
  assert.equal(unchanged.location, input.location);
  assert.equal(unchanged.recurrence_rule, 'biweekly');
  assert.equal((await tools.run('calendar', ctx, { action: 'update', id: row.id, recurrence_rule: null })).result.ok, true);
  const single = await get('SELECT * FROM appointments WHERE id = ?', [row.id]);
  assert.equal(single.recurrence_rule, null);
  assert.equal(single.recurrence_end, null);
  assert.equal((await tools.run('calendar', ctx, { action: 'delete', id: row.id })).result.ok, true);
});

test('calendar: invalid times, dates, frequencies and unknown fields never write', async () => {
  const before = await get('SELECT COUNT(*) AS count FROM appointments');
  for (const patch of [
    { appointment_time: '25:20' }, { appointment_time: '9:20 AM' }, { appointment_date: '2026-02-30' },
    { recurrence_rule: 'fortnightly' }, { recurrence_rule: 'weekly', recurrence_end: '2026-09-01' },
    { recurrence_end: '2026-10-01' }, { address: 'silently dropped field' }, { recurring: true },
  ]) {
    const result = await tools.run('calendar', ctx, { action: 'add', title: 'Invalid', appointment_date: '2026-09-12', ...patch });
    assert.equal(result.result.ok, false, JSON.stringify(patch));
    assert.ok(result.result.error);
  }
  assert.deepEqual(await get('SELECT COUNT(*) AS count FROM appointments'), before);
});

test('routines: archive and restore preserve entries and respect creator ownership', async () => {
  const r = await db.createRoutine({ group_id: ctx.groupId, created_by: ctx.userId, name: 'Retired naps', routine_type: 'baby_sleep', shared_scope: 'household' });
  await db.addRoutineEntry(r.id, { entry_date: '2026-09-01', entry_type: 'nap', value: { duration_minutes: 90 } });
  const original = await db.getRoutineEntries(r.id);
  const housemate = { ...ctx, userId: quinnId };
  assert.equal((await tools.run('routines', housemate, { action: 'archive', routine_id: r.id })).result.ok, false);
  for (const operation of ['archive', 'archive', 'restore', 'restore']) {
    assert.equal((await tools.run('routines', ctx, { action: operation, routine_id: r.id })).result.ok, true);
    assert.deepEqual(await db.getRoutineEntries(r.id), original);
    const active = await tools.run('routines', ctx, { action: 'list' });
    const archived = await tools.run('routines', ctx, { action: 'list', status: 'archived' });
    assert.equal(active.result.some(v => v.id === r.id), operation === 'restore');
    assert.equal(archived.result.some(v => v.id === r.id), operation === 'archive');
  }
});

test('venue lookup uses household saved address and excludes other households', async () => {
  await db.addFamilyAddress({ name: 'Example Music School', address: '123 Test Street, Halifax', lat: 44.6, lng: -63.5, group_id: ctx.groupId });
  const found = await tools.run('calendar', ctx, { action: 'lookup_place', query: 'Example Music School Halifax' });
  assert.equal(found.result.matches[0].address, '123 Test Street, Halifax');
  const noHousehold = await tools.run('calendar', { ...ctx, groupId: null }, { action: 'lookup_place', query: 'Example Music School Halifax' });
  assert.ok(noHousehold.result.error);
});

test('venue lookup requires cited evidence and returns provider failure honestly', async () => {
  const ai = require('../services/anthropic');
  const original = ai.callClaudeRaw;
  try {
    ai.callClaudeRaw = async () => ({ content: [{ type: 'text', text: 'An invented address' }] });
    assert.equal((await tools.run('calendar', ctx, { action: 'lookup_place', query: 'Unlisted Academy' })).result.ok, false);
    ai.callClaudeRaw = async () => { throw new Error('Search unavailable'); };
    assert.equal((await tools.run('calendar', ctx, { action: 'lookup_place', query: 'Unlisted Academy' })).result.error, 'Search unavailable');
    ai.callClaudeRaw = async request => {
      assert.equal(request.tools[0].max_uses, 2);
      assert.equal(request.messages[0].content, 'Unlisted Academy Halifax');
      return { content: [{ type: 'text', text: 'Unlisted Academy, 2 Fixture Road, Halifax', citations: [{ url: 'https://example.org/location', title: 'School address' }] }] };
    };
    const found = await tools.run('calendar', ctx, { action: 'lookup_place', query: 'Unlisted Academy Halifax' });
    assert.equal(found.result.evidence[0].sources[0].url, 'https://example.org/location');
  } finally { ai.callClaudeRaw = original; }
});

test('history: July date-night venue and Costco scanned line items are searchable', async () => {
  await db.addAppointment({ group_id: ctx.groupId, title: 'Date night', appointment_date: '2026-07-18', location: 'Fixture Bistro, 45 Example Road' });
  await db.addReceipt({ group_id: ctx.groupId, merchant: 'Costco', amount: 67.89, date: '2026-09-02', notes: 'Lemons — $6.99\nMilk — $5.49' });
  await db.addReceipt({ group_id: ctx.groupId, merchant: 'Costco', amount: 30, date: '2026-08-01', notes: 'Lemons — $6.99' });
  const events = await tools.run('history', ctx, { action: 'search', source: 'calendar', query: 'date night', date_from: '2026-07-01', date_to: '2026-07-31' });
  assert.equal(events.result.records.length, 1);
  assert.match(events.result.records[0].detail, /Fixture Bistro/);
  const lemons = await tools.run('history', ctx, { action: 'search', source: 'receipts', merchant: 'Costco', query: 'lemons', date_from: '2026-09-01', date_to: '2026-09-07' });
  assert.equal(lemons.result.records.length, 1);
  assert.match(lemons.result.records[0].detail, /6.99/);
  assert.equal(lemons.result.records[0].date, '2026-09-02');
  assert.match(lemons.result.purchase_guidance, /not proof/);
  const noMatch = await tools.run('history', ctx, { action: 'search', query: '%', source: 'receipts' });
  assert.equal(noMatch.result.records.length, 0, 'wildcards are literal');
});

test('history: all sources execute, pagination is stable, private records never leak', async () => {
  await run("INSERT INTO notes (user_id,title,body) VALUES (?, 'Fixture private note', 'secret')", [quinnId]);
  const secret = await db.createRoutine({ group_id: ctx.groupId, created_by: quinnId, name: 'Fixture private cycle', routine_type: 'period' });
  await db.addRoutineEntry(secret.id, { entry_date: '2026-09-01', entry_type: 'period_start', notes: 'Fixture private record' });
  for (const source of ['all', ...require('../services/historySearch').SOURCES]) {
    const result = await tools.run('history', ctx, { action: 'search', source, query: 'Fixture private' });
    assert.ok(Array.isArray(result.result.records), JSON.stringify(result));
    assert.equal(result.result.records.length, 0, source);
  }
  const first = await tools.run('history', ctx, { action: 'search', source: 'receipts', merchant: 'Costco', limit: 1 });
  assert.equal(first.result.next_offset, 1);
  const second = await tools.run('history', ctx, { action: 'search', source: 'receipts', merchant: 'Costco', limit: 1, offset: first.result.next_offset });
  assert.notEqual(first.result.records[0].id, second.result.records[0].id);
  const foreign = await tools.run('history', { ...ctx, groupId: -1 }, { action: 'search', source: 'receipts', merchant: 'Costco' });
  assert.equal(foreign.result.records.length, 0);
});

test('Home pins are ordered, personal, reversible and report actual budget spending', async () => {
  const set = await tools.run('home', ctx, { action: 'set', pins: ['budget', 'trips', 'routines', 'lists', 'calendar', 'tasks', 'pantry', 'people'] });
  assert.equal(set.result.ok, true);
  const home = await tools.run('home', ctx, { action: 'get' });
  assert.equal(home.result.cards.length, 8, JSON.stringify(home));
  assert.deepEqual(home.result.cards.map(c => c.id), set.result.pins);
  assert.match(home.result.cards[0].detail, /spent/);
  const peer = await tools.run('home', { ...ctx, userId: quinnId }, { action: 'get' });
  assert.deepEqual(peer.result.pins, []);
  assert.equal((await tools.run('home', ctx, { action: 'set', pins: ['trips', 'trips'] })).result.ok, false);
  assert.equal((await tools.run('home', ctx, { action: 'set', pins: [] })).result.ok, true);
  assert.deepEqual((await tools.run('home', ctx, { action: 'get' })).result.cards, []);
});

test('domain lifecycles: pantry, contacts, subscriptions, notes and travel', async () => {
  const call = async (name, input) => {
    const out = await tools.run(name, { ...ctx, push: null }, input);
    assert.equal(out.result.error, undefined, `${name} ${input.action}: ${JSON.stringify(out)}`);
    return out.result;
  };
  for (const scenario of [
    { domain: 'pantry', table: 'pantry', add: { item: 'Fixture rice', quantity: '2' }, update: { quantity: '3', location: 'pantry' }, check: ['quantity', '3'] },
    { domain: 'contacts', table: 'contacts', add: { name: 'Fixture Tutor', phone: '5550100' }, update: { phone: '5550101' }, check: ['phone', '5550101'] },
    { domain: 'recurring_payments', table: 'recurring_payments', add: { name: 'Fixture music', amount: 20 }, update: { amount: 25 }, check: ['amount', 25] },
    { domain: 'notes', table: 'notes', add: { title: 'Fixture note', body: 'Original' }, update: { body: 'Updated' }, check: ['body', 'Updated'] },
  ]) {
    await call(scenario.domain, { action: 'add', ...scenario.add });
    const row = await get(`SELECT * FROM ${scenario.table} ORDER BY id DESC LIMIT 1`);
    await call(scenario.domain, { action: 'list' });
    await call(scenario.domain, { action: 'update', id: row.id, ...scenario.update });
    const edited = await get(`SELECT * FROM ${scenario.table} WHERE id = ?`, [row.id]);
    assert.equal(String(edited[scenario.check[0]]), String(scenario.check[1]));
    await call(scenario.domain, { action: 'delete', id: row.id });
    assert.equal(await get(`SELECT id FROM ${scenario.table} WHERE id = ?`, [row.id]), undefined);
  }
  await call('trips', { action: 'add', traveler: 'Pam Tool', destination: 'Fixture school' });
  const trip = await get('SELECT id FROM trips ORDER BY id DESC LIMIT 1');
  await call('trips', { action: 'update', id: trip.id, destination: 'Fixture home' });
  await call('trips', { action: 'arrive', id: trip.id });
  assert.equal((await get('SELECT status FROM trips WHERE id=?', [trip.id])).status, 'arrived');
  await call('trips', { action: 'delete', id: trip.id });
});

test('Home Trips includes explicitly shared clan itineraries, excludes other households', async () => {
  const clan = await run("INSERT INTO groups (name,group_type,invite_code,created_by) VALUES ('Fixture Clan','family','CLANFIX',?)", [ctx.userId]);
  await run("INSERT INTO group_members (group_id,user_id,role) VALUES (?,?,'member')", [clan.lastID, ctx.userId]);
  const stranger = await run("INSERT INTO users (username,name,password_hash) VALUES ('trip_outsider','Outsider','x')");
  await db.createItinerary({ title: 'Visible clan camping', traveler_id: stranger.lastID, traveler_name: 'Outsider', group_id: clan.lastID, start_date: '2026-08-01', end_date: '2026-08-05' });
  await db.createItinerary({ title: 'Secret outsider holiday', traveler_id: stranger.lastID, traveler_name: 'Outsider', group_id: null, start_date: '2026-08-02', end_date: '2026-08-07' });
  await tools.run('home', ctx, { action: 'set', pins: ['trips'] });
  const result = await tools.run('home', ctx, { action: 'get' });
  assert.match(result.result.cards[0].detail, /Visible clan camping/);
  assert.match(result.result.cards[0].detail, /Clan/);
  assert.doesNotMatch(result.result.cards[0].detail, /Secret outsider/);
});

test('chat and streaming paths execute multiple actions and expose errors without false completion', async () => {
  const ai = require('../services/anthropic');
  const chat = require('../services/conciergeChat');
  const saved = { enabled: ai.isAIEnabled, raw: ai.callClaudeRaw, stream: ai.streamClaudeRaw };
  try {
    ai.isAIEnabled = () => true;
    for (const method of ['handleChat', 'handleChatStream']) {
      for (const source of ['text', 'voice', 'chat_extract']) {
        let turn = 0;
        const model = async ({ messages }) => {
          if (turn++ === 0) return { stop_reason: 'tool_use', content: [
            { type: 'tool_use', id: 'a', name: 'notes', input: { action: 'add', title: `${method} ${source}`, body: 'Persist this note' } },
            { type: 'tool_use', id: 'b', name: 'calendar', input: { action: 'add', title: 'Bad date', appointment_date: 'not-a-date' } },
          ] };
          const outputs = messages.at(-1).content;
          assert.equal(outputs[0].is_error, false);
          assert.equal(outputs[1].is_error, true);
          return { stop_reason: 'end_turn', content: [{ type: 'text', text: 'Saved your note; the event date needs clarification.' }] };
        };
        ai.callClaudeRaw = model; ai.streamClaudeRaw = model;
        const response = await chat[method](db, { userId: ctx.userId, userName: ctx.userName, message: 'Save a note and event', source });
        assert.equal(response.actions.length, 1);
        assert.match(response.reply, /clarification/);
      }
      const looping = async () => ({ stop_reason: 'tool_use', content: [{ type: 'tool_use', id: 'failed', name: 'calendar', input: { action: 'add' } }] });
      ai.callClaudeRaw = looping; ai.streamClaudeRaw = looping;
      const response = await chat[method](db, { userId: ctx.userId, userName: ctx.userName, message: 'Create something' });
      assert.equal(response.actions.length, 0);
      assert.match(response.reply, /no changes were confirmed/);
      assert.doesNotMatch(response.reply, /Done|taken care/);
    }
  } finally { ai.isAIEnabled = saved.enabled; ai.callClaudeRaw = saved.raw; ai.streamClaudeRaw = saved.stream; }
});

test('Budget Home card distinguishes no limit, monthly pace and overspending', async () => {
  const user = await run("INSERT INTO users (username,name,password_hash) VALUES ('pace_fixture','Pace','x')");
  const household = await run("INSERT INTO groups (name,group_type,invite_code,created_by) VALUES ('Pace','household','PACEFIX',?)", [user.lastID]);
  await run("INSERT INTO group_members (group_id,user_id,role) VALUES (?,?,'admin')", [household.lastID,user.lastID]);
  const pace = { ...ctx, userId: user.lastID, groupId: household.lastID, today: '2099-09-10' };
  await tools.run('home', pace, { action: 'set', pins: ['budget'] });
  const card = async () => (await tools.run('home', pace, { action: 'get' })).result.cards[0];
  assert.equal((await card()).headline, 'Set a monthly budget');
  await db.addBudgetCategory('Living', 300, null, pace.groupId);
  const receipt = await db.addReceipt({ group_id: pace.groupId, merchant: 'Fixture store', date: '2099-09-01', amount: 90, category: 'Uncategorized' });
  assert.equal((await card()).headline, 'On track this month');
  assert.match((await card()).detail, /90.00/, 'spending outside named categories is still counted');
  await run('UPDATE receipts SET amount=150 WHERE id=?', [receipt.id]);
  assert.equal((await card()).headline, 'Above this month’s pace');
  await run('UPDATE receipts SET amount=310 WHERE id=?', [receipt.id]);
  assert.equal((await card()).headline, 'Over monthly budget');
});
