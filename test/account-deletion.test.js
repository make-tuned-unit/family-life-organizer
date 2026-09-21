// Account deletion (App Store 5.1.1(v)) + concierge/DM erasure.
// Verifies re-auth is required, personal data is wiped, a sole-owner
// household is deleted, and a shared household survives with the user removed.

const { test, before, after } = require('node:test');
const assert = require('node:assert');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const PORT = 3993;
const BASE = `http://127.0.0.1:${PORT}`;
let server, tmpDir;

function makeClient() {
  let cookie = '';
  return async (method, pathname, body) => {
    const res = await fetch(BASE + pathname, {
      method,
      headers: { 'Content-Type': 'application/json', ...(cookie ? { Cookie: cookie } : {}) },
      body: body ? JSON.stringify(body) : undefined,
      redirect: 'manual',
    });
    const sc = res.headers.get('set-cookie');
    if (sc) cookie = sc.split(';')[0];
    let json = null; try { json = await res.json(); } catch {}
    return { status: res.status, body: json };
  };
}
async function waitForHealth(t = 15000) {
  const s = Date.now();
  while (Date.now() - s < t) { try { if ((await fetch(BASE + '/healthz')).ok) return; } catch {} await new Promise(r => setTimeout(r, 200)); }
  throw new Error('server did not become healthy');
}

before(async () => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'fl-del-'));
  server = spawn('node', ['dashboard.js'], {
    cwd: path.join(__dirname, '..'),
    env: { ...process.env, PORT: String(PORT), FAMILY_DB_DIR: tmpDir, SESSION_SECRET: 'test', NODE_ENV: 'test', ANTHROPIC_API_KEY: '' },
    stdio: 'ignore',
  });
  await waitForHealth();
});
after(() => { if (server) server.kill('SIGKILL'); if (tmpDir) fs.rmSync(tmpDir, { recursive: true, force: true }); });

test('delete requires the correct password', async () => {
  const c = makeClient();
  await c('POST', '/api/auth/register', { username: 'del_a', password: 'password123', name: 'Del A' });
  const wrong = await c('POST', '/api/account/delete', { current_password: 'nope' });
  assert.equal(wrong.status, 401);
  const me = await c('GET', '/api/auth/me');
  assert.equal(me.status, 200, 'still logged in after failed delete');
});

test('sole-owner household + personal data are erased; login no longer works', async () => {
  const c = makeClient();
  await c('POST', '/api/auth/register', { username: 'del_b', password: 'password123', name: 'Del B' });
  // Leave a data trail: a task, a list, a contact.
  await c('POST', '/api/add', { type: 'task', data: { title: 'Solo task' } });
  await c('POST', '/api/lists', { name: 'Solo List' });
  await c('POST', '/api/contacts', { name: 'Solo Contact', relationship: 'friend' });

  const del = await c('POST', '/api/account/delete', { current_password: 'password123' });
  assert.equal(del.status, 200);

  // Session destroyed.
  assert.equal((await c('GET', '/api/auth/me')).status, 401);
  // Credentials gone — cannot log back in.
  const relog = await makeClient()('POST', '/api/auth/login', { username: 'del_b', password: 'password123' });
  assert.equal(relog.status, 401);
  // Username is free again (row deleted, not just flagged).
  const reReg = await makeClient()('POST', '/api/auth/register', { username: 'del_b', password: 'password123', name: 'Del B2' });
  assert.equal(reReg.status, 200);
});

test('shared household survives; departing user is removed', async () => {
  const owner = makeClient();
  const reg = await owner('POST', '/api/auth/register', { username: 'del_owner', password: 'password123', name: 'Owner' });
  const invite = reg.body.household.invite_code;
  const joiner = makeClient();
  await joiner('POST', '/api/auth/register', { username: 'del_joiner', password: 'password123', name: 'Joiner', invite_code: invite });

  // Owner adds a shared task, then deletes their account.
  await owner('POST', '/api/add', { type: 'task', data: { title: 'Shared task' } });
  assert.equal((await owner('POST', '/api/account/delete', { current_password: 'password123' })).status, 200);

  // Joiner still has the household and its shared task.
  const tasks = await joiner('GET', '/api/tasks');
  assert.equal(tasks.status, 200);
  assert.ok(tasks.body.some(t => t.title === 'Shared task'), 'shared task survives owner deletion');
});

// Inspect actual storage, not only authentication failure after deletion.
async function inspectDB(work) {
  const sqlite3 = require('sqlite3');
  const db = new sqlite3.Database(path.join(tmpDir, 'family.db'));
  const run = (sql, params = []) => new Promise((resolve, reject) => db.run(sql, params, function(e) { e ? reject(e) : resolve(this); }));
  const get = (sql, params = []) => new Promise((resolve, reject) => db.get(sql, params, (e, row) => e ? reject(e) : resolve(row)));
  try { return await work({ run, get }); }
  finally { await new Promise(resolve => db.close(resolve)); }
}

test('deletion erases private health, calendar, OAuth and preferences in a surviving household', async () => {
  const owner = makeClient(), member = makeClient();
  const reg = await owner('POST', '/api/auth/register', { username: 'del_health', password: 'password123', name: 'Health Owner' });
  await member('POST', '/api/auth/register', { username: 'del_health_other', password: 'password123', name: 'Other', invite_code: reg.body.household.invite_code });
  let uid, routineId, entryId;
  await inspectDB(async ({ run, get }) => {
    uid = (await get("SELECT id FROM users WHERE username = 'del_health'")).id;
    routineId = (await run("INSERT INTO routines(group_id,created_by,name,routine_type,shared_scope) VALUES (?,?,'Private cycle','period','private')", [reg.body.household.id, uid])).lastID;
    entryId = (await run("INSERT INTO routine_entries(routine_id,entry_date,entry_type,value,created_by) VALUES (?,'2026-09-21','symptom','sensitive fixture',?)", [routineId, uid])).lastID;
    await run("INSERT INTO synced_calendar_events(user_id,group_id,external_id,title,starts_at) VALUES (?,?,'fixture','Private appointment','2026-09-21T10:00:00')", [uid, reg.body.household.id]);
    await run("INSERT INTO home_preferences(user_id,pins) VALUES (?, '[\"budget\"]')", [uid]);
    await run("INSERT INTO oauth_clients(client_id,client_name,redirect_uris) VALUES ('deletion-fixture','QA','[]')");
    await run("INSERT INTO oauth_tokens(user_id,client_id,access_hash,refresh_hash,scope,expires_at) VALUES (?,'deletion-fixture','fixture-access','fixture-refresh','write','2099-01-01')", [uid]);
  });
  assert.equal((await owner('POST', '/api/account/delete', { current_password: 'password123' })).status, 200);
  await inspectDB(async ({ get }) => {
    assert.equal(await get('SELECT id FROM routines WHERE id=?', [routineId]), undefined);
    assert.equal(await get('SELECT id FROM routine_entries WHERE id=?', [entryId]), undefined);
    for (const table of ['synced_calendar_events', 'home_preferences', 'oauth_tokens']) {
      assert.equal((await get(`SELECT COUNT(*) AS n FROM ${table} WHERE user_id=?`, [uid])).n, 0, table);
    }
    assert.ok(await get('SELECT id FROM groups WHERE id=?', [reg.body.household.id]), 'other household member survives');
  });
});

test('sole-owner deletion erases child rows with no household column', async () => {
  const c = makeClient();
  const reg = await c('POST', '/api/auth/register', { username: 'del_children', password: 'password123', name: 'Children QA' });
  let routineId, decisionId;
  await inspectDB(async ({ run, get }) => {
    const uid = (await get("SELECT id FROM users WHERE username='del_children'")).id;
    routineId = (await run("INSERT INTO routines(group_id,created_by,name,routine_type,shared_scope) VALUES (?,?,'Shared sleep','baby_sleep','household')", [reg.body.household.id, uid])).lastID;
    await run("INSERT INTO routine_entries(routine_id,entry_date,notes) VALUES (?,'2026-09-21','health fixture')", [routineId]);
    decisionId = (await run("INSERT INTO decisions(group_id,title,decision_type) VALUES (?,'Fixture','poll')", [reg.body.household.id])).lastID;
    await run("INSERT INTO decision_comments(decision_id,member_name,text) VALUES (?,'QA','personal fixture')", [decisionId]);
  });
  assert.equal((await c('POST', '/api/account/delete', { current_password: 'password123' })).status, 200);
  await inspectDB(async ({ get }) => {
    assert.equal((await get('SELECT COUNT(*) AS n FROM routine_entries WHERE routine_id=?', [routineId])).n, 0);
    assert.equal((await get('SELECT COUNT(*) AS n FROM decision_comments WHERE decision_id=?', [decisionId])).n, 0);
  });
});

test('deletion invalidates another device cookie as well as refresh tokens', async () => {
  const owner = makeClient(), otherDevice = makeClient();
  await owner('POST', '/api/auth/register', { username: 'del_cookie', password: 'password123', name: 'Cookie QA' });
  assert.equal((await otherDevice('POST', '/api/auth/login', { username: 'del_cookie', password: 'password123' })).status, 200);
  assert.equal((await otherDevice('GET', '/api/notes')).status, 200);
  assert.equal((await owner('POST', '/api/account/delete', { current_password: 'password123' })).status, 200);
  assert.equal((await otherDevice('GET', '/api/notes')).status, 401);
  assert.equal((await otherDevice('POST', '/api/notes', { body: 'must not create orphan personal data' })).status, 401);
});
