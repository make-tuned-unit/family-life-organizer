// Real Concierge handler -> SQLite -> authenticated HTTP endpoint used by iOS.
// No provider calls, live accounts, email or push delivery.
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn } = require('node:child_process');
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'kinrows-wiring-'));
process.env.FAMILY_DB_DIR = dir;
const FamilyDB = require('../database');
const tools = require('../services/conciergeTools');
const base = 'http://127.0.0.1:3972';
let server, db, ctx, owner, outsider;
function client() {
  let cookie = '';
  return async (method, route, body) => {
    const res = await fetch(base + route, { method, headers: { 'Content-Type': 'application/json', Cookie: cookie }, body: body ? JSON.stringify(body) : undefined });
    if (res.headers.get('set-cookie')) cookie = res.headers.get('set-cookie').split(';')[0];
    return { status: res.status, body: await res.json() };
  };
}
before(async () => {
  server = spawn(process.execPath, ['dashboard.js'], { cwd: path.join(__dirname, '..'), stdio: 'ignore', env: {
    ...process.env, PORT: '3972', FAMILY_DB_DIR: dir, NODE_ENV: 'test', SESSION_SECRET: 'isolated-release-wiring',
    ANTHROPIC_API_KEY: '', RESEND_API_KEY: '', STRIPE_SECRET_KEY: '', APNS_KEY_ID: '',
  } });
  let healthy = false;
  for (let n = 0; n < 100; n++) {
    try { if ((await fetch(base + '/healthz')).ok) { healthy = true; break; } } catch {}
    await new Promise(r => setTimeout(r, 150));
  }
  assert.ok(healthy, 'isolated server started');
  owner = client(); outsider = client();
  const reg = await owner('POST', '/api/auth/register', { username: 'qa_owner', password: 'isolated-fixture-123', name: 'QA Owner' });
  assert.equal(reg.status, 200);
  const other = await outsider('POST', '/api/auth/register', { username: 'qa_other', password: 'isolated-fixture-123', name: 'QA Other' });
  assert.equal(other.status, 200);
  db = new FamilyDB();
  const user = await db.getUserByUsername('qa_owner');
  ctx = { db, userId: user.id, groupId: reg.body.household.id, userName: 'QA Owner', today: '2026-09-21', push: null };
});
after(() => { server?.kill('SIGKILL'); db?.close(); fs.rmSync(dir, { recursive: true, force: true }); });
async function act(domain, input) {
  const out = await tools.run(domain, ctx, input);
  assert.notEqual(out.result?.ok, false, JSON.stringify(out));
  assert.equal(out.result?.error, undefined, JSON.stringify(out));
  return out.result;
}
for (const s of [
  { domain: 'pantry', route: '/api/pantry', table: 'pantry', add: { item: 'QA rice', quantity: '2' }, edit: { quantity: '3' }, field: 'quantity', value: '3' },
  { domain: 'notes', route: '/api/notes', table: 'notes', add: { title: 'QA note', body: 'Initial' }, edit: { body: 'Revised' }, field: 'body', value: 'Revised' },
  { domain: 'contacts', route: '/api/contacts', table: 'contacts', add: { name: 'QA Tutor', phone: '5550100' }, edit: { phone: '5550101' }, field: 'phone', value: '5550101' },
  { domain: 'recurring_payments', route: '/api/recurring-payments', table: 'recurring_payments', add: { name: 'QA music', amount: 20 }, edit: { amount: 25 }, field: 'amount', value: 25 },
]) {
  test(`wiring: ${s.domain} Concierge create/edit/delete reaches iOS HTTP reads and stays isolated`, async () => {
    await act(s.domain, { action: 'add', ...s.add });
    const row = await new Promise((resolve, reject) => db.db.get(`SELECT id FROM ${s.table} ORDER BY id DESC LIMIT 1`, (e, r) => e ? reject(e) : resolve(r)));
    const first = await owner('GET', s.route);
    assert.equal(first.status, 200);
    assert.ok(first.body.some(r => r.id === row.id), 'tool write visible through app endpoint');
    assert.ok(!(await outsider('GET', s.route)).body.some(r => r.id === row.id), 'other household cannot read');
    const forbidden = await outsider('PUT', `${s.route}/${row.id}`, s.edit);
    assert.ok([403, 404].includes(forbidden.status), `unauthorized update rejected: ${forbidden.status}`);
    await act(s.domain, { action: 'update', id: row.id, ...s.edit });
    const changed = (await owner('GET', s.route)).body.find(r => r.id === row.id);
    assert.equal(String(changed[s.field]), String(s.value));
    await act(s.domain, { action: 'delete', id: row.id });
    assert.ok(!(await owner('GET', s.route)).body.some(r => r.id === row.id));
  });
}
test('wiring: calendar recurrence and reverse API edit are visible to Concierge', async () => {
  const saved = await act('calendar', { action: 'add', title: 'QA violin', appointment_date: '2026-09-22', appointment_time: '09:20', recurrence_rule: 'weekly', recurrence_end: '2026-10-06', location: '123 Fictional Street' });
  const read = await owner('GET', `/api/appointments/id/${saved.id}`);
  assert.equal(read.status, 200); assert.equal(read.body.appointment_time, '09:20');
  assert.equal((await owner('PUT', `/api/appointments/${saved.id}`, { appointment_time: '10:20' })).status, 200);
  const events = await act('calendar', { action: 'list', date_from: '2026-09-22', date_to: '2026-10-07' });
  const occurrences = events.filter(e => e.id === saved.id);
  assert.equal(occurrences.length, 3);
  assert.ok(occurrences.every(e => e.time === '10:20'), JSON.stringify(occurrences));
  await act('calendar', { action: 'delete', id: saved.id });
  assert.equal((await owner('GET', `/api/appointments/id/${saved.id}`)).status, 404);
});
test('wiring: automatic briefs stay cloud-free even when a client requests AI', async () => {
  for (const route of ['/api/concierge/brief', '/api/concierge/brief?skipAI=false&refresh=1']) {
    const r = await owner('GET', route);
    assert.equal(r.status, 200); assert.equal(r.body.ai_enabled, false);
    assert.ok(Array.isArray(r.body.cards));
  }
});
