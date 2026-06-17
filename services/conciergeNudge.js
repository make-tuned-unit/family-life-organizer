// Concierge proactive nudges.
// Detects what most needs attention in a household and sends ONE throttled
// push nudge that deep-links into the Concierge tab. Premium households only.

const push = require('../push');
const { buildSnapshot } = require('./conciergeContext');

const DAILY_CAP_HOURS = 20;   // at most one nudge per household per ~day
const DEDUPE_HOURS = 72;      // don't repeat the same nudge within 3 days

function plural(n, word) {
  return `${n} ${word}${n === 1 ? '' : 's'}`;
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

    const snapshot = await buildSnapshot(db, member.user_id);
    const nudge = pickNudge(snapshot);
    if (!nudge) continue;
    summary.considered++;

    if (await db.countRecentNudges(groupId, dailyCapHours)) continue;       // daily cap
    if (await db.recentNudgeKey(groupId, nudge.key, dedupeHours)) continue; // dedupe

    // Record BEFORE pushing so the log is the guard against duplicate sends.
    await db.recordNudge(groupId, nudge.key);
    await push.pushToGroup(db, groupId, null, nudge.title, nudge.body, { type: 'concierge', nudge: nudge.key });
    summary.sent++;
  }
  return summary;
}

module.exports = { pickNudge, runProactiveSweep };
