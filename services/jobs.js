/**
 * SQLite outbox for side effects that must not block (or fail) an HTTP
 * request: APNs pushes and waitlist Resend emails.
 *
 * Single-process: claim is SELECT + UPDATE status='pending', plus an
 * in-process drain mutex. Retries use available_at backoff; after
 * max_attempts the row stays in status='failed' for inspection.
 *
 * Not a hosted queue. Onboarding drip, 2FA, concierge chat, and receipt
 * scan stay on their existing paths.
 */

const BACKOFF_SECONDS = [5, 15, 45, 120, 300];
const BATCH_SIZE = 10;
const MAX_BATCHES_PER_DRAIN = 20;
const STALE_RUNNING_SECONDS = 120;

const KINDS = new Set(['push_user', 'push_group', 'waitlist_welcome', 'waitlist_notify']);

let draining = false;
let kickTimer = null;
let queuedOpts = null;

function isConfigured() {
  return require('../push').isConfigured();
}

function kick() {
  if (kickTimer) return;
  kickTimer = setImmediate(() => {
    kickTimer = null;
    drainOnce().catch((err) => console.error('[jobs] drain:', err.message));
  });
  if (kickTimer.unref) kickTimer.unref();
}

async function enqueue(db, kind, payload, { maxAttempts = 5, kick: shouldKick = true } = {}) {
  if (!KINDS.has(kind)) throw new Error(`unknown job kind: ${kind}`);
  const row = await db.enqueueJob({ kind, payload, maxAttempts });
  if (shouldKick) kick();
  return row;
}

// Drop-in for push.pushToUser / push.pushToGroup. Persists then kicks the
// drain; never throws (callers fire-and-forget). No row when APNs is unset.
function pushToUser(db, userId, title, body, data) {
  if (!isConfigured()) return Promise.resolve();
  return enqueue(db, 'push_user', { userId, title, body, data: data || {} })
    .catch((err) => console.error('[jobs] enqueue push_user failed:', err.message));
}

function pushToGroup(db, groupId, excludeUserId, title, body, data) {
  if (!isConfigured()) return Promise.resolve();
  return enqueue(db, 'push_group', { groupId, excludeUserId, title, body, data: data || {} })
    .catch((err) => console.error('[jobs] enqueue push_group failed:', err.message));
}

async function enqueueWaitlist(db, { email, total, notify }) {
  await enqueue(db, 'waitlist_welcome', { email });
  if (notify) await enqueue(db, 'waitlist_notify', { email, total });
}

function backoffSeconds(attempts) {
  const i = Math.max(0, (Number(attempts) || 1) - 1);
  return BACKOFF_SECONDS[Math.min(i, BACKOFF_SECONDS.length - 1)];
}

async function runJob(db, job, deps) {
  const payload = job.payload && typeof job.payload === 'object' ? job.payload : {};
  switch (job.kind) {
    case 'push_user': {
      const push = deps.push || require('../push');
      await push.pushToUser(
        db, payload.userId, payload.title, payload.body, payload.data || {},
        { throwOnError: true }
      );
      return;
    }
    case 'push_group': {
      const push = deps.push || require('../push');
      await push.pushToGroup(
        db, payload.groupId, payload.excludeUserId, payload.title, payload.body, payload.data || {},
        { throwOnError: true }
      );
      return;
    }
    case 'waitlist_welcome': {
      const emailMod = deps.email || require('./email');
      const sendEmail = deps.sendEmail || emailMod.sendEmail.bind(emailMod);
      if (!emailMod.isEmailEnabled()) return;
      const welcome = emailMod.waitlistWelcomeEmail();
      const r = await sendEmail({
        to: payload.email,
        subject: welcome.subject,
        html: welcome.html,
        text: welcome.text,
      });
      if (!r.ok) throw new Error(r.error || 'welcome send failed');
      await db.markWaitlistWelcomed(payload.email);
      return;
    }
    case 'waitlist_notify': {
      const emailMod = deps.email || require('./email');
      const sendEmail = deps.sendEmail || emailMod.sendEmail.bind(emailMod);
      if (!emailMod.isEmailEnabled() || !emailMod.emailConfig.notify) return;
      const note = emailMod.waitlistNotifyEmail(payload.email, payload.total);
      const r = await sendEmail({
        to: emailMod.emailConfig.notify,
        subject: note.subject,
        html: note.html,
        text: note.text,
      });
      if (!r.ok) throw new Error(r.error || 'notify send failed');
      return;
    }
    default:
      throw new Error(`unknown job kind: ${job.kind}`);
  }
}

async function settle(db, job, err) {
  if (!err) {
    await db.markJobDone(job.id);
    return 'done';
  }
  const msg = err.message || String(err);
  if (job.attempts >= job.max_attempts) {
    await db.markJobFailed(job.id, msg);
    return 'failed';
  }
  await db.markJobRetry(job.id, msg, backoffSeconds(job.attempts));
  return 'retry';
}

async function drainOnce(opts = {}) {
  if (draining) {
    queuedOpts = opts;
    return { skipped: true };
  }
  draining = true;
  const db = opts.db || new (require('../database'))();
  const summary = { claimed: 0, done: 0, retry: 0, failed: 0 };
  try {
    await db.reclaimStuckJobs(opts.staleSeconds || STALE_RUNNING_SECONDS);
    for (let i = 0; i < MAX_BATCHES_PER_DRAIN; i++) {
      const jobs = await db.claimPendingJobs(opts.limit || BATCH_SIZE);
      if (!jobs.length) break;
      summary.claimed += jobs.length;
      for (const job of jobs) {
        let err = null;
        try {
          await runJob(db, job, opts);
        } catch (e) {
          err = e;
        }
        const outcome = await settle(db, job, err);
        summary[outcome]++;
      }
    }
    return summary;
  } finally {
    draining = false;
    if (queuedOpts) {
      const next = queuedOpts;
      queuedOpts = null;
      setImmediate(() => drainOnce(next).catch((err) => console.error('[jobs] drain:', err.message)));
    }
  }
}

function startWorker() {
  const ms = Math.max(1000, Number(process.env.JOB_DRAIN_MS) || 5000);
  const handle = setInterval(() => {
    drainOnce().catch((err) => console.error('[jobs] drain:', err.message));
  }, ms);
  if (handle.unref) handle.unref();
  kick();
}

// Tests that fail mid-drain would otherwise leave the mutex stuck.
function resetDrainLock() {
  draining = false;
  queuedOpts = null;
  if (kickTimer) {
    clearImmediate(kickTimer);
    kickTimer = null;
  }
}

module.exports = {
  KINDS,
  enqueue,
  enqueueWaitlist,
  pushToUser,
  pushToGroup,
  isConfigured,
  kick,
  drainOnce,
  startWorker,
  resetDrainLock,
  backoffSeconds,
};
