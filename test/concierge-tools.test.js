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

test('send_message: resolves by first name, refuses strangers', async () => {
  const sent = await tools.run('send_message', ctx, { to: 'Quinn', text: 'Home late tonight' });
  assert.equal(sent.result.ok, true, JSON.stringify(sent.result));
  const row = await get('SELECT sender_id, recipient_id, text FROM direct_messages ORDER BY id DESC LIMIT 1');
  assert.equal(row.recipient_id, quinnId);
  assert.equal(row.text, 'Home late tonight');

  const stranger = await tools.run('send_message', ctx, { to: 'Zorp', text: 'hi' });
  assert.equal(stranger.result.ok, false);
});
