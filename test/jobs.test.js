// SQLite outbox: enqueue, drain, retry-with-backoff, and dead-letter.
// Direct FamilyDB tests (no HTTP server) so we can inject push/email handlers.

const { test, before, after, afterEach } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'fl-jobs-'));
process.env.FAMILY_DB_DIR = tmpDir;

const FamilyDB = require('../database');
const jobs = require('../services/jobs');

let db;
const run = (sql, params = []) => new Promise((res, rej) => db.db.run(sql, params, function (e) { e ? rej(e) : res(this); }));
const get = (sql, params = []) => new Promise((res, rej) => db.db.get(sql, params, (e, r) => e ? rej(e) : res(r)));

before(async () => {
  db = new FamilyDB();
  await db.initSchema();
  await new Promise((r) => setTimeout(r, 400));
});

afterEach(async () => {
  jobs.resetDrainLock();
  await run('DELETE FROM jobs');
});

after(() => {
  jobs.resetDrainLock();
  try { db.close(); } catch {}
  fs.rmSync(tmpDir, { recursive: true, force: true });
});

function okPush() {
  const calls = [];
  return {
    calls,
    push: {
      async pushToUser(_db, userId, title, body, data) {
        calls.push({ kind: 'user', userId, title, body, data });
      },
      async pushToGroup(_db, groupId, excludeUserId, title, body, data) {
        calls.push({ kind: 'group', groupId, excludeUserId, title, body, data });
      },
    },
  };
}

test('enqueue rejects unknown kinds', async () => {
  await assert.rejects(() => jobs.enqueue(db, 'not_a_kind', {}, { kick: false }), /unknown job kind/);
});

test('drain runs a push_user job and marks it done', async () => {
  const { calls, push } = okPush();
  const row = await jobs.enqueue(db, 'push_user', {
    userId: 7, title: 'Hi', body: 'There', data: { type: 'message' },
  }, { kick: false });
  const summary = await jobs.drainOnce({ db, push });
  assert.equal(summary.claimed, 1);
  assert.equal(summary.done, 1);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].userId, 7);
  assert.equal(calls[0].title, 'Hi');
  const stored = await db.getJob(row.id);
  assert.equal(stored.status, 'done');
  assert.equal(stored.attempts, 1);
});

test('a failed job retries then dead-letters', async () => {
  const push = {
    async pushToUser() { throw new Error('APNs down'); },
  };
  const row = await jobs.enqueue(db, 'push_user', {
    userId: 1, title: 'T', body: 'B',
  }, { kick: false, maxAttempts: 2 });

  let summary = await jobs.drainOnce({ db, push });
  assert.equal(summary.retry, 1);
  let stored = await db.getJob(row.id);
  assert.equal(stored.status, 'pending');
  assert.equal(stored.attempts, 1);
  assert.match(stored.last_error, /APNs down/);

  await run("UPDATE jobs SET available_at = datetime('now', '-1 second') WHERE id = ?", [row.id]);
  summary = await jobs.drainOnce({ db, push });
  assert.equal(summary.failed, 1);
  stored = await db.getJob(row.id);
  assert.equal(stored.status, 'failed');
  assert.equal(stored.attempts, 2);
});

test('waitlist_welcome sends mail and marks the row welcomed', async () => {
  await db.addWaitlistEntry({ email: 'join@example.com', source: 'test' });
  const sent = [];
  const email = {
    isEmailEnabled: () => true,
    emailConfig: { notify: '' },
    waitlistWelcomeEmail: () => ({ subject: 'Welcome', html: '<p>hi</p>', text: 'hi' }),
    waitlistNotifyEmail() { throw new Error('notify should not run'); },
  };
  await jobs.enqueue(db, 'waitlist_welcome', { email: 'join@example.com' }, { kick: false });
  const summary = await jobs.drainOnce({
    db,
    email,
    sendEmail: async (msg) => { sent.push(msg); return { ok: true, id: 'msg_1' }; },
  });
  assert.equal(summary.done, 1);
  assert.equal(sent.length, 1);
  assert.equal(sent[0].to, 'join@example.com');
  const row = await get('SELECT welcomed FROM waitlist WHERE email = ?', ['join@example.com']);
  assert.equal(row.welcomed, 1);
});

test('waitlist send failure retries instead of marking welcomed', async () => {
  await db.addWaitlistEntry({ email: 'retry@example.com', source: 'test' });
  const email = {
    isEmailEnabled: () => true,
    emailConfig: { notify: '' },
    waitlistWelcomeEmail: () => ({ subject: 'W', html: 'h', text: 't' }),
  };
  const row = await jobs.enqueue(db, 'waitlist_welcome', { email: 'retry@example.com' }, { kick: false });
  await jobs.drainOnce({
    db,
    email,
    sendEmail: async () => ({ ok: false, error: 'Resend 429' }),
  });
  const stored = await db.getJob(row.id);
  assert.equal(stored.status, 'pending');
  assert.match(stored.last_error, /Resend 429/);
  const wl = await get('SELECT welcomed FROM waitlist WHERE email = ?', ['retry@example.com']);
  assert.equal(wl.welcomed, 0);
});

test('stuck running jobs are reclaimed', async () => {
  const row = await jobs.enqueue(db, 'push_group', {
    groupId: 1, excludeUserId: null, title: 'T', body: 'B',
  }, { kick: false });
  await run(
    `UPDATE jobs SET status = 'running', started_at = datetime('now', '-10 minutes'), attempts = 1 WHERE id = ?`,
    [row.id]
  );
  const { reclaimed } = await db.reclaimStuckJobs(120);
  assert.ok(reclaimed >= 1);
  const stored = await db.getJob(row.id);
  assert.equal(stored.status, 'pending');
});

test('a concurrent drain is skipped rather than double-claiming', async () => {
  let release;
  const gate = new Promise((r) => { release = r; });
  let started;
  const startedP = new Promise((r) => { started = r; });
  const push = {
    async pushToUser() { started(); await gate; },
    async pushToGroup() { started(); await gate; },
  };
  await jobs.enqueue(db, 'push_user', { userId: 3, title: 'A', body: 'B' }, { kick: false });
  const first = jobs.drainOnce({ db, push });
  await startedP;
  const second = await jobs.drainOnce({ db, push });
  assert.equal(second.skipped, true);
  release();
  const summary = await first;
  assert.equal(summary.claimed, 1);
  assert.equal(summary.done, 1);
});
