#!/usr/bin/env node
// Opt-in paid-provider acceptance using ONLY synthetic records in a temporary
// SQLite DB. Real tools run; reads use the same HTTP endpoints as the iOS app.
// No live accounts, emails, billing or APNs are involved.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
if (!process.env.ANTHROPIC_API_KEY) { console.error('ANTHROPIC_API_KEY is required'); process.exit(1); }
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'kinrows-live-wiring-'));
process.env.FAMILY_DB_DIR = dir;
const FamilyDB = require('../database');
const subscription = require('../services/subscription');
const base = 'http://127.0.0.1:3973';
let server, db, cookie = '';
async function api(method, route, body) {
  const res = await fetch(base + route, { method, headers: { 'Content-Type': 'application/json', Cookie: cookie }, body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(120000) });
  if (res.headers.get('set-cookie')) cookie = res.headers.get('set-cookie').split(';')[0];
  const data = await res.json();
  assert.equal(res.status, 200, `${route}: ${JSON.stringify(data)}`);
  return data;
}
(async () => {
  const results = [];
  try {
    server = spawn(process.execPath, ['dashboard.js'], { cwd: path.join(__dirname, '..'), stdio: 'ignore', env: { ...process.env, PORT: '3973', FAMILY_DB_DIR: dir, NODE_ENV: 'test', SESSION_SECRET: 'synthetic-live-qa', RESEND_API_KEY: '', STRIPE_SECRET_KEY: '', APNS_KEY_ID: '' } });
    let healthy = false;
    for (let n = 0; n < 100; n++) { try { if ((await fetch(base + '/healthz')).ok) { healthy = true; break; } } catch {} await new Promise(r => setTimeout(r, 100)); }
    assert.ok(healthy, 'isolated live QA server started');
    const registered = await api('POST', '/api/auth/register', { username: 'synthetic_live_qa', name: 'Morgan QA', password: 'synthetic-fixture-only' });
    db = new FamilyDB();
    await subscription.grantCompForGroup(db, registered.household.id, registered.user.id);
    const packing = await api('POST', '/api/lists', { name: 'QA Packing' });
    const cases = [
      { name: 'saved address create', say: 'Save a household address named QA Cabin at 10 Fictional Road, Halifax. Do it now.', verify: async () => (await api('GET', '/api/addresses')).some(r => r.name === 'QA Cabin' && r.address.includes('10 Fictional Road')) },
      { name: 'list pin after lookup', say: 'Pin the existing QA Packing list to the top of my lists. This is a list pin, not a Home card.', verify: async () => !!(await api('GET', '/api/lists')).find(r => r.id === packing.id && r.pinned === 1) },
      { name: 'private routine creation', say: 'Create a private custom routine named QA Daily Reading. Start today. Do it now; do not share it.', verify: async () => (await api('GET', '/api/routines')).some(r => r.name === 'QA Daily Reading' && r.shared_scope === 'private') },
      { name: 'feed post', say: 'Post this exact message to our household feed now: QA picnic moved to Saturday.', verify: async () => (await api('GET', `/api/groups/${registered.household.id}/feed`)).some(r => r.body === 'QA picnic moved to Saturday.') },
      { name: 'memory create and selective deletion', say: 'Remember that the QA spare key is in the blue box.', followup: 'Forget the fact you just saved about the QA spare key. I confirm deleting that remembered fact.', verify: async () => !(await api('GET', '/api/concierge/memory')).some(r => /spare key/i.test(r.content)), intermediate: async () => (await api('GET', '/api/concierge/memory')).some(r => /spare key/i.test(r.content)) },
    ];
    const handoffs = ['receipt', 'health', 'groups'].map(workflow => ({
      name: `native ${workflow} handoff`,
      say: { receipt: 'I want to take a photo of a receipt and review it before saving. Open the receipt scanner for me.', health: 'Open the HealthKit permission and health sync workflow in the app for me.', groups: 'Open the family group membership and invitations workflow for me.' }[workflow],
      native: true, verify: async chat => chat.actions?.some(a => a.tool === 'open_workflow' && a.workflow === workflow),
    }));
    for (const c of (process.argv.includes('--handoffs-only') ? handoffs : cases)) {
      try {
        let chat = await api('POST', '/api/concierge/chat', { message: c.say, native_handoffs: c.native === true });
        const actions = [...(chat.actions || [])];
        if (c.intermediate) assert.ok(await c.intermediate(), 'initial state was actually persisted');
        if (c.followup) { chat = await api('POST', '/api/concierge/chat', { message: c.followup, conversation_id: chat.conversation_id }); actions.push(...(chat.actions || [])); }
        assert.ok(await c.verify(chat), `persisted native HTTP state disagrees with response: ${chat.reply}`);
        assert.ok(actions.length, 'successful writes publish refresh actions');
        if (c.native) {
          const history = await api('GET', `/api/concierge/conversations/${chat.conversation_id}/messages`);
          assert.deepEqual(history.at(-1).actions, chat.actions, 'resuming the conversation preserves its buttons');
          assert.match(chat.reply, /Tap .* to open the workflow/);
          assert.doesNotMatch(chat.reply, /is now open|are now open/);
        }

        const row = { scenario: c.name, status: 'PASS', actions: actions.map(a => a.tool) }; results.push(row); console.log(JSON.stringify(row));
      } catch (e) { const row = { scenario: c.name, status: 'FAIL', error: e.message }; results.push(row); console.log(JSON.stringify(row)); }
    }
    console.log(JSON.stringify({ passed: results.filter(r => r.status === 'PASS').length, total: results.length }));
    if (results.some(r => r.status !== 'PASS')) process.exitCode = 1;
  } catch (e) { console.error(e.message); process.exitCode = 1; }
  finally { server?.kill('SIGKILL'); db?.close(); fs.rmSync(dir, { recursive: true, force: true }); }
})();
