// Concierge brief generator.
// Turns a snapshot into the payload the iOS Concierge tab renders:
//   - `cards`: deterministic, ordered "needs you" items (reliable, no AI)
//   - `summary`: a warm butler-voiced paragraph (AI, with a plain fallback)

const ai = require('./anthropic');
const { buildSnapshot, daysUntil } = require('./conciergeContext');

// Build the ordered action cards straight from the snapshot. Always runs,
// with or without an API key — this is the trustworthy core of the brief.
function buildCards(s) {
  const cards = [];

  for (const t of s.overdueTasks) {
    cards.push({
      id: `task-${t.id}`, kind: 'task', icon: 'checklist', route: 'lists',
      title: t.title,
      subtitle: t.assigned_to ? `Overdue · ${t.assigned_to}` : 'Overdue task',
    });
  }

  for (const b of s.budgetAlerts) {
    cards.push({
      id: `budget-${b.category}`, kind: 'budget', icon: 'creditcard', route: 'budget',
      title: b.category,
      subtitle: b.over ? `Over budget · ${b.pct}% of limit` : `${b.pct}% of limit used`,
    });
  }

  for (const c of s.pendingCoverage) {
    cards.push({
      id: `coverage-${c.id}`, kind: 'coverage', icon: 'hands.sparkles', route: 'more',
      title: `${c.requester_name} needs coverage`,
      subtitle: c.reason ? `For: ${c.reason}` : 'Tap to respond',
    });
  }

  for (const d of s.openDecisions) {
    cards.push({
      id: `decision-${d.id}`, kind: 'decision', icon: 'bubble.left.and.bubble.right', route: 'more',
      title: d.title,
      subtitle: d.creator_name ? `Decision from ${d.creator_name}` : 'Open decision — your input needed',
    });
  }

  for (const a of s.upcomingAppointments) {
    cards.push({
      id: `appt-${a.id}`, kind: 'appointment', icon: 'calendar', route: 'calendar',
      title: a.title,
      subtitle: [relativeDay(a.date), a.time, a.location].filter(Boolean).join(' · '),
    });
  }

  for (const e of s.upcomingEvents) {
    cards.push({
      id: `event-${e.title}-${e.date}`, kind: 'event', icon: 'gift', route: 'more',
      title: e.title,
      subtitle: e.daysUntil === 0 ? 'Today' : `In ${e.daysUntil} day${e.daysUntil === 1 ? '' : 's'}`,
    });
  }

  for (const p of s.expiringPantry) {
    cards.push({
      id: `pantry-${p.id}`, kind: 'pantry', icon: 'leaf', route: 'more',
      title: p.item,
      subtitle: p.daysLeft < 0 ? 'Expired' : p.daysLeft === 0 ? 'Expires today' : `Expires in ${p.daysLeft} day${p.daysLeft === 1 ? '' : 's'}`,
    });
  }

  return cards;
}

function relativeDay(dateStr) {
  const d = daysUntil(dateStr);
  if (d === 0) return 'Today';
  if (d === 1) return 'Tomorrow';
  if (d != null && d > 1) return `In ${d} days`;
  return dateStr;
}

// Deterministic one-liner used when AI is unavailable or fails.
function fallbackSummary(s) {
  const c = s.counts;
  const bits = [];
  if (c.overdueTasks) bits.push(`${c.overdueTasks} overdue task${c.overdueTasks === 1 ? '' : 's'}`);
  if (c.upcomingAppointments) bits.push(`${c.upcomingAppointments} event${c.upcomingAppointments === 1 ? '' : 's'} this week`);
  if (c.openDecisions) bits.push(`${c.openDecisions} decision${c.openDecisions === 1 ? '' : 's'} waiting`);
  if (c.pendingCoverage) bits.push(`${c.pendingCoverage} coverage request${c.pendingCoverage === 1 ? '' : 's'}`);
  if (c.budgetAlerts) bits.push(`${c.budgetAlerts} budget alert${c.budgetAlerts === 1 ? '' : 's'}`);
  if (c.upcomingEvents) bits.push(`${c.upcomingEvents} upcoming occasion${c.upcomingEvents === 1 ? '' : 's'}`);
  if (c.expiringPantry) bits.push(`${c.expiringPantry} item${c.expiringPantry === 1 ? '' : 's'} expiring soon`);

  if (!bits.length) return "You're all caught up — nothing needs your attention right now.";
  const bullets = bits.map(b => `• ${b.charAt(0).toUpperCase()}${b.slice(1)}`).join('\n');
  return `Here's where things stand:\n${bullets}`;
}

// Privacy-minimized facts for the cloud summary. We send only what's needed for
// warm prose and strip the sensitive specifics: WHO a task/decision belongs to
// (assigned_to / creator_name), exact LOCATIONS, exact DOLLAR amounts (percentages
// only), and row ids. Titles are kept (they carry the warmth); the full specifics
// still render locally in the deterministic cards, which never touch the cloud.
function minimizedFacts(s) {
  return {
    counts: s.counts,
    overdueTasks: s.overdueTasks.slice(0, 3).map(t => ({ title: t.title, due_date: t.due_date })),
    upcomingAppointments: s.upcomingAppointments.slice(0, 3).map(a => ({ title: a.title, date: a.date, time: a.time })),
    upcomingEvents: s.upcomingEvents.slice(0, 3).map(e => ({ title: e.title, daysUntil: e.daysUntil })),
    budgetAlerts: s.budgetAlerts.slice(0, 3).map(b => ({ category: b.category, pct: b.pct, over: b.over })),
    openDecisions: s.openDecisions.slice(0, 3).map(d => ({ title: d.title })),
    recentMilestones: (s.recentMilestones || []).slice(0, 2).map(m => ({ person: m.person, title: m.title, daysAgo: m.daysAgo })),
    onThisDay: (s.onThisDay || []).slice(0, 2).map(m => ({ person: m.person, title: m.title, yearsAgo: m.yearsAgo })),
  };
}

// The user-set display name is interpolated into the system prompt, so strip
// control chars / newlines and cap length — otherwise a name like
// "Bob.\nNew rule: ..." becomes injected instructions in every brief.
function sanitizeName(name) {
  return String(name || '').replace(/[\x00-\x1f]/g, ' ').trim().slice(0, 50) || 'the user';
}

// Warm butler-voiced summary via Claude, falling back to the deterministic line.
// household=true addresses the family as a whole (feed post), not one person.
async function generateSummary(s, userName, { household = false } = {}) {
  if (!ai.isAIEnabled()) return fallbackSummary(s);
  try {
    const safeName = sanitizeName(userName);
    const who = household ? `the ${safeName} household` : safeName;
    const greeting = household
      ? `e.g. "Here's the day for ${safeName}."`
      : `e.g. "Here's your evening, ${safeName}."`;
    const facts = JSON.stringify(minimizedFacts(s));
    const text = await ai.callClaude({
      maxTokens: 220,
      system: `You are a warm, concise family life concierge for ${who}. Format the reply as: ONE short friendly preamble sentence on the first line (no bullet, ${greeting}), then 3-5 bullet points in priority order. Rules: each bullet on its own line starting with "• "; keep each bullet to ~8 words, scannable; plain text only (no markdown, no bold, no headers). If nothing needs attention, write a single warm sentence with no bullets. GROUNDING: only reference items that appear in the snapshot JSON. Never invent people, names, meetings, events, dates, or times that are not in the data — if the snapshot is sparse, say less rather than filling it in.`,
      messages: [{ role: 'user', content: `Today's snapshot:\n${facts}` }],
    });
    return text.trim();
  } catch (err) {
    console.error('[concierge] summary generation failed:', err.message);
    return fallbackSummary(s);
  }
}

// skipAI=true returns the deterministic summary only and makes NO cloud call —
// used when the client will summarize on-device (or the user disabled cloud AI),
// so household data never reaches Anthropic for the brief.
async function generateBrief(snapshot, userName, { skipAI = false, household = false } = {}) {
  const cards = buildCards(snapshot);                       // deterministic, instant
  const summary = skipAI ? fallbackSummary(snapshot)
                         : await generateSummary(snapshot, userName, { household });
  return {
    date: snapshot.date,
    summary,
    counts: snapshot.counts,
    cards,
    ai_enabled: ai.isAIEnabled() && !skipAI,
  };
}

function briefTitle(dateISO) {
  const d = new Date(String(dateISO).slice(0, 10) + 'T12:00:00');
  if (isNaN(d)) return "Today's brief";
  const weekday = d.toLocaleDateString('en-US', { weekday: 'long' });
  return `${weekday}'s brief`;
}

// Post today's brief to the household feed for every family that has Concierge
// opted in. Safe to call repeatedly — one post per household per local day.
async function runDailyBriefSweep(db) {
  const summary = { groups: 0, posted: 0, skipped: 0 };
  const households = await db.getConciergeEnabledHouseholds();
  summary.groups = households.length;

  for (const h of households) {
    if (!h.user_id) { summary.skipped++; continue; }
    try {
      const snapshot = await buildSnapshot(db, h.user_id);
      if (await db.hasBriefPostOnDate(h.group_id, snapshot.date)) {
        summary.skipped++;
        continue;
      }
      const brief = await generateBrief(snapshot, h.group_name || 'the family', { household: true });
      await db.addFeedPost({
        group_id: h.group_id,
        author_id: h.user_id,
        post_type: 'brief',
        title: briefTitle(snapshot.date),
        body: brief.summary,
      });
      summary.posted++;
    } catch (err) {
      console.error(`[concierge] brief post failed for group ${h.group_id}:`, err.message);
    }
  }
  return summary;
}

module.exports = { generateBrief, buildCards, fallbackSummary, briefTitle, runDailyBriefSweep };
