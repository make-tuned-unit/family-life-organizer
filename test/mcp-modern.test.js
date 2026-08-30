// Official MCP SDK client against Kinrows' 2026-07-28 protocol path.

const { test, before, after } = require('node:test');
const assert = require('node:assert');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { Client, StreamableHTTPClientTransport } = require('@modelcontextprotocol/client');

const PORT = 4002;
const BASE = `http://127.0.0.1:${PORT}`;
let server, tmpDir, apiKey, client, transport;

function makeWebClient() {
  let cookie = '';
  return async (method, pathname, body) => {
    const res = await fetch(BASE + pathname, {
      method,
      headers: { 'Content-Type': 'application/json', ...(cookie ? { Cookie: cookie } : {}) },
      body: body ? JSON.stringify(body) : undefined,
    });
    const sc = res.headers.get('set-cookie');
    if (sc) cookie = sc.split(';')[0];
    return { status: res.status, body: await res.json() };
  };
}

async function waitForHealth(timeoutMs = 15000) {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    try { if ((await fetch(BASE + '/healthz')).ok) return; } catch {}
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  throw new Error('server did not become healthy');
}

before(async () => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'fl-mcp-modern-'));
  server = spawn('node', ['dashboard.js'], {
    cwd: path.join(__dirname, '..'),
    env: {
      ...process.env, PORT: String(PORT), FAMILY_DB_DIR: tmpDir,
      SESSION_SECRET: 'test', NODE_ENV: 'test', ANTHROPIC_API_KEY: '', ADMIN_USER_IDS: '1',
    },
    stdio: 'ignore',
  });
  await waitForHealth();

  const web = makeWebClient();
  const registered = await web('POST', '/api/auth/register', {
    username: 'mcp_modern', password: 'password123', name: 'Modern Agent User',
  });
  assert.equal(registered.status, 200);
  const groupId = registered.body.household.id;
  assert.equal((await web('POST', '/api/admin/comp', { group_id: groupId, action: 'grant' })).status, 200);
  const key = await web('POST', '/api/developer/keys', { name: 'Official SDK test', scope: 'write' });
  assert.equal(key.status, 201);
  apiKey = key.body.key;

  transport = new StreamableHTTPClientTransport(new URL(BASE + '/v1/mcp'), {
    authProvider: { token: async () => apiKey },
  });
  client = new Client({ name: 'kinrows-regression', version: '1.0.0' }, {
    versionNegotiation: { mode: { pin: '2026-07-28' } },
  });
  await client.connect(transport);
});

after(async () => {
  try { await client?.close(); } catch {}
  if (server) server.kill('SIGKILL');
  if (tmpDir) fs.rmSync(tmpDir, { recursive: true, force: true });
});

test('official v2 client negotiates 2026-07-28 and discovers Kinrows capabilities', async () => {
  assert.equal(client.getNegotiatedProtocolVersion(), '2026-07-28');
  assert.equal(client.getServerVersion().name, 'kinrows');
  const capabilities = client.getServerCapabilities();
  assert.ok(capabilities.tools && capabilities.resources && capabilities.prompts);

  const { tools } = await client.listTools();
  const tasks = tools.find(tool => tool.name === 'tasks');
  assert.ok(tasks);
  assert.equal(tasks.annotations.destructiveHint, true);
  assert.ok(tasks.outputSchema, 'structured output schema advertised');

  const result = await client.callTool({ name: 'tasks', arguments: { action: 'list' } });
  assert.equal(result.isError, false);
  assert.ok(result.structuredContent && Object.hasOwn(result.structuredContent, 'result'));
});

test('official v2 client reads resources, templates, and prompts', async () => {
  const resources = await client.listResources();
  assert.ok(resources.resources.some(resource => resource.uri === 'kinrows://household/snapshot'));

  const templates = await client.listResourceTemplates();
  assert.ok(templates.resourceTemplates.some(template => template.uriTemplate.includes('{section}')));

  const snapshot = await client.readResource({ uri: 'kinrows://household/snapshot/counts' });
  assert.equal(snapshot.contents[0].mimeType, 'application/json');
  assert.equal(JSON.parse(snapshot.contents[0].text).section, 'counts');

  const prompts = await client.listPrompts();
  assert.ok(prompts.prompts.some(prompt => prompt.name === 'morning-brief'));
  const prompt = await client.getPrompt({ name: 'morning-brief', arguments: { focus: 'school pickup' } });
  assert.match(prompt.messages[0].content.text, /school pickup/);
});

test('modern MCP refuses destructive calls without explicit confirmation', async () => {
  const result = await client.callTool({ name: 'tasks', arguments: { action: 'delete', id: 999 } });
  assert.equal(result.isError, true);
  assert.equal(result.structuredContent.result.confirmation_required, true);
});
