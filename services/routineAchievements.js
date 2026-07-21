// Achievements for "activity" routines (violin, swimming, baseball, …).
//
// Design follows the habit-gamification evidence: cumulative COUNT milestones are
// the primary reward because they never reset — a missed week can't erase what
// you've already earned, which avoids the streak-loss demotivation that the
// research flags as gamification's main failure mode. A current weekly streak is
// surfaced too, but only as an encouraging secondary signal, never a punishment.

// Cumulative-session milestone thresholds. Spacing widens so there's always a
// reachable "next" without the ladder feeling grindy.
const MILESTONES = [
  { count: 1,   title: 'First session',   blurb: 'You showed up — that\'s the hardest part.' },
  { count: 5,   title: '5 sessions',      blurb: 'A habit is taking shape.' },
  { count: 10,  title: '10 sessions',     blurb: 'Double digits — real momentum.' },
  { count: 25,  title: '25 sessions',     blurb: 'Quarter-century of practice.' },
  { count: 50,  title: '50 sessions',     blurb: 'Halfway to a hundred. Dedicated.' },
  { count: 100, title: '100 sessions',    blurb: 'Triple digits. This is who you are now.' },
  { count: 150, title: '150 sessions',    blurb: 'Serious commitment.' },
  { count: 200, title: '200 sessions',    blurb: 'Two hundred. Remarkable.' },
  { count: 300, title: '300 sessions',    blurb: 'Elite consistency.' },
  { count: 500, title: '500 sessions',    blurb: 'A true master of the routine.' },
];

// ISO-ish week key (year + week number) in local time, so "weekly streak" means
// distinct calendar weeks with at least one attended session.
function weekKey(dateStr) {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(dateStr));
  if (!m) return null;
  const d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
  if (Number.isNaN(d.getTime())) return null;
  // Thursday-based ISO week number.
  const target = new Date(d);
  const day = (d.getDay() + 6) % 7; // Mon=0..Sun=6
  target.setDate(target.getDate() - day + 3);
  const firstThursday = new Date(target.getFullYear(), 0, 4);
  const week = 1 + Math.round(((target - firstThursday) / 86400000 - 3 + ((firstThursday.getDay() + 6) % 7)) / 7);
  return `${target.getFullYear()}-W${String(week).padStart(2, '0')}`;
}

// Count of whole weeks between two week keys, treating consecutive ISO weeks as
// distance 1. We approximate via the entry dates' Monday anchors.
function mondayOf(dateStr) {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(dateStr));
  const d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
  const day = (d.getDay() + 6) % 7;
  d.setDate(d.getDate() - day);
  d.setHours(0, 0, 0, 0);
  return d;
}

// entries: routine_entries (any order). A session counts when entry_type is a
// session/attended marker (skips and notes don't count toward the total).
function compute(entries, { todayISO } = {}) {
  const attended = (entries || [])
    .filter(e => e && (e.entry_type === 'session' || e.entry_type === 'attended') && attendedStatus(e))
    .filter(e => /^\d{4}-\d{2}-\d{2}/.test(String(e.entry_date || '')))
    .sort((a, b) => a.entry_date < b.entry_date ? -1 : 1);

  const total = attended.length;

  // Weekly streak: distinct weeks with ≥1 session, counting back from the most
  // recent session's week while weeks stay consecutive.
  let currentStreak = 0;
  if (total) {
    const weeks = [...new Set(attended.map(e => mondayOf(e.entry_date).getTime()))].sort((a, b) => a - b);
    currentStreak = 1;
    for (let i = weeks.length - 1; i > 0; i--) {
      const gapWeeks = Math.round((weeks[i] - weeks[i - 1]) / (7 * 86400000));
      if (gapWeeks === 1) currentStreak++;
      else break;
    }
    // If the most recent session is already 2+ weeks old, the streak has lapsed.
    if (todayISO) {
      const lastMonday = weeks[weeks.length - 1];
      const nowMonday = mondayOf(todayISO).getTime();
      const staleWeeks = Math.round((nowMonday - lastMonday) / (7 * 86400000));
      if (staleWeeks >= 2) currentStreak = 0;
    }
  }

  const earned = MILESTONES.filter(m => total >= m.count);
  const next = MILESTONES.find(m => total < m.count) || null;

  return {
    total_sessions: total,
    current_streak_weeks: currentStreak,
    last_session_date: total ? attended[attended.length - 1].entry_date : null,
    earned: earned.map(m => ({ count: m.count, title: m.title, blurb: m.blurb })),
    next_milestone: next
      ? { count: next.count, title: next.title, blurb: next.blurb, remaining: next.count - total }
      : null,
    // The newest earned badge, for a "just unlocked" celebration on the client.
    latest: earned.length ? earned[earned.length - 1].title : null,
  };
}

// A session entry is "attended" unless its JSON value explicitly says skipped.
function attendedStatus(e) {
  if (!e.value) return true;
  try {
    const v = typeof e.value === 'string' ? JSON.parse(e.value) : e.value;
    return v.status !== 'skipped';
  } catch {
    return true;
  }
}

module.exports = { compute, MILESTONES };
