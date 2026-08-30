// List endpoints must not inline base64 avatars/photos. Dedicated avatar
// GETs still return the image. JSON GETs gzip when asked. Run: npm test

const { test, before, after } = require('node:test');
const assert = require('node:assert');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('path');
const http = require('node:http');
const zlib = require('node:zlib');

const PORT = 3978;
const BASE = `http://127.0.0.1:${PORT}`;
let server;
let tmpDir;

// Tiny valid JPEG so the blob is real, not an empty string the SQL treats as missing.
const JPEG_B64 = Buffer.from([
  0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01,
  0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xff, 0xdb, 0x00, 0x43,
  0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08, 0x07, 0x07, 0x07, 0x09,
  0x09, 0x08, 0x0a, 0x0c, 0x14, 0x0d, 0x0c, 0x0b, 0x0b, 0x0c, 0x19, 0x12,
  0x13, 0x0f, 0x14, 0x1d, 0x1a, 0x1f, 0x1e, 0x1d, 0x1a, 0x1c, 0x1c, 0x20,
  0x24, 0x2e, 0x27, 0x20, 0x22, 0x2c, 0x23, 0x1c, 0x1c, 0x28, 0x37, 0x29,
  0x2c, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1f, 0x27, 0x39, 0x3d, 0x38, 0x32,
  0x3c, 0x2e, 0x33, 0x34, 0x32, 0xff, 0xc0, 0x00, 0x0b, 0x08, 0x00, 0x01,
  0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xff, 0xc4, 0x00, 0x14, 0x00, 0x01,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x03, 0xff, 0xc4, 0x00, 0x14, 0x10, 0x01, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0xff, 0xda, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3f, 0x00,
  0x7f, 0x3f, 0xff, 0xd9,
]).toString('base64');

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
    return { status: res.status, body: json, cookie };
  };
}

function rawGet(pathname, cookie, acceptEncoding) {
  return new Promise((resolve, reject) => {
    http.get({
      hostname: '127.0.0.1',
      port: PORT,
      path: pathname,
      headers: {
        ...(cookie ? { Cookie: cookie } : {}),
        ...(acceptEncoding ? { 'Accept-Encoding': acceptEncoding } : {}),
      },
    }, (res) => {
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => resolve({
        status: res.statusCode,
        encoding: res.headers['content-encoding'] || '',
        body: Buffer.concat(chunks),
      }));
    }).on('error', reject);
  });
}

function assertNoInlineImage(obj, label) {
  const raw = JSON.stringify(obj);
  assert.doesNotMatch(raw, /data:image/, `${label} must not contain a data:image URI`);
  assert.doesNotMatch(raw, /profile_image/, `${label} must not include profile_image`);
  assert.doesNotMatch(raw, /partner_image/, `${label} must not include partner_image`);
  assert.doesNotMatch(raw, /image_data/, `${label} must not include image_data`);
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
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'fl-slim-'));
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

test('conversations, groups, and members omit image blobs and expose has_avatar', async () => {
  const a = makeClient();
  const ra = await a('POST', '/api/auth/register', {
    username: 'slim_a', password: 'password123', name: 'Slim A',
  });
  assert.equal(ra.status, 200, JSON.stringify(ra.body));
  const invite = ra.body.household.invite_code;
  const aId = ra.body.user.id;

  const put = await a('PUT', '/api/users/me/avatar', { image: JPEG_B64 });
  assert.equal(put.status, 200, JSON.stringify(put.body));

  const b = makeClient();
  const rb = await b('POST', '/api/auth/register', {
    username: 'slim_b', password: 'password123', name: 'Slim B', invite_code: invite,
  });
  assert.equal(rb.status, 200, JSON.stringify(rb.body));
  const bId = rb.body.user.id;

  const dm = await a('POST', '/api/messages', {
    recipient_id: bId, text: 'hi', image_data: JPEG_B64,
  });
  assert.equal(dm.status, 200, JSON.stringify(dm.body));

  const groups = await a('GET', '/api/groups');
  assert.equal(groups.status, 200);
  assertNoInlineImage(groups.body, 'GET /api/groups');
  const hh = (groups.body || []).find((g) => g.group_type === 'household');
  assert.ok(hh, 'household group present');
  assert.ok(hh.has_avatar === 0 || hh.has_avatar === 1, 'groups has_avatar is 0/1');

  const members = await a('GET', `/api/groups/${hh.id}/members`);
  assert.equal(members.status, 200);
  assertNoInlineImage(members.body, 'GET /api/groups/:id/members');
  const me = (members.body || []).find((m) => m.user_id === aId);
  assert.ok(me, 'caller is a member');
  assert.equal(me.has_avatar, 1, 'uploader has_avatar=1');
  const peer = (members.body || []).find((m) => m.user_id === bId);
  assert.ok(peer, 'invitee is a member');
  assert.equal(peer.has_avatar, 0, 'peer without photo has_avatar=0');

  const convos = await a('GET', '/api/messages');
  assert.equal(convos.status, 200);
  assertNoInlineImage(convos.body, 'GET /api/messages');
  assert.ok(Array.isArray(convos.body) && convos.body.length >= 1, 'conversation row present');
  const thread = convos.body.find((c) => c.partner_id === bId);
  assert.ok(thread, 'thread with B');
  assert.equal(thread.has_avatar, 0);
  assert.equal(thread.has_image, 1, 'latest message was a photo but blob is not inlined');

  const avatar = await a('GET', `/api/users/${aId}/avatar`);
  assert.equal(avatar.status, 200);
  assert.equal(avatar.body.image, JPEG_B64, 'dedicated avatar GET still returns the image');

  const outsider = makeClient();
  await outsider('POST', '/api/auth/register', {
    username: 'slim_x', password: 'password123', name: 'Outsider',
  });
  const stolen = await outsider('GET', `/api/users/${aId}/avatar`);
  assert.ok([403, 404].includes(stolen.status), `cross-household avatar blocked (got ${stolen.status})`);
});

test('JSON GETs gzip when the client asks; uncompressed when they do not', async () => {
  const c = makeClient();
  const reg = await c('POST', '/api/auth/register', {
    username: 'slim_gz', password: 'password123', name: 'Gzip User',
  });
  assert.equal(reg.status, 200);
  const cookie = reg.cookie;
  assert.ok(cookie, 'session cookie');

  const plain = await rawGet('/api/tasks', cookie, 'identity');
  assert.equal(plain.status, 200);
  assert.equal(plain.encoding, '');
  const parsed = JSON.parse(plain.body.toString('utf8'));
  assert.ok(Array.isArray(parsed), 'uncompressed JSON array');

  const gz = await rawGet('/api/tasks', cookie, 'gzip');
  assert.equal(gz.status, 200);
  assert.equal(gz.encoding, 'gzip');
  const inflated = zlib.gunzipSync(gz.body).toString('utf8');
  assert.deepEqual(JSON.parse(inflated), parsed);
});

test('receipt scan rejects a missing image before invoking the AI provider', async () => {
  const c = makeClient();
  const reg = await c('POST', '/api/auth/register', {
    username: 'slim_scan', password: 'password123', name: 'Scan User',
  });
  assert.equal(reg.status, 200);

  const response = await c('POST', '/api/receipts/scan', {});
  assert.equal(response.status, 400);
  assert.equal(response.body.error, 'Receipt image is required');
});
