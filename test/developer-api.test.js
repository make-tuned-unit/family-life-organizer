// Developer API (bring-your-own-agent): key minting is premium-gated, keys
// authenticate /v1, read-scoped keys cannot write, tools act on the key
// owner's household only, revocation and lapsed entitlement cut access, and
// the MCP endpoint speaks enough JSON-RPC for a host to list + call tools.

const { test, before, after } = require('node:test');
const assert = require('node:assert');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const PORT = 3988;
const BASE = `http://127.0.0.1:${PORT}`;
let server, tmpDir;

function makeClient() {
  let cookie = '';
  return async (method, pathname, body, headers = {}) => {
    const res = await fetch(BASE + pathname, {
      method,
      headers: { 'Content-Type': 'application/json', ...(cookie ? { Cookie: cookie } : {}), ...headers },
      body: body ? JSON.stringify(body) : undefined,
      redirect: 'manual',
    });
    const sc = res.headers.get('set-cookie');
    if (sc) cookie = sc.split(';')[0];
    let json = null; try { json = await res.json(); } catch {}
    return { status: res.status, body: json };
  };
}
function bearer(key) {
  return async (method, pathname, body) => {
    const res = await fetch(BASE + pathname, {
      method,
      headers: { 'Content-Type': 'application/json', ...(key ? { Authorization: `Bearer ${key}` } : {}) },
      body: body ? JSON.stringify(body) : undefined,
    });
    let json = null; try { json = await res.json(); } catch {}
    return { status: res.status, body: json };
  };
}
function householdOf(me) {
  const g = (me.groups || []).find(x => x.group_type === 'household') || (me.groups || [])[0];
  return g?.id;
}
async function waitForHealth(t = 15000) {
  const s = Date.now();
  while (Date.now() - s < t) { try { if ((await fetch(BASE + '/healthz')).ok) return; } catch {} await new Promise(r => setTimeout(r, 200)); }
  throw new Error('server did not become healthy');
}

// First registered user gets id 1 — make them the admin so the suite can comp
// households via /api/admin/comp.
before(async () => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'fl-devapi-'));
  server = spawn('node', ['dashboard.js'], {
    cwd: path.join(__dirname, '..'),
    env: { ...process.env, PORT: String(PORT), FAMILY_DB_DIR: tmpDir, SESSION_SECRET: 'test', NODE_ENV: 'test', ANTHROPIC_API_KEY: '', ADMIN_USER_IDS: '1' },
    stdio: 'ignore',
  });
  await waitForHealth();
});
after(() => { if (server) server.kill('SIGKILL'); if (tmpDir) fs.rmSync(tmpDir, { recursive: true, force: true }); });

let admin, ada, adaGroup, adaKey, adaReadKey;

test('key minting requires a paid household', async () => {
  admin = makeClient();
  await admin('POST', '/api/auth/register', { username: 'dev_admin', password: 'password123', name: 'Dev Admin' });
  ada = makeClient();
  await ada('POST', '/api/auth/register', { username: 'dev_ada', password: 'password123', name: 'Ada Dev' });
  const me = await ada('GET', '/api/auth/me');
  adaGroup = householdOf(me.body);
  assert.ok(adaGroup, 'ada has a household');

  const denied = await ada('POST', '/api/developer/keys', { name: 'agent' });
  assert.equal(denied.status, 402);

  const comp = await admin('POST', '/api/admin/comp', { group_id: adaGroup, action: 'grant' });
  assert.equal(comp.status, 200);

  const created = await ada('POST', '/api/developer/keys', { name: 'My Claude agent' });
  assert.equal(created.status, 201);
  assert.match(created.body.key, /^kr_live_[0-9a-f]{64}$/);
  assert.equal(created.body.scope, 'write');
  adaKey = created.body.key;

  const ro = await ada('POST', '/api/developer/keys', { name: 'Read only', scope: 'read' });
  assert.equal(ro.status, 201);
  adaReadKey = ro.body.key;

  const bad = await ada('POST', '/api/developer/keys', { name: 'x', scope: 'admin' });
  assert.equal(bad.status, 400);

  const list = await ada('GET', '/api/developer/keys');
  assert.equal(list.body.keys.length, 2);
  assert.ok(list.body.keys.every(k => !k.key && k.key_prefix.startsWith('kr_live_')), 'plaintext never listed');
});

test('/v1 rejects missing, malformed and unknown keys', async () => {
  assert.equal((await bearer(null)('GET', '/v1/me')).status, 401);
  assert.equal((await bearer('nope')('GET', '/v1/me')).status, 401);
  assert.equal((await bearer('kr_live_' + 'a'.repeat(64))('GET', '/v1/me')).status, 401);
});

test('/v1/me, /v1/tools and /v1/snapshot answer for a valid key', async () => {
  const c = bearer(adaKey);
  const me = await c('GET', '/v1/me');
  assert.equal(me.status, 200);
  assert.equal(me.body.user.name, 'Ada Dev');
  assert.equal(me.body.household.id, adaGroup);
  assert.equal(me.body.key.scope, 'write');

  const tools = await c('GET', '/v1/tools');
  assert.equal(tools.status, 200);
  const names = tools.body.tools.map(t => t.name);
  assert.ok(names.includes('tasks') && names.includes('lists') && names.includes('send_message'));
  assert.ok(tools.body.tools[0].input_schema, 'anthropic shape by default');

  const oa = await c('GET', '/v1/tools?format=openai');
  assert.equal(oa.body.tools[0].type, 'function');
  assert.ok(oa.body.tools[0].function.parameters);

  const snap = await c('GET', '/v1/snapshot');
  assert.equal(snap.status, 200);
});

test('write key can add/list/complete a task; read key can list but not write', async () => {
  const w = bearer(adaKey);
  const add = await w('POST', '/v1/tools/tasks', { action: 'add', title: 'Book dentist' });
  assert.equal(add.status, 200, JSON.stringify(add.body));
  const list = await w('POST', '/v1/tools/tasks', { action: 'list' });
  assert.equal(list.status, 200);
  assert.ok(JSON.stringify(list.body).includes('Book dentist'));

  const r = bearer(adaReadKey);
  const rlist = await r('POST', '/v1/tools/tasks', { action: 'list' });
  assert.equal(rlist.status, 200);
  const radd = await r('POST', '/v1/tools/tasks', { action: 'add', title: 'Should fail' });
  assert.equal(radd.status, 403);
  const rsend = await r('POST', '/v1/tools/send_message', { to: 'Ada', text: 'hi' });
  assert.equal(rsend.status, 403);

  const unknown = await w('POST', '/v1/tools/tasks', { action: 'teleport' });
  assert.equal(unknown.status, 400);
  const notool = await w('POST', '/v1/tools/nope', {});
  assert.equal(notool.status, 400);
});

test('keys are scoped to their owner household (no cross-household leakage)', async () => {
  const bob = makeClient();
  await bob('POST', '/api/auth/register', { username: 'dev_bob', password: 'password123', name: 'Bob Other' });
  const bobGroup = householdOf((await bob('GET', '/api/auth/me')).body);
  await admin('POST', '/api/admin/comp', { group_id: bobGroup, action: 'grant' });
  const bk = (await bob('POST', '/api/developer/keys', { name: 'bob agent' })).body.key;
  const list = await bearer(bk)('POST', '/v1/tools/tasks', { action: 'list' });
  assert.equal(list.status, 200);
  assert.ok(!JSON.stringify(list.body).includes('Book dentist'), "bob's key must not see ada's tasks");
});

test('MCP endpoint: legacy clients get tools, structured calls, resources, prompts, notifications, and batches', async () => {
  const c = bearer(adaKey);
  const init = await c('POST', '/v1/mcp', { jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-03-26', capabilities: {}, clientInfo: { name: 't', version: '0' } } });
  assert.equal(init.status, 200);
  assert.equal(init.body.result.serverInfo.name, 'kinrows');
  assert.ok(init.body.result.capabilities.tools);

  const notif = await fetch(BASE + '/v1/mcp', { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${adaKey}` }, body: JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }) });
  assert.equal(notif.status, 202);

  const list = await c('POST', '/v1/mcp', { jsonrpc: '2.0', id: 2, method: 'tools/list' });
  assert.ok(list.body.result.tools.some(t => t.name === 'tasks' && t.inputSchema));

  const call = await c('POST', '/v1/mcp', { jsonrpc: '2.0', id: 3, method: 'tools/call', params: { name: 'tasks', arguments: { action: 'list' } } });
  assert.equal(call.body.result.isError, false);
  assert.ok(call.body.result.content[0].text.includes('Book dentist'));
  assert.ok(call.body.result.structuredContent.result, 'tool result is also machine-readable');

  const ro = await bearer(adaReadKey)('POST', '/v1/mcp', { jsonrpc: '2.0', id: 4, method: 'tools/call', params: { name: 'tasks', arguments: { action: 'add', title: 'nope' } } });
  assert.equal(ro.body.result.isError, true);

  const resources = await c('POST', '/v1/mcp', { jsonrpc: '2.0', id: 5, method: 'resources/list' });
  assert.ok(resources.body.result.resources.some(r => r.uri === 'kinrows://household/snapshot'));
  const snapshot = await c('POST', '/v1/mcp', { jsonrpc: '2.0', id: 8, method: 'resources/read', params: { uri: 'kinrows://household/snapshot' } });
  assert.equal(snapshot.body.result.contents[0].mimeType, 'application/json');
  assert.ok(JSON.parse(snapshot.body.result.contents[0].text).counts);

  const prompts = await c('POST', '/v1/mcp', { jsonrpc: '2.0', id: 9, method: 'prompts/list' });
  assert.ok(prompts.body.result.prompts.some(p => p.name === 'plan-week'));
  const prompt = await c('POST', '/v1/mcp', { jsonrpc: '2.0', id: 10, method: 'prompts/get', params: { name: 'plan-week', arguments: {} } });
  assert.match(prompt.body.result.messages[0].content.text, /kinrows:\/\/household\/snapshot/i);

  const needsConfirm = await c('POST', '/v1/mcp', { jsonrpc: '2.0', id: 11, method: 'tools/call', params: { name: 'tasks', arguments: { action: 'delete', task_id: 999 } } });
  assert.equal(needsConfirm.body.result.isError, true);
  assert.equal(needsConfirm.body.result.structuredContent.result.confirmation_required, true);

  const batch = await c('POST', '/v1/mcp', [{ jsonrpc: '2.0', id: 6, method: 'ping' }, { jsonrpc: '2.0', id: 7, method: 'ping' }]);
  assert.equal(batch.body.length, 2);

  const audit = await c('POST', '/v1/mcp', { jsonrpc: '2.0', id: 12, method: 'resources/read', params: { uri: 'kinrows://developer/audit' } });
  const events = JSON.parse(audit.body.result.contents[0].text).events;
  assert.ok(events.some(e => e.transport === 'mcp' && e.status === 'confirmation_required'));
  assert.ok(events.some(e => e.transport === 'rest' && e.tool_name === 'tasks'));
});

test('revoking a key and lapsing the subscription both cut access', async () => {
  const keys = (await ada('GET', '/api/developer/keys')).body.keys;
  const roRow = keys.find(k => k.scope === 'read');
  const del = await ada('DELETE', `/api/developer/keys/${roRow.id}`);
  assert.equal(del.status, 200);
  assert.equal((await bearer(adaReadKey)('GET', '/v1/me')).status, 401);
  assert.equal((await ada('DELETE', `/api/developer/keys/${roRow.id}`)).status, 404, 'already revoked');

  // Another user cannot revoke ada's key.
  const bob = makeClient();
  await bob('POST', '/api/auth/login', { username: 'dev_bob', password: 'password123' });
  const wRow = keys.find(k => k.scope === 'write');
  assert.equal((await bob('DELETE', `/api/developer/keys/${wRow.id}`)).status, 404);

  await admin('POST', '/api/admin/comp', { group_id: adaGroup, action: 'revoke' });
  assert.equal((await bearer(adaKey)('GET', '/v1/me')).status, 402);
  // Lapsed subscriber can still list/revoke (list is premium-gated, revoke is not).
  assert.equal((await ada('DELETE', `/api/developer/keys/${wRow.id}`)).status, 200);
});
