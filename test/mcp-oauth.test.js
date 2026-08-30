// OAuth 2.1 + PKCE flow used by remote MCP clients.

const { test, before, after } = require('node:test');
const assert = require('node:assert');
const crypto = require('node:crypto');
const { spawn } = require('node:child_process');
const http = require('node:http');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { Client, StreamableHTTPClientTransport } = require('@modelcontextprotocol/client');

const PORT = 4003;
const BASE = `http://127.0.0.1:${PORT}`;
const REDIRECT = 'http://127.0.0.1:48291/callback';
let server, tmpDir, cookie = '';

async function request(method, pathname, body, { form = false, auth, redirect = 'manual' } = {}) {
  const headers = { ...(cookie ? { Cookie: cookie } : {}), ...(auth ? { Authorization: `Bearer ${auth}` } : {}) };
  let payload;
  if (body !== undefined) {
    if (form) { headers['Content-Type'] = 'application/x-www-form-urlencoded'; payload = new URLSearchParams(body); }
    else { headers['Content-Type'] = 'application/json'; payload = JSON.stringify(body); }
  }
  const res = await fetch(BASE + pathname, { method, headers, body: payload, redirect });
  const sc = res.headers.get('set-cookie');
  if (sc) cookie = sc.split(';')[0];
  const text = await res.text();
  let json = null; try { json = JSON.parse(text); } catch {}
  return { status: res.status, body: json, text, location: res.headers.get('location'), headers: res.headers };
}

async function waitForHealth(timeoutMs = 15000) {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    try { if ((await fetch(BASE + '/healthz')).ok) return; } catch {}
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  throw new Error('server did not become healthy');
}

function requestWithHost(host) {
  return new Promise((resolve, reject) => {
    const req = http.request({
      hostname: '127.0.0.1', port: PORT, path: '/v1/mcp', method: 'POST',
      headers: { Host: host, 'Content-Type': 'application/json' },
    }, res => {
      res.resume();
      res.on('end', () => resolve(res.statusCode));
    });
    req.on('error', reject);
    req.end(JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'ping' }));
  });
}

before(async () => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'fl-mcp-oauth-'));
  server = spawn('node', ['dashboard.js'], {
    cwd: path.join(__dirname, '..'),
    env: { ...process.env, PORT: String(PORT), FAMILY_DB_DIR: tmpDir, SESSION_SECRET: 'test', NODE_ENV: 'test', ANTHROPIC_API_KEY: '', ADMIN_USER_IDS: '1' },
    stdio: 'ignore',
  });
  await waitForHealth();
  const registered = await request('POST', '/api/auth/register', { username: 'oauth_user', password: 'password123', name: 'OAuth User' });
  assert.equal(registered.status, 200);
  assert.equal((await request('POST', '/api/admin/comp', { group_id: registered.body.household.id, action: 'grant' })).status, 200);
});

after(() => {
  if (server) server.kill('SIGKILL');
  if (tmpDir) fs.rmSync(tmpDir, { recursive: true, force: true });
});

test('OAuth discovery advertises the MCP resource and secure code flow', async () => {
  const resource = await request('GET', '/.well-known/oauth-protected-resource/v1/mcp');
  assert.equal(resource.status, 200);
  assert.equal(resource.body.resource, BASE + '/v1/mcp');
  assert.deepEqual(resource.body.scopes_supported, ['kinrows:read', 'kinrows:write']);

  const auth = await request('GET', '/.well-known/oauth-authorization-server');
  assert.equal(auth.body.authorization_endpoint, BASE + '/oauth/authorize');
  assert.deepEqual(auth.body.code_challenge_methods_supported, ['S256']);

  const unauth = await fetch(BASE + '/v1/mcp', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'ping' }) });
  assert.equal(unauth.status, 401);
  assert.match(unauth.headers.get('www-authenticate'), /resource_metadata=/);

  assert.equal(await requestWithHost('attacker.example'), 421, 'Host validation runs before bearer authentication');
});

test('dynamic client registration rejects unsafe redirects', async () => {
  const bad = await request('POST', '/oauth/register', { client_name: 'Bad', redirect_uris: ['http://attacker.example/callback'] });
  assert.equal(bad.status, 400);
  assert.equal(bad.body.error, 'invalid_client_metadata');
});

test('authorization code + S256 PKCE issues, refreshes, uses, and revokes MCP tokens', async () => {
  const registration = await request('POST', '/oauth/register', {
    client_name: 'Household Agent', redirect_uris: [REDIRECT], token_endpoint_auth_method: 'none',
  });
  assert.equal(registration.status, 201, registration.text);
  const clientId = registration.body.client_id;
  const verifier = crypto.randomBytes(48).toString('base64url');
  const challenge = crypto.createHash('sha256').update(verifier).digest('base64url');
  const query = new URLSearchParams({
    response_type: 'code', client_id: clientId, redirect_uri: REDIRECT,
    scope: 'kinrows:read kinrows:write', state: 'state-123',
    code_challenge: challenge, code_challenge_method: 'S256',
  });

  const consent = await request('GET', `/oauth/authorize?${query}`);
  assert.equal(consent.status, 200, consent.text);
  assert.match(consent.text, /Household Agent/);
  const nonce = /name="nonce" value="([^"]+)"/.exec(consent.text)?.[1];
  assert.ok(nonce);

  const approved = await request('POST', '/oauth/authorize', { nonce, decision: 'allow' }, { form: true });
  assert.equal(approved.status, 302, approved.text);
  const callback = new URL(approved.location);
  assert.equal(callback.origin + callback.pathname, REDIRECT);
  assert.equal(callback.searchParams.get('state'), 'state-123');
  assert.equal(callback.searchParams.get('iss'), BASE);
  const code = callback.searchParams.get('code');
  assert.ok(code);

  const exchanged = await request('POST', '/oauth/token', {
    grant_type: 'authorization_code', client_id: clientId, redirect_uri: REDIRECT,
    code, code_verifier: verifier,
  }, { form: true });
  assert.equal(exchanged.status, 200, exchanged.text);
  assert.match(exchanged.body.access_token, /^kr_oauth_/);
  assert.match(exchanged.body.refresh_token, /^kr_refresh_/);
  assert.equal(exchanged.body.scope, 'kinrows:read kinrows:write');

  const replay = await request('POST', '/oauth/token', {
    grant_type: 'authorization_code', client_id: clientId, redirect_uri: REDIRECT,
    code, code_verifier: verifier,
  }, { form: true });
  assert.equal(replay.status, 400);
  assert.equal(replay.body.error, 'invalid_grant');

  const me = await request('GET', '/v1/me', undefined, { auth: exchanged.body.access_token });
  assert.equal(me.status, 200, me.text);
  assert.equal(me.body.user.name, 'OAuth User');

  const transport = new StreamableHTTPClientTransport(new URL(BASE + '/v1/mcp'), {
    authProvider: { token: async () => exchanged.body.access_token },
  });
  const client = new Client({ name: 'oauth-regression', version: '1' }, {
    versionNegotiation: { mode: { pin: '2026-07-28' } },
  });
  await client.connect(transport);
  assert.ok((await client.listTools()).tools.some(tool => tool.name === 'tasks'));
  await client.close();

  const refreshed = await request('POST', '/oauth/token', {
    grant_type: 'refresh_token', client_id: clientId,
    refresh_token: exchanged.body.refresh_token, scope: 'kinrows:read',
  }, { form: true });
  assert.equal(refreshed.status, 200, refreshed.text);
  assert.equal(refreshed.body.scope, 'kinrows:read');
  assert.notEqual(refreshed.body.refresh_token, exchanged.body.refresh_token);

  const write = await request('POST', '/v1/tools/tasks', { action: 'add', title: 'Must not write' }, { auth: refreshed.body.access_token });
  assert.equal(write.status, 403);

  assert.equal((await request('POST', '/oauth/revoke', { token: refreshed.body.access_token }, { form: true })).status, 200);
  assert.equal((await request('GET', '/v1/me', undefined, { auth: refreshed.body.access_token })).status, 401);
});
