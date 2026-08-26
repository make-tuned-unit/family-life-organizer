// Concierge proactive nudges.
// Detects what most needs attention in a household and sends ONE throttled
// push nudge that deep-links into the Concierge tab. Premium households only.

const push = require('../push');
const { buildSnapshot } = require('./conciergeContext');
const sleepStats = require('./sleepStats');

const DAILY_CAP_HOURS = 20;   // at most one nudge per household per ~day
const DEDUPE_HOURS = 72;      // don't repeat the same nudge within 3 days

function plural(n, word) {
  return `${n} ${word}${n === 1 ? '' : 's'}`;
}

// How long a sleep insight stays quiet once sent. Longer than the generic
// dedupe: the point of a sleep finding is to be acted on over a week, and
// re-sending it every third day would train the family to swipe it away.
const SLEEP_DEDUPE_HOURS = 24 * 7;
// Below this there is not enough of a log to say anything worth a push.
const SLEEP_MIN_NIGHTS = 5;

/**
 * The one sleep insight in this household worth interrupting for, or null.
 *
 * PRIVACY: a routine is private to its creator unless shared_scope is
 * 'household' (see the routines table). A private routine's findings are pushed
 * to that creator ALONE — never through pushToGroup — so the sweep can't
 * broadcast one parent's private log to the whole house. `audience_user_id`
 * carries that decision to the caller.
 */
async function sleepNudgeFor(db, groupId, { today = null } = {}) {
  const members = await db.getGroupMembers(groupId);
  const seen = new Set();
  const routines = [];
  for (const m of members) {
    if (!m.user_id) continue;
    for (const r of await db.getRoutines(groupId, m.user_id)) {
      if (seen.has(r.id)) continue;
      seen.add(r.id);
      if (r.active === 0) continue;
      if (!['baby_sleep', 'sleep_training'].includes(r.routine_type)) continue;
      routines.push(r);
    }
  }

  const entriesBy = await db.getRoutineEntriesForIds(routines.map(r => r.id), { limitPer: 600 });
  for (const routine of routines) {
    const entries = entriesBy.get(routine.id) || [];
    const birthdate = routine.subject_birthdate || null;
    const analysis = sleepStats.analyzeWakings(entries, { birthdate, today, windowDays: 14 });
    if (analysis.nights_analyzed < SLEEP_MIN_NIGHTS) continue;

    // Only a pattern with a rhythm behind it earns a push. A single rough night
    // is not news to the person who was awake for it.
    const cluster = analysis.cluster;
    if (!cluster || !analysis.rhythm || analysis.rhythm.confidence === 'low') continue;

    const stats = sleepStats.compute(entries, { birthdate, today });
    const rec = sleepStats.recommend(stats, analysis, { birthdate }).items[0];
    if (!rec) continue;

    const who = routine.subject_name || routine.name;
    const shared = routine.shared_scope === 'household';
    return {
      // Keyed on the FINDING, not the routine: the same insight stays quiet,
      // and a genuinely new pattern gets through the dedupe immediately.
      key: `sleep:${routine.id}:${rec.key}:${cluster.typical_time_minutes}`,
      title: `${who}'s sleep — a pattern worth a look`,
      body: `Waking around ${cluster.typical_time} on ${cluster.nights_affected} of the last ${cluster.nights_logged} nights, ${analysis.rhythm.label}. Tap to see what the data suggests trying.`,
      audience_user_id: shared ? null : routine.created_by,
      dedupe_hours: SLEEP_DEDUPE_HOURS,
      routine_id: routine.id,
    };
  }
  return null;
}

// Choose the single highest-priority nudge from a snapshot, or null if nothing
// is worth interrupting the family for. Deterministic — no AI.
function pickNudge(s) {
  if (s.overdueTasks.length) {
    return {
      key: 'tasks:overdue',
      title: 'Overdue tasks',
      body: `You have ${plural(s.overdueTasks.length, 'task')} past due. Tap to catch up.`,
    };
  }
  const over = s.budgetAlerts.find(b => b.over);
  if (over) {
    return {
      key: `budget:${over.category}`,
      title: 'Budget alert',
      body: `You're over budget on ${over.category} (${over.pct}% of limit).`,
    };
  }
  // Note: coverage is person-to-person and already has its own notifications,
  // so it's deliberately not a household-wide proactive nudge.
  if (s.openDecisions.length) {
    const d = s.openDecisions[0];
    return {
      key: `decision:${d.id}`,
      title: 'A decision is waiting',
      body: `"${d.title}" needs your input.`,
    };
  }
  if (s.upcomingEvents.length) {
    const e = s.upcomingEvents[0];
    const when = e.daysUntil === 0 ? 'today' : `in ${plural(e.daysUntil, 'day')}`;
    return {
      key: `event:${e.title}:${e.date}`,
      title: 'Coming up',
      body: `${e.title} is ${when}.`,
    };
  }
  if (s.expiringPantry.length) {
    const p = s.expiringPantry[0];
    const when = p.daysLeft < 0 ? 'has expired' : p.daysLeft === 0 ? 'expires today' : `expires in ${plural(p.daysLeft, 'day')}`;
    return {
      key: `pantry:${p.id}`,
      title: 'Expiring soon',
      body: `${p.item} ${when}.`,
    };
  }
  return null;
}

// Sweep every premium household and send at most one throttled, deduped nudge.
// Safe to call repeatedly — throttling lives in the concierge_nudges log.
async function runProactiveSweep(db, { dailyCapHours = DAILY_CAP_HOURS, dedupeHours = DEDUPE_HOURS } = {}) {
  const summary = { groups: 0, considered: 0, sent: 0 };
  if (!push.isConfigured()) return summary;

  const groups = await db.getPremiumGroups();
  summary.groups = groups.length;

  for (const groupId of groups) {
    const members = await db.getGroupMembers(groupId);
    const member = members.find(m => m.user_id);
    if (!member) continue;

    // A sleep pattern outranks the generic candidates: it is rarer, it is
    // deduped for a week, and it is the one thing here a parent cannot work out
    // by looking at a list.
    const sleep = await safeSleepNudge(db, groupId);
    const nudge = sleep || pickNudge(await buildSnapshot(db, member.user_id));
    if (!nudge) continue;
    summary.considered++;

    if (await db.countRecentNudges(groupId, dailyCapHours)) continue;       // daily cap
    if (await db.recentNudgeKey(groupId, nudge.key, nudge.dedupe_hours || dedupeHours)) continue;

    // Record BEFORE pushing so the log is the guard against duplicate sends.
    await db.recordNudge(groupId, nudge.key);
    const payload = { type: 'concierge', nudge: nudge.key };
    if (nudge.routine_id) payload.routine_id = nudge.routine_id;
    if (nudge.audience_user_id) {
      // Private routine: its owner only. See the PRIVACY note on sleepNudgeFor.
      await push.pushToUser(db, nudge.audience_user_id, nudge.title, nudge.body, payload);
    } else {
      await push.pushToGroup(db, groupId, null, nudge.title, nudge.body, payload);
    }
    summary.sent++;
  }
  return summary;
}

// A failure in the sleep analysis must not take the whole sweep down with it —
// every other household still deserves its nudge.
async function safeSleepNudge(db, groupId) {
  try {
    return await sleepNudgeFor(db, groupId);
  } catch (err) {
    console.error('[concierge] sleep nudge failed:', err.message);
    return null;
  }
}

module.exports = { pickNudge, sleepNudgeFor, runProactiveSweep };
