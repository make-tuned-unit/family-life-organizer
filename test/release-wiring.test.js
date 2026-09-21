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

const get = (sql, args = []) => new Promise((r, j) => db.db.get(sql, args, (e, x) => e ? j(e) : r(x)));
const runSql = (sql, args = []) => new Promise((r, j) => db.db.run(sql, args, function(e) { e ? j(e) : r(this.lastID); }));
async function denied(domain, input, context) {
  const output = await tools.run(domain, context || { ...ctx, userId: (await db.getUserByUsername('qa_other')).id, groupId: await db.getUserHouseholdId((await db.getUserByUsername('qa_other')).id) }, input);
  assert.equal(output.result.ok, false, JSON.stringify(output));
}

test('wiring: saved addresses CRUD, range validation and household guards', async () => {
  const created = await act('addresses', { action: 'add', name: 'QA cabin', address: '10 Fictional Road', lat: 44, lng: -63 });
  assert.ok((await owner('GET', '/api/addresses')).body.some(r => r.id === created.id));
  await denied('addresses', { action: 'update', id: created.id, name: 'Forbidden' });
  await denied('addresses', { action: 'delete', id: created.id });
  await denied('addresses', { action: 'update', id: created.id, lat: 100 }, ctx);
  await act('addresses', { action: 'update', id: created.id, address: '11 Fictional Road' });
  assert.equal((await owner('GET', '/api/addresses')).body.find(r => r.id === created.id).address, '11 Fictional Road');
  await act('addresses', { action: 'delete', id: created.id });
  assert.ok(!(await owner('GET', '/api/addresses')).body.some(r => r.id === created.id));
});

test('wiring: list pin, reorder and attachment lifecycle', async () => {
  const list = (await owner('POST', '/api/lists', { name: 'QA packing' })).body.id;
  const a = (await owner('POST', `/api/lists/${list}/items`, { title: 'Alpha' })).body.id;
  const b = (await owner('POST', `/api/lists/${list}/items`, { title: 'Beta' })).body.id;
  assert.ok(a && b);
  await act('lists', { action: 'pin', list_id: list });
  assert.equal((await get('SELECT pinned FROM lists WHERE id = ?', [list])).pinned, 1);
  await act('lists', { action: 'reorder', list_id: list, ordered_ids: [b, a] });
  assert.equal((await get('SELECT sort_order FROM list_items WHERE id = ?', [b])).sort_order, 0);
  await denied('lists', { action: 'reorder', list_id: list, ordered_ids: [a, b] });
  await act('lists', { action: 'unpin', list_id: list });
  assert.equal((await get('SELECT pinned FROM lists WHERE id = ?', [list])).pinned, 0);
  const event = await act('calendar', { action: 'add', title: 'Packing party', appointment_date: '2026-10-01' });
  await act('calendar', { action: 'attach', appointment_id: event.id, attachment_id: list, attachment_type: 'list' });
  const attached = await act('calendar', { action: 'attachments', appointment_id: event.id });
  assert.equal(attached[0].attachment_id, list);
  assert.deepEqual((await owner('GET', `/api/appointments/${event.id}/attachments`)).body, attached);
  await denied('calendar', { action: 'attachments', appointment_id: event.id });
  await denied('calendar', { action: 'detach', appointment_id: event.id, attachment_id: attached[0].id });
  await act('calendar', { action: 'detach', appointment_id: event.id, attachment_id: attached[0].id });
  assert.equal((await owner('GET', `/api/appointments/${event.id}/attachments`)).body.length, 0);
});

test('wiring: routine lifecycle, private sharing, corrected sleep and calendar occurrences', async () => {
  const member = await db.getUserByUsername('qa_other');
  await runSql('INSERT OR IGNORE INTO group_members (group_id, user_id, role) VALUES (?, ?, ?)', [ctx.groupId, member.id, 'member']);
  const memberCtx = { ...ctx, userId: member.id };
  try {
    const r = await act('routines', { action: 'create', name: 'QA sleep', routine_type: 'baby_sleep', subject_name: 'Child', config: { calendar_keyword: 'Packing' } });
    assert.equal((await owner('GET', `/api/routines/${r.id}`)).status, 200);
    await denied('routines', { action: 'get', routine_id: r.id }, memberCtx);
    await act('routines', { action: 'update', id: r.id, name: 'QA revised sleep' });
    assert.equal((await db.getRoutineById(r.id)).name, 'QA revised sleep');
    await act('routines', { action: 'share', id: r.id, shared: true });
    assert.equal((await tools.run('routines', memberCtx, { action: 'get', routine_id: r.id })).result.id, r.id);
    await denied('routines', { action: 'share', id: r.id, shared: false }, memberCtx);
    await denied('routines', { action: 'delete', id: r.id }, memberCtx);
    const e = await act('routines', { action: 'log_entry', routine_id: r.id, entry_type: 'sleep', date: '2026-09-21' });
    await act('routines', { action: 'update_entry', routine_id: r.id, entry_id: e.id, start_time: '23:00', end_time: '06:00', wake_count: 2 });
    const entries = (await owner('GET', `/api/routines/${r.id}/entries`)).body;
    assert.equal(JSON.parse(entries.find(x => x.id === e.id).value).duration_minutes, 420);
    assert.deepEqual(await act('routines', { action: 'occurrences', id: r.id }), (await owner('GET', `/api/routines/${r.id}/occurrences`)).body);
    const other = await act('routines', { action: 'create', name: 'Other routine', routine_type: 'custom' });
    await denied('routines', { action: 'delete_entry', routine_id: other.id, entry_id: e.id }, ctx);
    await act('routines', { action: 'delete_entry', routine_id: r.id, entry_id: e.id });
    assert.equal((await owner('GET', `/api/routines/${r.id}/entries`)).body.length, 0);
    await act('routines', { action: 'share', id: r.id, shared: false });
    assert.equal(await get("SELECT id FROM feed_posts WHERE reference_type = 'routine' AND reference_id = ?", [r.id]), undefined);
    await act('routines', { action: 'delete', id: r.id });
    assert.equal((await owner('GET', `/api/routines/${r.id}`)).status, 404);
  } finally { await runSql('DELETE FROM group_members WHERE group_id = ? AND user_id = ?', [ctx.groupId, member.id]); }
});

test('wiring: feed discussion and author-only deletion', async () => {
  const p = await act('feed', { action: 'post', title: 'QA feed', body: 'An update' });
  await act('feed', { action: 'react', post_id: p.id, reaction_type: 'like' });
  await act('feed', { action: 'comment', post_id: p.id, text: 'Comment' });
  assert.ok((await act('feed', { action: 'list' })).some(x => x.id === p.id));
  assert.deepEqual(await act('feed', { action: 'reactions', post_id: p.id }), (await owner('GET', `/api/feed/${p.id}/reactions`)).body);
  assert.deepEqual(await act('feed', { action: 'comments', post_id: p.id }), (await owner('GET', `/api/feed/${p.id}/comments`)).body);
  for (const action of ['reactions', 'comments', 'delete', 'unreact']) await denied('feed', { action, post_id: p.id });
  await act('feed', { action: 'unreact', post_id: p.id });
  assert.equal((await owner('GET', `/api/feed/${p.id}/reactions`)).body.length, 0);
  await act('feed', { action: 'delete', post_id: p.id });
  assert.ok(!(await owner('GET', `/api/groups/${ctx.groupId}/feed`)).body.some(x => x.id === p.id));
});

test('wiring: message reads require shared membership and mark only the caller inbox', async () => {
  const member = await db.getUserByUsername('qa_other');
  await runSql('INSERT OR IGNORE INTO group_members (group_id, user_id, role) VALUES (?, ?, ?)', [ctx.groupId, member.id, 'member']);
  try {
    const m = await db.sendMessage({ sender_id: member.id, recipient_id: ctx.userId, text: 'Message fixture' });
    assert.deepEqual(await act('messages', { action: 'list', partner_id: member.id }), (await owner('GET', `/api/messages/${member.id}`)).body);
    assert.ok((await act('messages', { action: 'conversations' })).some(x => x.partner_id === member.id));
    await act('messages', { action: 'read', partner_id: member.id });
    assert.ok((await get('SELECT read_at FROM direct_messages WHERE id = ?', [m.id])).read_at);
  } finally { await runSql('DELETE FROM group_members WHERE group_id = ? AND user_id = ?', [ctx.groupId, member.id]); }
  await denied('messages', { action: 'list', partner_id: member.id }, ctx);
  assert.ok(!(await act('messages', { action: 'conversations' })).some(x => x.partner_id === member.id));
});

test('wiring: decisions, rivalry results, budget stats, expenses and memory', async () => {
  const d = (await owner('POST', '/api/decisions', { title: 'QA poll', decision_type: 'poll', poll_options: ['A', 'B'] })).body.id;
  await act('decisions', { action: 'update', id: d, title: 'Revised poll' });
  assert.equal((await owner('GET', `/api/decisions/${d}`)).body.title, 'Revised poll');
  for (const [action, endpoint] of [['reactions', 'reactions'], ['comments', 'comments']]) {
    assert.deepEqual(await act('decisions', { action, id: d }), (await owner('GET', `/api/decisions/${d}/${endpoint}`)).body);
    await denied('decisions', { action, id: d });
  }
  const r = (await act('rivalries', { action: 'create', title: 'QA challenge', participants: ['QA Owner', 'QA Other'], challenge_type: 'steps', start_date: '2026-09-21', end_date: '2026-09-28' })).id;
  await act('rivalries', { action: 'update', id: r, title: 'Revised challenge', participants: ['QA Owner', 'QA Other'] });
  assert.equal((await owner('GET', '/api/rivalries')).body.find(x => x.id === r).title, 'Revised challenge');
  assert.deepEqual(await act('rivalries', { action: 'entries', id: r }), (await owner('GET', `/api/rivalries/${r}/entries`)).body);
  assert.deepEqual(await act('rivalries', { action: 'leaderboard' }), (await owner('GET', '/api/rivalries/leaderboard')).body);
  await denied('rivalries', { action: 'update', id: r, title: 'Forbidden' });
  assert.deepEqual(await act('budget', { action: 'stats', months: 6 }), (await owner('GET', '/api/budget/stats?months=6')).body);
  const p = (await owner('POST', '/api/projects', { name: 'QA project', budget: 100 })).body.id;
  assert.deepEqual(await act('projects', { action: 'expenses', project_id: p }), (await owner('GET', `/api/projects/${p}/expenses`)).body);
  await denied('projects', { action: 'expenses', project_id: p });
  const memory = await runSql('INSERT INTO concierge_memory (group_id, user_id, content) VALUES (?, ?, ?)', [ctx.groupId, ctx.userId, 'QA remembered fact']);
  assert.ok((await act('memory', { action: 'list' })).some(x => x.id === memory));
  await denied('memory', { action: 'delete', id: memory });
  await act('memory', { action: 'delete', id: memory });
  assert.ok(!(await act('memory', { action: 'list' })).some(x => x.id === memory));
});

test('wiring: hosting request/response uses shared state and exactly one pair of calendar events', async () => {
  const host = await db.getUserByUsername('qa_other');
  const hostCtx = { ...ctx, userId: host.id, userName: host.name, groupId: await db.getUserHouseholdId(host.id) };
  const itinerary = await db.createItinerary({ title: 'QA visit', traveler_id: ctx.userId, traveler_name: ctx.userName, group_id: ctx.groupId, start_date: '2026-10-01', end_date: '2026-10-03' });
  const stay = await db.addItineraryStay({ itinerary_id: itinerary.id, host_user_id: host.id, host_name: host.name, check_in: '2026-10-01', check_out: '2026-10-03' });
  await denied('itineraries', { action: 'request_stay', stay_id: stay.id }, hostCtx);
  await act('itineraries', { action: 'request_stay', stay_id: stay.id });
  const pending = (await tools.run('itineraries', hostCtx, { action: 'pending_requests' })).result;
  assert.ok(pending.some(x => x.id === stay.id));
  assert.deepEqual(pending, (await outsider('GET', '/api/stays/pending')).body);
  await denied('itineraries', { action: 'respond_stay', stay_id: stay.id, approved: true }, ctx);
  const responses = await Promise.all([tools.run('itineraries', hostCtx, { action: 'respond_stay', stay_id: stay.id, approved: true }), tools.run('itineraries', hostCtx, { action: 'respond_stay', stay_id: stay.id, approved: true })]);
  assert.equal(responses.filter(r => r.result.ok).length, 1);
  const saved = await db.getItineraryStayById(stay.id);
  assert.equal(saved.status, 'confirmed');
  assert.equal((await owner('GET', `/api/appointments/id/${saved.calendar_event_id}`)).status, 200);
  assert.equal((await outsider('GET', `/api/appointments/id/${saved.host_calendar_event_id}`)).status, 200);
  assert.equal((await get('SELECT COUNT(*) n FROM appointments WHERE id IN (?, ?)', [saved.calendar_event_id, saved.host_calendar_event_id])).n, 2);
  await denied('itineraries', { action: 'request_stay', stay_id: stay.id }, ctx);
  assert.deepEqual(await act('itineraries', { action: 'expenses', itinerary_id: itinerary.id }), (await owner('GET', `/api/itineraries/${itinerary.id}/expenses`)).body);
  await denied('itineraries', { action: 'expenses', itinerary_id: itinerary.id }, hostCtx);
});

test('wiring: coverage detail checks recipient identity and never returns invite tokens to the model', async () => {
  const request = await db.createCoverageRequest({ requester_id: ctx.userId, reason: 'QA coverage', child_name: 'Child' });
  const detail = await act('coverage', { action: 'detail', id: request.id });
  assert.equal(detail.id, request.id);
  assert.equal((await owner('GET', `/api/coverage/${request.id}`)).status, 200);
  await denied('coverage', { action: 'detail', id: request.id });
  assert.deepEqual(await act('coverage', { action: 'blocks', date_from: '2026-09-01', date_to: '2026-10-01' }), (await owner('GET', '/api/coverage/blocks?date_from=2026-09-01&date_to=2026-10-01')).body);
  assert.ok(detail.recipients.every(r => !Object.hasOwn(r, 'invite_token')));
});

test('safety: blocking holds across native HTTP, Concierge/history, images, unread counts and notifications', async () => {
  const other = await db.getUserByUsername('qa_other');
  const otherCtx = { ...ctx, userId: other.id, userName: other.name };
  await runSql('INSERT OR IGNORE INTO group_members (group_id, user_id, role) VALUES (?, ?, ?)', [ctx.groupId, other.id, 'member']);
  try {
    const dm = await db.sendMessage({ sender_id: other.id, recipient_id: ctx.userId, text: 'Safety fixture secret', image_data: 'data:image/png;base64,iVBORw0KGgo=' });
    const post = await db.addFeedPost({ group_id: ctx.groupId, author_id: other.id, post_type: 'photo', title: 'Safety fixture', body: 'Safety fixture secret', photo_url: 'data:image/png;base64,iVBORw0KGgo=' });
    assert.equal((await owner('POST', `/api/users/${other.id}/block`, {})).status, 200);
    assert.ok((await owner('GET', '/api/blocked-users')).body.some(x => x.id === other.id));
    for (const [a, b] of [[owner, other.id], [outsider, ctx.userId]]) {
      assert.equal((await a('GET', `/api/messages/${b}`)).status, 403);
      assert.equal((await a('POST', '/api/messages', { recipient_id: b, text: 'Should be blocked' })).status, 403);
    }
    assert.equal((await owner('GET', `/api/messages/${other.id}/${dm.id}/image`)).status, 404);
    assert.equal((await owner('GET', `/api/feed/${post.id}/photo`)).status, 404);
    assert.ok(!(await owner('GET', `/api/groups/${ctx.groupId}/feed`)).body.some(x => x.id === post.id));
    assert.ok(!(await db.getActivityFeed(100, ctx.userId)).some(x => x.ref_id === post.id && x.feed_type === 'post'));
    assert.equal((await owner('GET', '/api/messages/unread-count')).body.count, 0);
    for (const action of ['list', 'read']) await denied('messages', { action, partner_id: other.id }, ctx);
    await denied('send_message', { to: other.name, text: 'Blocked via model' }, ctx);
    await denied('feed', { action: 'comments', post_id: post.id }, ctx);
    const history = await tools.run('history', ctx, { action: 'search', query: 'Safety fixture secret', source: 'messages' });
    assert.equal(history.result.error, undefined, JSON.stringify(history));
    assert.ok(!JSON.stringify(history.result).includes('Safety fixture secret'), JSON.stringify(history));
    const push = require('../push');
    let tokenReads = 0;
    const fakeDb = { isUserBlocked: db.isUserBlocked.bind(db), getDeviceTokens: async () => { tokenReads++; return []; }, getGroupMembers: async () => [{ user_id: other.id }, { user_id: ctx.userId }], getDeviceTokensForUsers: async ids => { assert.ok(!ids.includes(ctx.userId)); return []; } };
    await push.pushToUser(fakeDb, ctx.userId, 'Message', 'Hidden', { type: 'message', ref_id: other.id }, { throwOnError: true });
    assert.equal(tokenReads, 0, 'blocked message never reaches APNs token lookup');
    await push.pushToGroup(fakeDb, ctx.groupId, other.id, 'Post', 'Hidden', {}, { throwOnError: true });
    assert.ok((await tools.run('messages', ctx, { action: 'blocked' })).result.some(x => x.id === other.id));
    await act('messages', { action: 'unblock', user_id: other.id });
    assert.equal((await owner('GET', `/api/messages/${other.id}`)).status, 200);
    await tools.run('messages', otherCtx, { action: 'block', user_id: ctx.userId });
    await act('messages', { action: 'unblock', user_id: other.id });
    assert.equal((await owner('GET', `/api/messages/${other.id}`)).status, 403, 'cannot remove someone else’s block');
  } finally {
    await db.setUserBlocked(ctx.userId, other.id, false);
    await db.setUserBlocked(other.id, ctx.userId, false);
    await runSql('DELETE FROM group_members WHERE group_id = ? AND user_id = ?', [ctx.groupId, other.id]);
  }
});

test('safety: prohibited threats are rejected consistently by API and Concierge before persistence', async () => {
  const before = (await get('SELECT COUNT(*) n FROM feed_posts')).n;
  const rejected = await owner('POST', `/api/groups/${ctx.groupId}/feed`, { body: 'I will kill you' });
  assert.equal(rejected.status, 422);
  await denied('feed', { action: 'post', body: 'I will kill you' }, ctx);
  assert.equal((await get('SELECT COUNT(*) n FROM feed_posts')).n, before);
  assert.equal((await owner('POST', `/api/groups/${ctx.groupId}/feed`, { body: 'Please remember the school play tonight.' })).status, 200);
});

test('privacy: a legacy private-note attachment never exposes its title or body to household members', async () => {
  const other = await db.getUserByUsername('qa_other');
  await runSql('INSERT OR IGNORE INTO group_members (group_id, user_id, role) VALUES (?, ?, ?)', [ctx.groupId, other.id, 'member']);
  try {
    const note = (await owner('POST', '/api/notes', { title: 'Private title', body: 'Private body', shared_scope: 'private' })).body.id;
    const event = await act('calendar', { action: 'add', title: 'Shared event', appointment_date: '2026-10-04' });
    await db.addEventAttachment({ appointment_id: event.id, attachment_type: 'note', attachment_id: note, group_id: ctx.groupId, added_by: ctx.userId });
    const own = (await owner('GET', `/api/appointments/${event.id}/attachments`)).body;
    assert.equal(own[0].title, 'Private title');
    const theirs = (await outsider('GET', `/api/appointments/${event.id}/attachments`)).body;
    assert.ok(!JSON.stringify(theirs).includes('Private title'));
    assert.ok(!JSON.stringify(theirs).includes('Private body'));
    const viaTool = await tools.run('calendar', { ...ctx, userId: other.id }, { action: 'attachments', appointment_id: event.id });
    assert.equal(viaTool.result.error, undefined);
    assert.ok(!JSON.stringify(viaTool).includes('Private body'));
  } finally { await runSql('DELETE FROM group_members WHERE group_id = ? AND user_id = ?', [ctx.groupId, other.id]); }
});

test('Concierge full note reads preserve private and shared visibility', async () => {
  const body = 'Complete note content beyond the preview. '.repeat(30);
  await act('notes', { action: 'add', title: 'Full private note', body });
  const note = await new Promise((resolve, reject) => db.db.get('SELECT id FROM notes WHERE title = ?', ['Full private note'], (e, r) => e ? reject(e) : resolve(r)));
  assert.equal((await act('notes', { action: 'get', id: note.id })).body, body);
  const other = await db.getUserByUsername('qa_other');
  const denied = await tools.run('notes', { ...ctx, userId: other.id }, { action: 'get', id: note.id });
  assert.equal(denied.result.ok, false);
  await act('notes', { action: 'update', id: note.id, shared: true });
  assert.equal((await act('notes', { action: 'get', id: note.id })).body, body);
  assert.equal((await tools.run('notes', { ...ctx, userId: other.id }, { action: 'get', id: note.id })).result.ok, false);
  await db.addGroupMember(ctx.groupId, { user_id: other.id, role: 'member', added_by: ctx.userId });
  assert.equal((await tools.run('notes', { ...ctx, userId: other.id }, { action: 'get', id: note.id })).result.body, body);
  await act('notes', { action: 'update', id: note.id, shared: false });
  assert.equal((await tools.run('notes', { ...ctx, userId: other.id }, { action: 'get', id: note.id })).result.ok, false, 'privatising retracts access immediately');
});

test('Native workflow handoffs require user action and never report a saved mutation', async () => {
  for (const workflow of ['receipt', 'cook', 'calendar', 'trips', 'health', 'groups', 'messages', 'notes', 'routines', 'history']) {
    const legacy = await tools.run('get_workflow_handoff', ctx, { workflow });
    assert.equal(legacy.result.status, 'requires_user_action');
    assert.equal(legacy.action, undefined, 'old clients receive instructions without a saved-changes card');
    const native = await tools.run('get_workflow_handoff', { ...ctx, nativeHandoffs: true }, { workflow });
    assert.equal(native.result.status, 'requires_user_action');
    assert.deepEqual(native.action, { tool: 'open_workflow', workflow, summary: `Continue in ${ { receipt: 'Receipt scanner', cook: 'Cook', calendar: 'Calendar', trips: 'Trips', health: 'Rivalries', groups: 'Family groups', messages: 'Messages', notes: 'Notes', routines: 'Routines', history: 'Conversation history' }[workflow]}` });
  }
  assert.equal((await tools.run('get_workflow_handoff', ctx, { workflow: 'settings' })).result.ok, false);
});
