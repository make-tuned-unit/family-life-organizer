// Bounded concurrency smoke test for the stateless MCP request path.

const { test, before, after } = require('node:test');
const assert = require('node:assert');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const PORT = 4004;
const BASE = `http://127.0.0.1:${PORT}`;
let server, tmpDir, key;

async function waitForHealth() {
  for (let attempt = 0; attempt < 150; attempt++) {
    try { if ((await fetch(BASE + '/healthz')).ok) return; } catch {}
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  throw new Error('server did not become healthy');
}

before(async () => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'fl-mcp-load-'));
  server = spawn('node', ['dashboard.js'], {
    cwd: path.join(__dirname, '..'),
    env: { ...process.env, PORT: String(PORT), FAMILY_DB_DIR: tmpDir, SESSION_SECRET: 'test', NODE_ENV: 'test', ANTHROPIC_API_KEY: '', ADMIN_USER_IDS: '1' },
    stdio: 'ignore',
  });
  await waitForHealth();
  let cookie = '';
  const call = async (pathname, body) => {
    const response = await fetch(BASE + pathname, {
      method: 'POST', headers: { 'Content-Type': 'application/json', ...(cookie ? { Cookie: cookie } : {}) },
      body: JSON.stringify(body),
    });
    const sc = response.headers.get('set-cookie'); if (sc) cookie = sc.split(';')[0];
    return { status: response.status, body: await response.json() };
  };
  const account = await call('/api/auth/register', { username: 'mcp_load', password: 'password123', name: 'MCP Load' });
  await call('/api/admin/comp', { group_id: account.body.household.id, action: 'grant' });
  key = (await call('/api/developer/keys', { name: 'Load', scope: 'read' })).body.key;
});

after(() => {
  if (server) server.kill('SIGKILL');
  if (tmpDir) fs.rmSync(tmpDir, { recursive: true, force: true });
});

test('40 concurrent stateless MCP requests complete without cross-talk or failures', async () => {
  const started = Date.now();
  const responses = await Promise.all(Array.from({ length: 40 }, async (_, index) => {
    const method = index % 3 === 0 ? 'resources/list' : index % 3 === 1 ? 'prompts/list' : 'tools/list';
    const response = await fetch(BASE + '/v1/mcp', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${key}` },
      body: JSON.stringify({ jsonrpc: '2.0', id: index + 1, method }),
    });
    return { status: response.status, body: await response.json(), id: index + 1 };
  }));
  assert.ok(responses.every(response => response.status === 200));
  assert.ok(responses.every(response => response.body.id === response.id && response.body.result));
  assert.ok(Date.now() - started < 10000, 'bounded local concurrency sweep completes within 10 seconds');
});
