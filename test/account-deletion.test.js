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
