const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const sqlite = require('sqlite3');
const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'kinrows-operations-'));
process.env.FAMILY_DB_DIR = directory;
const FamilyDB = require('../database');
const reports = require('../services/contentReports');
const jobs = require('../services/jobs');
const backups = require('../services/backups');
let db;
const sql = (query, params = []) => new Promise((resolve, reject) => db.db.run(query, params, function(error) { error ? reject(error) : resolve(this.lastID); }));
before(async () => { db = new FamilyDB(); await db.initSchema(); await sql("INSERT INTO users (username, password_hash, name) VALUES ('operator_fixture', 'unused', 'Fixture')"); });
after(() => { jobs.resetDrainLock(); db.close(); fs.rmSync(directory, { recursive: true, force: true }); });

test('reports persist with retryable delivery; resolved reports never send stale notifications', async () => {
  const uid = (await reports.get(db, "SELECT id FROM users WHERE username = 'operator_fixture'")).id;
  const first = await reports.create(db, { reporterId: uid, type: 'message', refId: 123, reason: 'QA concern' });
  let result = await jobs.drainOnce({ db, email: { isEmailEnabled: () => true }, sendEmail: async () => ({ ok: false, error: 'temporary outage' }) });
  assert.equal(result.retry, 1);
  assert.equal((await reports.listOpen(db)).length, 1);
  assert.deepEqual(await reports.status(db), { open: 1, overdue: 0, delivery_failed: 0 });
  const stored = await reports.get(db, "SELECT * FROM jobs WHERE kind = 'content_report'");
  assert.deepEqual(JSON.parse(stored.payload), { reportId: first.id });
  await sql("UPDATE jobs SET available_at = datetime('now', '-1 minute')");
  let sent = 0;
  result = await jobs.drainOnce({ db, email: { isEmailEnabled: () => true }, sendEmail: async mail => { sent++; assert.ok(!mail.text.includes('QA concern')); return { ok: true }; } });
  assert.equal(result.done, 1); assert.equal(sent, 1);
  assert.equal((await reports.get(db, 'SELECT payload FROM jobs WHERE id = ?', [stored.id])).payload, '{}');
  await reports.resolve(db, first.id, { decision: 'dismiss', operator: 'QA' });
  assert.equal((await reports.listOpen(db)).length, 0);
  await assert.rejects(reports.resolve(db, first.id, { decision: 'remove', operator: 'QA' }), /already resolved/);
  const second = await reports.create(db, { reporterId: uid, type: 'message', refId: 124, reason: 'QA concern' });
  await reports.resolve(db, second.id, { decision: 'dismiss', operator: 'QA' });
  await jobs.drainOnce({ db, email: { isEmailEnabled: () => true }, sendEmail: async () => { throw new Error('must not deliver a resolved report'); } });
  assert.equal((await reports.get(db, 'SELECT status FROM jobs ORDER BY id DESC LIMIT 1')).status, 'done');
});

test('operator removal erases reported content and photos without exposing an unauthenticated endpoint', async () => {
  const uid = (await reports.get(db, "SELECT id FROM users WHERE username = 'operator_fixture'")).id;
  const message = await sql("INSERT INTO direct_messages (sender_id,recipient_id,text,image_data) VALUES (?,?,'reported content','fixture image')", [uid, uid]);
  const report = await reports.create(db, { reporterId: uid, type: 'message', refId: message, reason: 'QA concern' });
  await assert.rejects(reports.resolve(db, report.id, { decision: 'remove', operator: '' }), /operator/);
  const queued = await db.enqueueJob({ kind: 'push_user', payload: { userId: uid, data: { type: 'message', ref_id: uid }, body: 'reported preview' }, maxAttempts: 5 });
  await reports.resolve(db, report.id, { decision: 'remove', operator: 'QA' });
  assert.equal(await reports.get(db, 'SELECT id FROM jobs WHERE id = ?', [queued.id]), undefined);
  assert.equal(await reports.get(db, 'SELECT id FROM direct_messages WHERE id = ?', [message]), undefined);
  assert.equal((await reports.get(db, 'SELECT decision FROM content_report_reviews WHERE report_id = ?', [report.id])).decision, 'remove');
});

test('dated backup expiry is age-based, isolated to owned files, and snapshot restores SQLite correctly', async () => {
  const target = path.join(directory, 'backups'); fs.mkdirSync(target);
  for (const name of ['family-2026-08-01.db', 'family-2026-09-07.db', 'family-2026-09-08.db', 'unrelated.db']) fs.writeFileSync(path.join(target, name), 'fixture');
  const { destination, removed } = await backups.createSnapshot(db, target, new Date('2026-09-21T00:00:00Z'));
  assert.deepEqual(removed.sort(), ['family-2026-08-01.db', 'family-2026-09-07.db']);
  assert.ok(fs.existsSync(path.join(target, 'family-2026-09-08.db')));
  assert.ok(fs.existsSync(path.join(target, 'unrelated.db')));
  assert.equal(fs.statSync(destination).mode & 0o777, 0o600);
  const copy = new sqlite.Database(destination, sqlite.OPEN_READONLY);
  const read = query => new Promise((resolve, reject) => copy.get(query, (error, row) => error ? reject(error) : resolve(row)));
  try { assert.equal((await read('PRAGMA integrity_check')).integrity_check, 'ok'); assert.equal((await read("SELECT name FROM users WHERE username = 'operator_fixture'")).name, 'Fixture'); }
  finally { await new Promise(resolve => copy.close(resolve)); }
});

test('blocked actors cannot deliver coverage, hosting or rivalry notifications', async () => {
  const push = require('../push');
  let tokenReads = 0;
  const fake = { isUserBlocked: async (recipient, actor) => recipient === 7 && actor === 8, getDeviceTokens: async () => { tokenReads++; return []; } };
  for (const type of ['coverage', 'stay_request', 'stay_confirmed', 'stay_declined', 'rivalry']) {
    const result = await push.pushToUser(fake, 7, 'Private title', 'Private preview', { actor_id: 8, type, ref_id: 123 });
    assert.equal(result.skipped, true);
  }
  assert.equal(tokenReads, 0);
});

test('conversation resume preserves handoff actions without replaying mutations', async () => {
  const uid = (await reports.get(db, "SELECT id FROM users WHERE username = 'operator_fixture'")).id;
  const conversation = await db.createConciergeConversation(uid, null);
  const action = { tool: 'open_workflow', workflow: 'notes', summary: 'Continue in Notes' };
  await db.addConciergeMessage(conversation.id, 'assistant', 'Tap to continue.', [action]);
  const messages = await db.getConciergeMessages(conversation.id);
  assert.deepEqual(messages[0].actions, [action]);
  await db.addConciergeMessage(conversation.id, 'user', 'Next request');
  assert.deepEqual((await db.getConciergeMessages(conversation.id))[1].actions, []);
});
