// Gift ideas are surprise-protected. A real server, four people in one home:
// Dad and Mom plan their son's birthday privately, Dad keeps ideas for Mom to
// himself, and a teen with an account must see none of it.
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn } = require('node:child_process');

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'kinrows-gifts-'));
process.env.FAMILY_DB_DIR = dir;
const FamilyDB = require('../database');
const tools = require('../services/conciergeTools');
const { searchHistory } = require('../services/historySearch');
const base = 'http://127.0.0.1:3973';
const pushFile = path.join(dir, 'pushes.jsonl');
const pushes = () => fs.existsSync(pushFile) ? fs.readFileSync(pushFile, 'utf8').trim().split('\n').filter(Boolean).map(JSON.parse) : [];
let server, db;
let dad, mom, teen, outsider;          // HTTP clients
let dadId, momId, teenId, outsiderId, groupId;
let sonPersonId, momPersonId, teenPersonId;

function client() {
  let cookie = '';
  return async (method, route, body) => {
    const res = await fetch(base + route, { method, headers: { 'Content-Type': 'application/json', Cookie: cookie }, body: body ? JSON.stringify(body) : undefined });
    if (res.headers.get('set-cookie')) cookie = res.headers.get('set-cookie').split(';')[0];
    return { status: res.status, body: await res.json() };
  };
}
const q = (sql, params = []) => new Promise((resolve, reject) => db.db.all(sql, params, (e, r) => e ? reject(e) : resolve(r)));
const titles = res => res.body.map(g => g.title).sort();

before(async () => {
  server = spawn(process.execPath, ['--require', './test/fixtures/capture-push.js', 'dashboard.js'], { cwd: path.join(__dirname, '..'), stdio: 'ignore', env: {
    ...process.env, PORT: '3973', PUSH_CAPTURE_FILE: pushFile, FAMILY_DB_DIR: dir, NODE_ENV: 'test', SESSION_SECRET: 'isolated-gift-privacy',
    ANTHROPIC_API_KEY: '', RESEND_API_KEY: '', STRIPE_SECRET_KEY: '', APNS_KEY_ID: '',
  } });
  let healthy = false;
  for (let n = 0; n < 100; n++) {
    try { if ((await fetch(base + '/healthz')).ok) { healthy = true; break; } } catch {}
    await new Promise(r => setTimeout(r, 150));
  }
  assert.ok(healthy, 'isolated server started');
  dad = client(); mom = client(); teen = client(); outsider = client();
  const reg = await dad('POST', '/api/auth/register', { username: 'gift_dad', password: 'isolated-fixture-123', name: 'Dad' });
  assert.equal(reg.status, 200);
  groupId = reg.body.household.id;
  const code = reg.body.household.invite_code;
  for (const [c, username, name] of [[mom, 'gift_mom', 'Mom'], [teen, 'gift_teen', 'Teen']]) {
    const r = await c('POST', '/api/auth/register', { username, password: 'isolated-fixture-123', name, invite_code: code });
    assert.equal(r.status, 200, JSON.stringify(r.body));
    assert.equal(r.body.household.id, groupId);
  }
  assert.equal((await outsider('POST', '/api/auth/register', { username: 'gift_out', password: 'isolated-fixture-123', name: 'Out' })).status, 200);
  db = new FamilyDB();
  [dadId, momId, teenId, outsiderId] = await Promise.all(['gift_dad', 'gift_mom', 'gift_teen', 'gift_out']
    .map(async u => (await db.getUserByUsername(u)).id));
  const people = (await dad('GET', '/api/people')).body;
  momPersonId = people.find(p => p.user_id === momId).id;
  teenPersonId = people.find(p => p.user_id === teenId).id;
  sonPersonId = (await dad('POST', '/api/people', { name: 'Max', relationship: 'son', is_dependent: 1 })).body.id;
});
after(() => { server?.kill('SIGKILL'); db?.close(); fs.rmSync(dir, { recursive: true, force: true }); });

let bikeId, necklaceId, legoId, secretId;

test('saving: shared with Mom, private, and household ideas', async () => {
  let r = await dad('POST', '/api/gifts/ideas', { person_id: sonPersonId, title: 'Bike', for_event: 'birthday', visibility: 'shared', shared_with_user_id: momId });
  assert.equal(r.status, 200, JSON.stringify(r.body)); bikeId = r.body.id;
  r = await dad('POST', '/api/gifts/ideas', { person_id: sonPersonId, title: 'Secret drone', visibility: 'private' });
  assert.equal(r.status, 200); secretId = r.body.id;
  r = await dad('POST', '/api/gifts/ideas', { person_id: sonPersonId, title: 'Lego', for_event: 'birthday' });
  assert.equal(r.status, 200); legoId = r.body.id;
  // Household visibility for Mom's own gift — the surprise rule must still hide it from her.
  r = await dad('POST', '/api/gifts/ideas', { person_id: momPersonId, title: 'Necklace' });
  assert.equal(r.status, 200); necklaceId = r.body.id;
  const row = (await q('SELECT created_by, visibility, shared_with_user_id FROM gift_ideas WHERE id = ?', [bikeId]))[0];
  assert.deepEqual(row, { created_by: dadId, visibility: 'shared', shared_with_user_id: momId });
});

test('visibility: each person sees exactly what they should', async () => {
  assert.deepEqual(titles(await dad('GET', '/api/gifts/ideas')), ['Bike', 'Lego', 'Necklace', 'Secret drone']);
  assert.deepEqual(titles(await mom('GET', '/api/gifts/ideas')), ['Bike', 'Lego'], 'Mom sees the shared bike, never her necklace');
  assert.deepEqual(titles(await mom('GET', `/api/gifts/ideas?person_id=${momPersonId}`)), []);
  assert.deepEqual(titles(await teen('GET', '/api/gifts/ideas')), ['Lego', 'Necklace'], 'teen sees only household ideas');
  assert.deepEqual(titles(await outsider('GET', '/api/gifts/ideas')), []);
});

test('people counts do not leak hidden ideas', async () => {
  const count = async (c, pid) => (await c('GET', '/api/people')).body.find(p => p.id === pid).gift_idea_count;
  assert.equal(await count(mom, momPersonId), 0, 'Mom cannot infer gifts exist for her');
  assert.equal(await count(dad, momPersonId), 1);
  assert.equal(await count(teen, sonPersonId), 1);
  assert.equal(await count(mom, sonPersonId), 2);
});

test('hidden ideas cannot be edited, deleted, or bought by others', async () => {
  for (const id of [necklaceId, secretId]) {
    assert.equal((await mom('PUT', `/api/gifts/ideas/${id}`, { title: 'x' })).status, 404);
    assert.equal((await mom('DELETE', `/api/gifts/ideas/${id}`)).status, 404);
    assert.equal((await mom('POST', `/api/gifts/ideas/${id}/purchased`, {})).status, 404);
  }
  assert.equal((await teen('PUT', `/api/gifts/ideas/${bikeId}`, { status: 'given' })).status, 404);
  assert.equal((await outsider('DELETE', `/api/gifts/ideas/${legoId}`)).status, 403);
  // Mom can edit the shared bike but can't re-scope Dad's idea.
  assert.equal((await mom('PUT', `/api/gifts/ideas/${bikeId}`, { notes: 'Blue' })).status, 200);
  assert.equal((await mom('PUT', `/api/gifts/ideas/${bikeId}`, { visibility: 'household' })).status, 403);
  // Clients can't forge server-managed fields.
  await mom('PUT', `/api/gifts/ideas/${bikeId}`, { created_by: momId, purchased_by: momId });
  const row = (await q('SELECT created_by, purchased_by FROM gift_ideas WHERE id = ?', [bikeId]))[0];
  assert.deepEqual(row, { created_by: dadId, purchased_by: null });
});

test('sharing validation: no self, outsiders, recipients, or foreign people', async () => {
  const bad = async body => (await dad('POST', '/api/gifts/ideas', { title: 'x', person_id: sonPersonId, ...body })).status;
  assert.equal(await bad({ visibility: 'shared', shared_with_user_id: dadId }), 400);
  assert.equal(await bad({ visibility: 'shared', shared_with_user_id: outsiderId }), 400);
  assert.equal(await bad({ visibility: 'shared' }), 400);
  assert.equal(await bad({ visibility: 'everyone' }), 400);
  assert.equal(await bad({ person_id: momPersonId, visibility: 'shared', shared_with_user_id: momId }), 400, 'cannot share a gift with its recipient');
  const foreign = await outsider('POST', '/api/people', { name: 'Stranger kid' });
  assert.equal(await bad({ person_id: foreign.body.id }), 403);
});

test('mark bought: notifies Mom with a private push, never the household', async () => {
  const before = (await q("SELECT COUNT(*) AS n FROM feed_posts")).at(0).n;
  const pushesBefore = pushes().length;
  const r = await dad('POST', `/api/gifts/ideas/${bikeId}/purchased`, { notify_user_id: momId });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal(r.body.notified, true);
  const row = (await q('SELECT status, purchased_by, purchased_at, visibility FROM gift_ideas WHERE id = ?', [bikeId]))[0];
  assert.equal(row.status, 'purchased');
  assert.equal(row.purchased_by, dadId);
  assert.ok(row.purchased_at);
  assert.equal(row.visibility, 'shared');
  const sent = pushes().slice(pushesBefore);
  assert.equal(sent.length, 1, 'exactly one push');
  assert.equal(sent[0].kind, 'user', 'a direct push, never a household broadcast');
  assert.equal(sent[0].userId, momId);
  assert.match(sent[0].body, /Dad bought Bike for Max's birthday/);
  assert.deepEqual(sent[0].data, { type: 'gift', ref_id: sonPersonId, actor_id: dadId });
  assert.equal((await q("SELECT COUNT(*) AS n FROM feed_posts")).at(0).n, before, 'no feed post');
});

test('mark bought: notifying about a private idea shares it with just that person', async () => {
  const r = await dad('POST', `/api/gifts/ideas/${secretId}/purchased`, { notify_user_id: momId });
  assert.equal(r.status, 200);
  assert.ok(titles(await mom('GET', '/api/gifts/ideas')).includes('Secret drone'));
  assert.ok(!titles(await teen('GET', '/api/gifts/ideas')).includes('Secret drone'));
  // Nobody can be notified about their own gift, and Mom can't pull the teen into Dad's idea.
  assert.equal((await dad('POST', `/api/gifts/ideas/${necklaceId}/purchased`, { notify_user_id: momId })).status, 400);
  assert.equal((await mom('POST', `/api/gifts/ideas/${secretId}/purchased`, { notify_user_id: teenId })).status, 403);
  // Plain mark-bought without a notification works too.
  const count = pushes().length;
  const plain = await dad('POST', `/api/gifts/ideas/${legoId}/purchased`, {});
  assert.deepEqual(plain.body, { success: true, notified: false });
  assert.equal(pushes().length, count, 'no push without a recipient');
});

test('concierge and history search follow the surprise rule', async () => {
  const momCtx = { db, userId: momId, groupId, userName: 'Mom', today: '2026-09-25', push: null };
  const teenCtx = { ...momCtx, userId: teenId, userName: 'Teen' };
  const listed = await tools.run('gifts', momCtx, { action: 'list_ideas' });
  assert.ok(!JSON.stringify(listed).includes('Necklace'), 'concierge never lists Mom\'s gift to her');
  const upd = await tools.run('gifts', momCtx, { action: 'update_idea', id: necklaceId, status: 'given' });
  assert.notEqual(upd.result?.ok, true, 'concierge cannot touch a hidden idea');
  const del = await tools.run('gifts', teenCtx, { action: 'delete_idea', id: bikeId });
  assert.notEqual(del.result?.ok, true);
  assert.equal((await q('SELECT COUNT(*) AS n FROM gift_ideas WHERE id = ?', [bikeId]))[0].n, 1);
  const search = JSON.stringify(await searchHistory(momCtx, { query: 'Necklace', source: 'gifts' }));
  assert.ok(!search.includes('Necklace'));
  const teenSearch = JSON.stringify(await searchHistory(teenCtx, { query: 'Bike', source: 'gifts' }));
  assert.ok(!teenSearch.includes('Bike'));
});

test('data export excludes ideas saved for you', async () => {
  const exp = await db.exportUserAccount(momId);
  const mine = exp.gift_ideas.map(g => g.title);
  assert.ok(!mine.includes('Necklace'));
  assert.ok(mine.includes('Bike'));
});
