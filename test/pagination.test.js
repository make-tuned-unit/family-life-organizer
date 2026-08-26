// Bounded list reads: receipts honor limit + keyset cursor; household lists
// never dump an unbounded table. Run: npm test

const { test, before, after } = require('node:test');
const assert = require('node:assert');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const PORT = 3984;
const BASE = `http://127.0.0.1:${PORT}`;
let server;
let tmpDir;

function makeClient() {
  let cookie = '';
  return async (method, pathname, body) => {
    const res = await fetch(BASE + pathname, {
      method,
      headers: {
        'Content-Type': 'application/json',
        ...(cookie ? { Cookie: cookie } : {}),
      },
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
    try {
      if ((await fetch(BASE + '/healthz')).ok) return;
    } catch {}
    await new Promise(r => setTimeout(r, 200));
  }
  throw new Error('server did not become healthy');
}

before(async () => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'fl-page-'));
  server = spawn('node', ['dashboard.js'], {
    cwd: path.join(__dirname, '..'),
    env: {
      ...process.env,
      PORT: String(PORT),
      FAMILY_DB_DIR: tmpDir,
      SESSION_SECRET: 'test-secret',
      NODE_ENV: 'test',
      ANTHROPIC_API_KEY: '',
    },
    stdio: 'ignore',
  });
  await waitForHealth();
});

after(() => {
  if (server) server.kill('SIGKILL');
  if (tmpDir) fs.rmSync(tmpDir, { recursive: true, force: true });
});

test('receipts: limit bounds the page and before_id+before_date returns the next page', async () => {
  const c = makeClient();
  const reg = await c('POST', '/api/auth/register', {
    username: 'page_recv', password: 'password123', name: 'Pager',
  });
  assert.equal(reg.status, 200, 'registers');

  for (let d = 1; d <= 8; d++) {
    const created = await c('POST', '/api/receipts', {
      amount: d, merchant: `Store ${d}`, date: `2026-08-0${d}`, category: 'Groceries',
    });
    assert.equal(created.status, 200, `receipt ${d} created`);
  }

  const unbounded = await c('GET', '/api/receipts');
  assert.equal(unbounded.status, 200);
  assert.equal(unbounded.body.length, 8, 'no-limit still returns the household set (under the 1000 cap)');

  const page1 = await c('GET', '/api/receipts?limit=3');
  assert.equal(page1.status, 200);
  assert.equal(page1.body.length, 3);
  assert.equal(page1.body[0].merchant, 'Store 8');
  assert.equal(page1.body[2].merchant, 'Store 6');

  const last = page1.body[2];
  const page2 = await c('GET', `/api/receipts?limit=3&before_date=${encodeURIComponent(last.date)}&before_id=${last.id}`);
  assert.equal(page2.status, 200);
  assert.equal(page2.body.length, 3);
  assert.equal(page2.body[0].merchant, 'Store 5');
  assert.ok(!page2.body.some(r => r.id === last.id), 'cursor page does not repeat the previous last row');
});

test('notes and pantry reads stay capped (small household still returns everything)', async () => {
  const c = makeClient();
  const reg = await c('POST', '/api/auth/register', {
    username: 'page_notes', password: 'password123', name: 'Noter',
  });
  assert.equal(reg.status, 200);

  const n1 = await c('POST', '/api/notes', { title: 'One', body: 'a' });
  const n2 = await c('POST', '/api/notes', { title: 'Two', body: 'b' });
  assert.equal(n1.status, 200);
  assert.equal(n2.status, 200);

  const notes = await c('GET', '/api/notes');
  assert.equal(notes.status, 200);
  assert.equal(notes.body.length, 2);

  const p = await c('POST', '/api/pantry', { item: 'Milk', location: 'fridge' });
  assert.ok([200, 201].includes(p.status), `pantry add (${p.status})`);
  const pantry = await c('GET', '/api/pantry');
  assert.equal(pantry.status, 200);
  assert.ok(Array.isArray(pantry.body));
  assert.ok(pantry.body.some(x => x.item === 'Milk'));
});
