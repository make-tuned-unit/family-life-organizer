#!/usr/bin/env node

// Reproducible protocol smoke sweep using the official MCP conformance runner.
// A loopback-only proxy injects a freshly minted test bearer because the
// conformance CLI has no custom-header option. No production auth bypass exists.

const { spawn } = require('node:child_process');
const http = require('node:http');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const APP_PORT = 3994;
const PROXY_PORT = 3995;
const APP = `http://127.0.0.1:${APP_PORT}`;
const scenarios = ['server-initialize', 'ping', 'tools-list', 'resources-list', 'prompts-list'];
const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'fl-mcp-conformance-'));
let appProcess;
let proxy;

async function waitForHealth() {
  for (let attempt = 0; attempt < 150; attempt++) {
    try { if ((await fetch(APP + '/healthz')).ok) return; } catch {}
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  throw new Error('Kinrows conformance server did not become healthy');
}

async function mintKey() {
  let cookie = '';
  const call = async (pathname, body) => {
    const response = await fetch(APP + pathname, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', ...(cookie ? { Cookie: cookie } : {}) },
      body: JSON.stringify(body),
    });
    const setCookie = response.headers.get('set-cookie');
    if (setCookie) cookie = setCookie.split(';')[0];
    const json = await response.json();
    if (!response.ok) throw new Error(`${pathname}: ${response.status} ${JSON.stringify(json)}`);
    return json;
  };
  const account = await call('/api/auth/register', { username: 'mcp_conformance', password: 'password123', name: 'Conformance' });
  await call('/api/admin/comp', { group_id: account.household.id, action: 'grant' });
  return (await call('/api/developer/keys', { name: 'Conformance', scope: 'write' })).key;
}

function startProxy(key) {
  return new Promise((resolve, reject) => {
    proxy = http.createServer(async (incoming, outgoing) => {
      try {
        const chunks = [];
        for await (const chunk of incoming) chunks.push(chunk);
        const headers = { ...incoming.headers, authorization: `Bearer ${key}` };
        delete headers.host;
        delete headers['content-length'];
        const response = await fetch(APP + incoming.url, {
          method: incoming.method,
          headers,
          body: chunks.length ? Buffer.concat(chunks) : undefined,
          redirect: 'manual',
        });
        const responseHeaders = {};
        for (const [name, value] of response.headers) responseHeaders[name] = value;
        outgoing.writeHead(response.status, responseHeaders);
        outgoing.end(Buffer.from(await response.arrayBuffer()));
      } catch (error) {
        outgoing.writeHead(502, { 'Content-Type': 'text/plain' });
        outgoing.end(error.message);
      }
    });
    proxy.once('error', reject);
    proxy.listen(PROXY_PORT, '127.0.0.1', resolve);
  });
}

function runScenario(scenario) {
  return new Promise((resolve, reject) => {
    const command = path.join(__dirname, '..', 'node_modules', '.bin', 'conformance');
    const child = spawn(command, ['server', '--url', `http://127.0.0.1:${PROXY_PORT}/v1/mcp`, '--scenario', scenario], {
      cwd: path.join(__dirname, '..'), stdio: 'inherit',
    });
    child.once('error', reject);
    child.once('exit', code => code === 0 ? resolve() : reject(new Error(`Conformance scenario ${scenario} exited ${code}`)));
  });
}

async function main() {
  appProcess = spawn(process.execPath, ['dashboard.js'], {
    cwd: path.join(__dirname, '..'),
    env: {
      ...process.env, PORT: String(APP_PORT), FAMILY_DB_DIR: tmpDir,
      SESSION_SECRET: 'conformance', NODE_ENV: 'test', ANTHROPIC_API_KEY: '', ADMIN_USER_IDS: '1',
    },
    stdio: ['ignore', 'ignore', 'inherit'],
  });
  await waitForHealth();
  await startProxy(await mintKey());
  for (const scenario of scenarios) await runScenario(scenario);
  console.log(`MCP conformance smoke sweep passed (${scenarios.length} scenarios).`);
}

main().catch(error => {
  console.error(error.stack || error);
  process.exitCode = 1;
}).finally(() => {
  proxy?.close();
  appProcess?.kill('SIGKILL');
  fs.rmSync(tmpDir, { recursive: true, force: true });
});
