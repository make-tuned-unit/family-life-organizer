// Weak ETags on read-mostly GETs: /api/home and unread-count must 304 when
// unchanged. Run: npm test

const { test, before, after } = require('node:test');
const assert = require('node:assert');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const PORT = 3976;
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
    return { status: res.status, body: json, headers: res.headers, cookie };
  };
}

async function waitForHealth(timeoutMs = 15000) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    try {
      if ((await fetch(BASE + '/healthz')).ok) return;
    } catch {}
    await new Promise((r) => setTimeout(r, 200));
  }
  throw new Error('server did not become healthy');
}

before(async () => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'fl-etag-'));
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

test('GET /api/home and unread-count emit ETag and honor If-None-Match', async () => {
  const c = makeClient();
  const reg = await c('POST', '/api/auth/register', {
    username: 'etag_user', password: 'password123', name: 'Etag User',
  });
  assert.equal(reg.status, 200, JSON.stringify(reg.body));

  const home1 = await fetch(BASE + '/api/home', {
    headers: { Cookie: reg.cookie },
  });
  assert.equal(home1.status, 200);
  const homeEtag = home1.headers.get('etag');
  assert.ok(homeEtag, 'home response carries ETag');
  assert.match(homeEtag, /^W\/"/);

  const home2 = await fetch(BASE + '/api/home', {
    headers: { Cookie: reg.cookie, 'If-None-Match': homeEtag },
  });
  assert.equal(home2.status, 304);
  assert.equal(await home2.text(), '');

  const unread1 = await fetch(BASE + '/api/messages/unread-count', {
    headers: { Cookie: reg.cookie },
  });
  assert.equal(unread1.status, 200);
  const unreadEtag = unread1.headers.get('etag');
  assert.ok(unreadEtag, 'unread-count carries ETag');

  const unread2 = await fetch(BASE + '/api/messages/unread-count', {
    headers: { Cookie: reg.cookie, 'If-None-Match': unreadEtag },
  });
  assert.equal(unread2.status, 304);
});

test('a write changes /api/home ETag', async () => {
  const c = makeClient();
  const reg = await c('POST', '/api/auth/register', {
    username: 'etag_write', password: 'password123', name: 'Etag Write',
  });
  assert.equal(reg.status, 200, JSON.stringify(reg.body));

  const h1 = await fetch(BASE + '/api/home', { headers: { Cookie: reg.cookie } });
  assert.equal(h1.status, 200);
  const etag1 = h1.headers.get('etag');
  assert.ok(etag1);

  const task = await c('POST', '/api/add', { type: 'task', data: { title: 'ETag bump' } });
  assert.equal(task.status, 200);

  const h2 = await fetch(BASE + '/api/home', { headers: { Cookie: reg.cookie } });
  assert.equal(h2.status, 200);
  const etag2 = h2.headers.get('etag');
  assert.notEqual(etag1, etag2, 'home ETag changes after a write');

  const stale = await fetch(BASE + '/api/home', {
    headers: { Cookie: reg.cookie, 'If-None-Match': etag1 },
  });
  assert.equal(stale.status, 200, 'old ETag no longer 304 after mutation');
});
