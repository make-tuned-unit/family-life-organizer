// Sleep statistics for a baby_sleep / sleep_training routine: what the logged
// entries actually say, measured against age-appropriate targets, plus tips that
// only fire when the data supports them.
//
// This is educational, NOT medical advice. Two rules keep it honest:
//   1. Every target is attributed to a source (see SOURCES in sleepTraining.js).
//   2. A tip must be earned by the data. No entries → no advice, and each tip
//      states the observed number it is reacting to, so nothing is hand-wavy.
//
// The AASM/AAP consensus deliberately starts at 4 months — there is NO expert
// consensus range below that age — so `recommended` is null for newborns and the
// UI says so rather than inventing a number.

const { ageInDays, wakeWindowForBirthdate, guidanceForBirthdate } = require('./sleepTraining');

// AASM child sleep-duration consensus (AAP-endorsed), hours per 24h INCLUDING
// naps. Bands are [minDays, maxDays] inclusive.
const DURATION_BANDS = [
  { minDays: 0, maxDays: 119, label: 'Under 4 months', min: null, max: null,
    note: 'The AASM consensus starts at 4 months — there is no expert-agreed range for newborns. Expect wide day-to-day variation.' },
  { minDays: 120, maxDays: 365, label: '4–12 months', min: 12, max: 16 },
  { minDays: 366, maxDays: 730, label: '1–2 years', min: 11, max: 14 },
  { minDays: 731, maxDays: 1825, label: '3–5 years', min: 10, max: 13 },
  { minDays: 1826, maxDays: 4380, label: '6–12 years', min: 9, max: 12 },
];

// Typical nap counts by age. Guidance for shaping a day, not a target to hit.
const NAP_BANDS = [
  { minDays: 0, maxDays: 119, min: 4, max: 6, label: '4–6 short naps, on no fixed schedule' },
  { minDays: 120, maxDays: 240, min: 3, max: 4, label: '3–4 naps' },
  { minDays: 241, maxDays: 456, min: 2, max: 3, label: '2–3 naps' },
  { minDays: 457, maxDays: 547, min: 1, max: 2, label: '1–2 naps' },
  { minDays: 548, maxDays: 1095, min: 1, max: 1, label: '1 nap' },
  { minDays: 1096, maxDays: 4380, min: 0, max: 1, label: '0–1 nap' },
];

const bandFor = (bands, days) =>
  bands.find(b => days >= b.minDays && days <= b.maxDays) || bands[bands.length - 1];

function parseValue(entry) {
  if (!entry.value) return null;
  try { return typeof entry.value === 'string' ? JSON.parse(entry.value) : entry.value; }
  catch { return null; }
}

// Sleep stamps are naive local clock times ("2026-08-20 09:14"), not instants.
// Parse them as UTC-clock so server timezone cannot shift comparisons, and
// accept the extra shapes the iOS formatter has actually emitted: seconds,
// a T separator, and 12-hour AM/PM. `new Date(stamp.replace(' ','T')+':00')`
// treated "09:14:00" and "09:14 AM" as invalid, so a morning nap was skipped
// and Home kept counting awake from last night's wake.
function parseSleepStamp(stamp) {
  const s = String(stamp || '').trim();
  const m = /^(\d{4})-(\d{2})-(\d{2})[ T](\d{1,2}):(\d{2})(?::(\d{2}))?(?:\s*([AaPp])\.?[Mm]\.?)?$/.exec(s);
  if (!m) return null;
  let h = parseInt(m[4], 10);
  const min = parseInt(m[5], 10);
  if (m[7]) {
    const pm = m[7].toLowerCase() === 'p';
    if (pm && h < 12) h += 12;
    if (!pm && h === 12) h = 0;
  }
  if (h > 23 || min > 59) return null;
  return Date.UTC(+m[1], +m[2] - 1, +m[3], h, min);
}

function formatSleepStamp(ms) {
  const d = new Date(ms);
  const pad = (v) => String(v).padStart(2, '0');
  return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())} ${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}`;
}

// "yyyy-MM-dd HH:mm" (and the sibling shapes above) -> minutes since midnight.
function minutesOfDay(stamp) {
  const ms = parseSleepStamp(stamp);
  if (ms == null) return null;
  const d = new Date(ms);
  return d.getUTCHours() * 60 + d.getUTCMinutes();
}

const dayOf = (stamp) => String(stamp || '').slice(0, 10);

function fmtHm(minutes) {
  const h = Math.floor(minutes / 60), m = Math.round(minutes % 60);
  if (h === 0) return `${m}m`;
  return m === 0 ? `${h}h` : `${h}h ${m}m`;
}

function fmtClock(minutesOfDayValue) {
  const total = ((Math.round(minutesOfDayValue) % 1440) + 1440) % 1440;
  const h = Math.floor(total / 60), m = total % 60;
  const suffix = h < 12 ? 'am' : 'pm';
  const h12 = h % 12 === 0 ? 12 : h % 12;
  return `${h12}:${String(m).padStart(2, '0')}${suffix}`;
}

const mean = (xs) => xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : null;

// Standard deviation of clock times has to respect the wrap at midnight: a
// bedtime of 23:50 and one of 00:10 are 20 minutes apart, not 23h40m. Anchor
// everything to the first value and fold differences into ±12h.
function clockStats(minuteValues) {
  if (!minuteValues.length) return null;
  const anchor = minuteValues[0];
  const folded = minuteValues.map(v => {
    let d = v - anchor;
    while (d > 720) d -= 1440;
    while (d < -720) d += 1440;
    return d;
  });
  const avgOffset = mean(folded);
  const variance = mean(folded.map(d => (d - avgOffset) ** 2));
  return {
    average: ((anchor + avgOffset) % 1440 + 1440) % 1440,
    spread: Math.sqrt(variance),
    earliest: anchor + Math.min(...folded),
    latest: anchor + Math.max(...folded),
  };
}

/**
 * @param entries routine_entries rows (any order, any type)
 * @param opts.birthdate  subject_birthdate (YYYY-MM-DD) — drives age targets
 * @param opts.today      YYYY-MM-DD, the day "last night" is measured back from
 * @param opts.windowDays how many days the averages cover (default 7)
 */
function compute(entries, { birthdate = null, today = null, windowDays = 7 } = {}) {
  const sleeps = (entries || [])
    .filter(e => e.entry_type === 'nap' || e.entry_type === 'night_sleep')
    .map(e => {
      const v = parseValue(e) || {};
      return {
        type: e.entry_type,
        date: e.entry_date,
        minutes: Number.isFinite(v.duration_minutes) ? v.duration_minutes : null,
        startMin: minutesOfDay(v.sleep_start),
        endMin: minutesOfDay(v.sleep_end),
        endDay: dayOf(v.sleep_end),
        wakeCount: Number.isFinite(v.wake_count) ? v.wake_count : null,
        inProgress: !!v.in_progress,
      };
    })
    // An in-progress sleep has no end yet — counting it would understate the
    // night in progress and make "last night" jump around as it's logged.
    .filter(s => !s.inProgress && s.minutes != null && s.minutes > 0);

  const dayKeys = [...new Set(sleeps.map(s => s.date))].sort().reverse();
  const window = today
    ? dayKeys.filter(d => d <= today).slice(0, windowDays)
    : dayKeys.slice(0, windowDays);
  const prior = today
    ? dayKeys.filter(d => d <= today).slice(windowDays, windowDays * 2)
    : dayKeys.slice(windowDays, windowDays * 2);

  const byDay = (days) => days.map(date => {
    const forDay = sleeps.filter(s => s.date === date);
    const nights = forDay.filter(s => s.type === 'night_sleep');
    const naps = forDay.filter(s => s.type === 'nap');
    return {
      date,
      total_minutes: forDay.reduce((a, s) => a + s.minutes, 0),
      night_minutes: nights.reduce((a, s) => a + s.minutes, 0),
      nap_minutes: naps.reduce((a, s) => a + s.minutes, 0),
      nap_count: naps.length,
      wake_count: nights.reduce((a, s) => a + (s.wakeCount || 0), 0),
      longest_minutes: forDay.length ? Math.max(...forDay.map(s => s.minutes)) : 0,
    };
  });

  const days = byDay(window);
  const priorDays = byDay(prior);
  const nightsInWindow = sleeps.filter(s => s.type === 'night_sleep' && window.includes(s.date));

  const avgDaily = mean(days.map(d => d.total_minutes));
  const priorAvgDaily = mean(priorDays.map(d => d.total_minutes));

  // A night is usually SEVERAL night_sleep entries — the bedtime itself plus
  // each overnight resettle. Averaging every start as if it were "a bedtime"
  // dragged the average (and the wind-down reminder built on it) hours past the
  // real bedtime. Reduce each night to two marks first: bedtime = the first
  // start of the night, wake = the last end. "First/last" is judged on a
  // noon-to-noon clock so a 00:30 resettle counts as later than a 19:15
  // bedtime, not earlier.
  const noonAnchored = (m) => (m < 720 ? m + 1440 : m);
  const perNight = new Map();
  for (const s of nightsInWindow) {
    const night = perNight.get(s.date) || { startMin: null, endMin: null };
    if (s.startMin != null && (night.startMin == null || noonAnchored(s.startMin) < noonAnchored(night.startMin))) {
      night.startMin = s.startMin;
    }
    if (s.endMin != null && (night.endMin == null || noonAnchored(s.endMin) > noonAnchored(night.endMin))) {
      night.endMin = s.endMin;
    }
    perNight.set(s.date, night);
  }
  const nightMarks = [...perNight.values()];
  const bedtimes = clockStats(nightMarks.map(n => n.startMin).filter(v => v != null));
  const wakeTimes = clockStats(nightMarks.map(n => n.endMin).filter(v => v != null));

  const days_old = birthdate ? ageInDays(birthdate) : null;
  const durationBand = days_old != null ? bandFor(DURATION_BANDS, days_old) : null;
  const napBand = days_old != null ? bandFor(NAP_BANDS, days_old) : null;

  // Night and nap figures average over the days that actually HAVE one. Dividing
  // by every logged day instead meant a day with only a nap contributed a
  // zero-length night, so two 11-hour nights and one nap-only day reported the
  // nights as 7h20m — a number that is neither the night average nor anything
  // else. Daily totals and naps-per-day stay over all logged days, where a zero
  // is a real observation rather than a missing one.
  const nightDays = days.filter(d => d.night_minutes > 0);
  const napDays = days.filter(d => d.nap_count > 0);
  const avgOf = (rows, pick, decimals = 0) => {
    const m = mean(rows.map(pick));
    if (m == null) return null;
    const f = 10 ** decimals;
    return Math.round(m * f) / f;
  };

  const totals = {
    nights_logged: nightsInWindow.length,
    days_logged: days.length,
    avg_daily_minutes: avgDaily == null ? null : Math.round(avgDaily),
    avg_night_minutes: avgOf(nightDays, d => d.night_minutes),
    avg_nap_minutes: avgOf(napDays, d => d.nap_minutes),
    avg_naps_per_day: avgOf(days, d => d.nap_count, 1),
    avg_wakings: avgOf(nightDays, d => d.wake_count, 1),
    // Scoped to the window like every other figure here — an all-time maximum
    // sitting under a "last 7 days" heading would be quietly wrong.
    longest_stretch_minutes: (() => {
      const inWindow = sleeps.filter(s => window.includes(s.date));
      return inWindow.length ? Math.max(...inWindow.map(s => s.minutes)) : null;
    })(),
    last_night_minutes: days[0] ? days[0].night_minutes : null,
  };

  const guidance = durationBand ? {
    age_label: durationBand.label,
    recommended_min_minutes: durationBand.min == null ? null : durationBand.min * 60,
    recommended_max_minutes: durationBand.max == null ? null : durationBand.max * 60,
    recommended_label: durationBand.min == null ? null : `${durationBand.min}–${durationBand.max} hours per 24h, naps included`,
    nap_label: napBand ? napBand.label : null,
    note: durationBand.note || null,
    source: 'AASM child sleep-duration consensus (AAP-endorsed)',
  } : null;

  return {
    window_days: windowDays,
    days,
    totals,
    bedtime: bedtimes ? {
      average: fmtClock(bedtimes.average),
      // Raw minutes-of-day as well as the label: a bedtime reminder has to do
      // arithmetic on this, and re-parsing "7:30pm" to get it back would be
      // absurd.
      average_minutes: Math.round(bedtimes.average),
      earliest: fmtClock(bedtimes.earliest),
      latest: fmtClock(bedtimes.latest),
      spread_minutes: Math.round(bedtimes.spread),
    } : null,
    wake_time: wakeTimes ? { average: fmtClock(wakeTimes.average) } : null,
    trend: (avgDaily != null && priorAvgDaily != null) ? {
      daily_delta_minutes: Math.round(avgDaily - priorAvgDaily),
      prior_avg_daily_minutes: Math.round(priorAvgDaily),
    } : null,
    guidance,
    tips: buildTips({ totals, days, bedtime: bedtimes, guidance, napBand, days_old,
                      trend: (avgDaily != null && priorAvgDaily != null) ? avgDaily - priorAvgDaily : null }),
  };
}

// Each tip names the number that triggered it. `severity` is 'info' | 'watch';
// nothing here is urgent enough to alarm a parent at 3am.
function buildTips({ totals, days, bedtime, guidance, napBand, days_old, trend }) {
  const tips = [];

  if (totals.days_logged === 0) {
    return [{
      key: 'no_data', severity: 'info', title: 'Log a few sleeps to see patterns',
      detail: 'Once there are two or three nights logged, this turns into averages, a bedtime range, and tips based on what is actually happening.',
    }];
  }

  if (totals.days_logged < 3) {
    tips.push({
      key: 'thin_data', severity: 'info', title: `${totals.days_logged} day${totals.days_logged === 1 ? '' : 's'} logged so far`,
      detail: 'Averages get meaningful at about a week. Treat everything below as a first sketch.',
    });
  }

  // Total sleep vs the age-appropriate range.
  if (guidance?.recommended_min_minutes && totals.avg_daily_minutes != null) {
    const { recommended_min_minutes: lo, recommended_max_minutes: hi } = guidance;
    const avg = totals.avg_daily_minutes;
    if (avg < lo) {
      tips.push({
        key: 'below_range', severity: 'watch',
        title: `Averaging ${fmtHm(avg)} a day — below the ${guidance.recommended_label}`,
        detail: `For ${guidance.age_label} the consensus range is ${guidance.recommended_label}. Short-changed daytime sleep often shows up as a harder bedtime, so an earlier bedtime is usually the first lever, not a later one.`,
        source: guidance.source,
      });
    } else if (avg > hi) {
      tips.push({
        key: 'above_range', severity: 'info',
        title: `Averaging ${fmtHm(avg)} a day — above the ${guidance.recommended_label}`,
        detail: 'Plenty of babies simply need more sleep than the range. Worth a mention at the next check-up only if it came with a sudden change in feeding or alertness.',
        source: guidance.source,
      });
    } else {
      tips.push({
        key: 'in_range', severity: 'info',
        title: `Averaging ${fmtHm(avg)} a day — inside the ${guidance.recommended_label}`,
        detail: `That is where ${guidance.age_label.toLowerCase()} is expected to land. Nothing to change.`,
        source: guidance.source,
      });
    }
  } else if (guidance?.note) {
    tips.push({ key: 'no_consensus', severity: 'info', title: guidance.age_label, detail: guidance.note, source: guidance.source });
  }

  // Bedtime consistency — the single most actionable lever in the literature.
  if (bedtime && totals.nights_logged >= 3) {
    const spread = Math.round(bedtime.spread);
    if (spread >= 45) {
      tips.push({
        key: 'bedtime_variable', severity: 'watch',
        title: `Bedtime moves around by about ${spread} minutes`,
        detail: `Nights ranged from ${fmtClock(bedtime.earliest)} to ${fmtClock(bedtime.latest)}. A consistent bedtime and a short, same-order routine is the change with the most evidence behind it — the benefit scales with how many nights you manage it.`,
        source: 'Mindell et al. 2015 — bedtime routine dose-response (n=10,085)',
      });
    } else if (spread <= 20) {
      tips.push({
        key: 'bedtime_consistent', severity: 'info',
        title: `Bedtime is steady, within about ${spread} minutes`,
        detail: `Averaging ${fmtClock(bedtime.average)}. Consistency like that is exactly what the bedtime-routine research points to — keep it.`,
        source: 'Mindell et al. 2015 — bedtime routine dose-response (n=10,085)',
      });
    }
  }

  // Night wakings, and whether they are getting worse.
  if (totals.avg_wakings != null && totals.avg_wakings >= 3) {
    tips.push({
      key: 'wakings_high', severity: 'watch',
      title: `About ${totals.avg_wakings} wakings a night`,
      detail: days_old != null && days_old < 120
        ? 'Normal at this age — night waking is developmentally expected before ~4 months, and formal sleep training is not recommended yet. Focus on day/night rhythm and putting down drowsy but awake.'
        : 'If this is new, teething, illness, or a developmental leap are the usual suspects and it typically settles in a week or two. If it is the steady state, the guided program covers the methods with the strongest evidence.',
    });
  }

  // Nap count against the age band.
  if (napBand && totals.avg_naps_per_day != null && totals.days_logged >= 3) {
    const naps = totals.avg_naps_per_day;
    if (naps < napBand.min - 0.5) {
      tips.push({
        key: 'naps_low', severity: 'info',
        title: `Averaging ${naps} nap${naps === 1 ? '' : 's'} a day — typical is ${napBand.label}`,
        detail: 'Either some naps are going unlogged, or a nap is being dropped. If bedtime has become a fight, an overtired baby is the more likely explanation than a baby who needs less sleep.',
      });
    } else if (naps > napBand.max + 0.5) {
      tips.push({
        key: 'naps_high', severity: 'info',
        title: `Averaging ${naps} naps a day — typical is ${napBand.label}`,
        detail: 'Frequent short naps at this age often mean the wake window before each one is a little short. Stretching it by 15 minutes is the usual first thing to try.',
      });
    }
  }

  // Week-over-week movement, once there is a prior week to compare with.
  if (trend != null && Math.abs(trend) >= 30) {
    const better = trend > 0;
    tips.push({
      key: 'trend', severity: better ? 'info' : 'watch',
      title: `${better ? 'Up' : 'Down'} about ${fmtHm(Math.abs(Math.round(trend)))} a day versus last week`,
      detail: better
        ? 'Whatever changed last week, it is working.'
        : 'A dip for a few days around teething, travel, or illness is ordinary. If it holds for more than a week or two, it is worth raising at the next check-up.',
    });
  }

  return tips;
}

// ---------------------------------------------------------------------------
// Night-waking analysis
// ---------------------------------------------------------------------------
//
// `compute` above answers "how much sleep". This answers "what is going wrong,
// and does it track anything we control" — the questions a parent standing in a
// dark hallway at 4am actually has.
//
// The raw material is already in the log: a disturbed night is recorded as
// SEVERAL night_sleep segments (bedtime, then each resettle), so the gap between
// one segment's end and the next one's start IS a waking, with a clock time and
// a length. Nothing new has to be logged for any of this to work.
//
// Two honesty rules carry over from buildTips:
//   1. A pattern must clear a stated threshold before it is named.
//   2. Everything reported carries the observed numbers behind it, so a parent
//      (or the concierge) can see why it was said and disagree.

// Wakings this close together are one unsettled stretch, not two events.
const CLUSTER_RADIUS_MIN = 45;
// Below this a "pattern" is just two coincidental nights.
const MIN_CLUSTER_NIGHTS = 3;
// A correlate has to move by this much before it is worth a parent's attention.
const MEANINGFUL_DELTA_MIN = 20;

// Night-time clock arithmetic runs on a noon-to-noon day: 4am is LATE in the
// night that began at 7pm, not thirteen hours earlier the same morning.
const noonAnchored = (m) => (m == null ? null : (m < 720 ? m + 1440 : m));

const median = (xs) => {
  if (!xs.length) return null;
  const s = [...xs].sort((a, b) => a - b);
  const mid = Math.floor(s.length / 2);
  return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
};

// Calendar days between two YYYY-MM-DD dates, UTC-anchored so it can't wobble.
function daysBetween(a, b) {
  const at = Date.parse(`${a}T00:00:00Z`), bt = Date.parse(`${b}T00:00:00Z`);
  if (Number.isNaN(at) || Number.isNaN(bt)) return null;
  return Math.round((bt - at) / 86400000);
}

/**
 * Reduce the entries to one record per night: its segments, the wakings between
 * them, and the daytime that preceded it. `night.date` is the entry_date the
 * night was filed under — the evening it started.
 */
function buildNights(entries, { today = null, windowDays = 14 } = {}) {
  const sleeps = (entries || [])
    .filter(e => e.entry_type === 'nap' || e.entry_type === 'night_sleep')
    .map(e => {
      const v = parseValue(e) || {};
      return {
        type: e.entry_type,
        date: e.entry_date,
        minutes: Number.isFinite(v.duration_minutes) ? v.duration_minutes : null,
        startMin: minutesOfDay(v.sleep_start),
        endMin: minutesOfDay(v.sleep_end),
        endDay: dayOf(v.sleep_end),
        wakeCount: Number.isFinite(v.wake_count) ? v.wake_count : null,
        notes: e.notes || null,
        inProgress: !!v.in_progress,
      };
    })
    .filter(s => !s.inProgress && s.minutes != null && s.minutes > 0);

  const nightDates = [...new Set(sleeps.filter(s => s.type === 'night_sleep').map(s => s.date))]
    .sort().reverse()
    .filter(d => !today || d <= today)
    .slice(0, windowDays);

  return nightDates.map(date => {
    const segments = sleeps
      .filter(s => s.type === 'night_sleep' && s.date === date && s.startMin != null && s.endMin != null)
      .sort((a, b) => noonAnchored(a.startMin) - noonAnchored(b.startMin));

    // Gaps between consecutive segments are the wakings. A segment logged with
    // wake_count but no companion segment tells us a waking happened without
    // saying when — kept separately so it can be counted but never plotted.
    const wakings = [];
    for (let i = 0; i < segments.length - 1; i++) {
      const wokeAt = segments[i].endMin;
      const backAt = segments[i + 1].startMin;
      let awake = noonAnchored(backAt) - noonAnchored(wokeAt);
      if (awake < 0) awake += 1440;
      wakings.push({ at_minutes: wokeAt, at: fmtClock(wokeAt), awake_minutes: Math.round(awake) });
    }
    const countedWakings = segments.reduce((a, s) => a + (s.wakeCount || 0), 0);

    // Naps belonging to this night's daytime: the ones logged on the same day,
    // which is the day that ran INTO this bedtime.
    const naps = sleeps.filter(s => s.type === 'nap' && s.date === date);
    const lastNapEnd = naps.length
      ? naps.reduce((latest, n) => (n.endMin != null && (latest == null || n.endMin > latest) ? n.endMin : latest), null)
      : null;
    const bedtime = segments.length ? segments[0].startMin : null;
    const morningWake = segments.length ? segments[segments.length - 1].endMin : null;

    return {
      date,
      bedtime_minutes: bedtime,
      bedtime: bedtime == null ? null : fmtClock(bedtime),
      morning_wake_minutes: morningWake,
      morning_wake: morningWake == null ? null : fmtClock(morningWake),
      night_minutes: segments.reduce((a, s) => a + s.minutes, 0),
      nap_minutes: naps.reduce((a, s) => a + s.minutes, 0),
      nap_count: naps.length,
      last_nap_end_minutes: lastNapEnd,
      last_nap_end: lastNapEnd == null ? null : fmtClock(lastNapEnd),
      // The awake stretch between the last nap and lights-out — the lever most
      // often behind both bedtime battles and 4am wake-ups.
      pre_bed_window_minutes: (lastNapEnd != null && bedtime != null)
        ? Math.max(0, noonAnchored(bedtime) - noonAnchored(lastNapEnd)) : null,
      wakings,
      // Timed gaps are the truth when we have them; a bare wake_count is the
      // fallback for nights logged as one entry with a count on it.
      waking_count: wakings.length || countedWakings,
      timed: wakings.length > 0,
    };
  });
}

/**
 * The tightest band of clock time that catches the most wakings. Sliding window
 * over noon-anchored minutes, so a 23:50 waking and a 00:20 one land together.
 */
function findCluster(nights) {
  const points = [];
  for (const n of nights) {
    for (const w of n.wakings) points.push({ date: n.date, anchored: noonAnchored(w.at_minutes), ...w });
  }
  if (points.length < MIN_CLUSTER_NIGHTS) return null;

  points.sort((a, b) => a.anchored - b.anchored);
  let best = null;
  for (const centre of points) {
    const inBand = points.filter(p => Math.abs(p.anchored - centre.anchored) <= CLUSTER_RADIUS_MIN);
    const nightsHit = new Set(inBand.map(p => p.date));
    // Rank by nights covered, not wakings — five wakings on one bad night is
    // not a pattern, three wakings on three nights is.
    if (!best || nightsHit.size > best.nightsHit.size ||
        (nightsHit.size === best.nightsHit.size && inBand.length > best.inBand.length)) {
      best = { inBand, nightsHit };
    }
  }
  if (!best || best.nightsHit.size < MIN_CLUSTER_NIGHTS) return null;

  const centreAnchored = median(best.inBand.map(p => p.anchored));
  const lo = Math.min(...best.inBand.map(p => p.anchored));
  const hi = Math.max(...best.inBand.map(p => p.anchored));
  const unwrap = (m) => ((Math.round(m) % 1440) + 1440) % 1440;
  return {
    typical_time: fmtClock(unwrap(centreAnchored)),
    typical_time_minutes: unwrap(centreAnchored),
    earliest: fmtClock(unwrap(lo)),
    latest: fmtClock(unwrap(hi)),
    nights_affected: best.nightsHit.size,
    nights_logged: nights.length,
    waking_count: best.inBand.length,
    median_awake_minutes: Math.round(median(best.inBand.map(p => p.awake_minutes)) || 0),
    dates: [...best.nightsHit].sort(),
  };
}

/**
 * Does the cluster land on alternating nights? Runs over the consecutive
 * calendar nights that were actually logged — a gap in logging breaks the
 * chain rather than being guessed at, because "every second night" is a claim
 * about consecutive nights and nothing else.
 */
function detectRhythm(nights, cluster) {
  if (!cluster || nights.length < 5) return null;
  const hit = new Set(cluster.dates);
  const ordered = [...nights].map(n => n.date).sort();

  let pairs = 0, alternating = 0, sameRun = 0;
  for (let i = 0; i < ordered.length - 1; i++) {
    if (daysBetween(ordered[i], ordered[i + 1]) !== 1) continue; // logging gap
    pairs++;
    if (hit.has(ordered[i]) !== hit.has(ordered[i + 1])) alternating++;
    else sameRun++;
  }
  if (pairs < 4) return null;

  const ratio = alternating / pairs;
  if (ratio >= 0.75) {
    return {
      pattern: 'alternating',
      label: 'roughly every second night',
      consecutive_pairs: pairs,
      alternating_pairs: alternating,
      confidence: ratio >= 0.9 ? 'high' : 'moderate',
      detail: `Of ${pairs} back-to-back night pairs, ${alternating} flipped between a disturbed night and a settled one.`,
    };
  }
  if (ratio <= 0.25 && cluster.nights_affected >= Math.ceil(nights.length * 0.7)) {
    return {
      pattern: 'nightly',
      label: 'most nights',
      consecutive_pairs: pairs,
      alternating_pairs: alternating,
      confidence: 'high',
      detail: `${cluster.nights_affected} of the last ${nights.length} logged nights had a waking in this window.`,
    };
  }
  return {
    pattern: 'irregular',
    label: 'some nights, with no clear rhythm',
    consecutive_pairs: pairs,
    alternating_pairs: alternating,
    confidence: 'low',
    detail: `${cluster.nights_affected} of ${nights.length} nights, without a consistent on/off pattern.`,
  };
}

/**
 * What was different about the disturbed nights. Compares the median of each
 * daytime factor on nights inside the cluster against nights outside it, and
 * reports only the factors that moved by a meaningful margin.
 *
 * This is a correlation over a handful of nights, never a cause, and every
 * consumer of this data is required to say so.
 */
function compareNights(nights, cluster) {
  if (!cluster) return [];
  const hit = new Set(cluster.dates);
  const disturbed = nights.filter(n => hit.has(n.date));
  const settled = nights.filter(n => !hit.has(n.date));
  if (disturbed.length < 2 || settled.length < 2) return [];

  // `label` heads a row of UI; `phrase` is the same factor in sentence form, so
  // a recommendation can say "tracks when the last nap ends" rather than the
  // ungrammatical "tracks last nap ended".
  const FACTORS = [
    { key: 'bedtime', label: 'Bedtime', phrase: 'bedtime', lever: 'bedtime',
      pick: n => n.bedtime_minutes, clock: true, later: 'later', earlier: 'earlier' },
    { key: 'nap_minutes', label: 'Daytime sleep', phrase: 'how much daytime sleep he gets',
      lever: 'the amount of daytime sleep', pick: n => (n.nap_count ? n.nap_minutes : null),
      later: 'more', earlier: 'less' },
    { key: 'pre_bed_window_minutes', label: 'Awake stretch before bed',
      phrase: 'the awake stretch before bed', lever: 'the awake stretch before bed',
      pick: n => n.pre_bed_window_minutes, later: 'longer', earlier: 'shorter' },
    { key: 'last_nap_end', label: 'Last nap ended', phrase: 'when the last nap ends',
      lever: 'the time the last nap ends', pick: n => n.last_nap_end_minutes, clock: true,
      later: 'later', earlier: 'earlier' },
  ];

  const out = [];
  for (const f of FACTORS) {
    const d = median(disturbed.map(f.pick).filter(v => v != null));
    const s = median(settled.map(f.pick).filter(v => v != null));
    if (d == null || s == null) continue;
    const delta = Math.round(d - s);
    if (Math.abs(delta) < MEANINGFUL_DELTA_MIN) continue;
    out.push({
      key: f.key,
      label: f.label,
      phrase: f.phrase,
      lever: f.lever,
      disturbed_value: f.clock ? fmtClock(d) : fmtHm(d),
      settled_value: f.clock ? fmtClock(s) : fmtHm(s),
      delta_minutes: delta,
      direction: delta > 0 ? f.later : f.earlier,
      summary: `${f.label} was ${fmtHm(Math.abs(delta))} ${delta > 0 ? f.later : f.earlier} on the disturbed nights (${f.clock ? fmtClock(d) : fmtHm(d)} vs ${f.clock ? fmtClock(s) : fmtHm(s)}).`,
    });
  }
  // Biggest mover first — it is the one worth trying to change.
  return out.sort((a, b) => Math.abs(b.delta_minutes) - Math.abs(a.delta_minutes));
}

/**
 * The whole night-waking picture: per-night detail, the dominant waking window,
 * whether it has a rhythm, and what differs on the nights it happens.
 */
function analyzeWakings(entries, { birthdate = null, today = null, windowDays = 14 } = {}) {
  const nights = buildNights(entries, { today, windowDays });
  const timedNights = nights.filter(n => n.timed);
  const cluster = findCluster(nights);
  const rhythm = detectRhythm(nights, cluster);

  const totalWakings = nights.reduce((a, n) => a + n.waking_count, 0);
  return {
    window_days: windowDays,
    nights_analyzed: nights.length,
    nights_with_timed_wakings: timedNights.length,
    total_wakings: totalWakings,
    // Averaged over nights we can actually see inside, so a night logged as one
    // block doesn't read as a flawless night.
    avg_wakings_per_night: timedNights.length
      ? Math.round((timedNights.reduce((a, n) => a + n.wakings.length, 0) / timedNights.length) * 10) / 10
      : null,
    cluster,
    rhythm,
    differences: compareNights(nights, cluster),
    nights: nights.map(n => ({
      date: n.date, bedtime: n.bedtime, morning_wake: n.morning_wake,
      night_minutes: n.night_minutes, nap_minutes: n.nap_minutes, nap_count: n.nap_count,
      last_nap_end: n.last_nap_end, pre_bed_window_minutes: n.pre_bed_window_minutes,
      waking_count: n.waking_count,
      wakings: n.wakings.map(w => ({ at: w.at, awake_minutes: w.awake_minutes })),
    })),
    // Said everywhere this surfaces. A handful of nights cannot establish cause,
    // and a parent deserves to be told that before they change anything.
    basis: 'Patterns observed in your own log over the last ' + windowDays + ' nights. Correlation across a handful of nights, not a cause — and not medical advice.',
  };
}

// ---------------------------------------------------------------------------
// Recommendations — "what to try tonight"
// ---------------------------------------------------------------------------
//
// buildTips describes what the data says. This proposes what to CHANGE, which
// is a higher bar, so the rules are stricter:
//
//   1. A recommendation must be earned by a specific observation, and it states
//      that observation in `because` — a parent can check our work.
//   2. Every lever names the evidence behind it. Where the evidence is a rule of
//      thumb rather than the AASM/AAP consensus, it says so in `strength`.
//   3. They are ordered by how much the data supports them, and capped, because
//      a list of twelve things to try is a list of nothing to try.
//   4. Nothing here is medical advice, and a red-flag pattern routes to a
//      pediatrician instead of to another lever.

const EVIDENCE = {
  routine: { source: 'Mindell et al. 2015 — bedtime routine dose-response (n=10,085)', strength: 'strong' },
  extinction: { source: 'Gradisar et al. 2016, Pediatrics — RCT of graduated extinction & bedtime fading', strength: 'strong' },
  review: { source: 'Mindell et al. 2006 — AASM review of behavioural sleep interventions', strength: 'strong' },
  duration: { source: 'AASM child sleep-duration consensus (AAP-endorsed)', strength: 'strong' },
  safe_sleep: { source: 'AAP 2022 Safe Sleep Policy Statement', strength: 'strong' },
  wake_windows: { source: 'Typical wake windows in pediatric sleep guidance', strength: 'rule of thumb' },
  practice: { source: 'Common pediatric sleep guidance (NHS)', strength: 'rule of thumb' },
};

const EARLY_MORNING_FROM = 4 * 60;   // 4:00am
const EARLY_MORNING_TO = 6 * 60;     // 6:00am
const SPLIT_NIGHT_AWAKE_MIN = 45;    // awake this long mid-night = a split night

/**
 * @param stats     the output of compute()
 * @param analysis  the output of analyzeWakings()
 * @param opts.birthdate  drives the age gate on formal training
 * @param opts.maxItems   how many to return (default 4)
 */
function recommend(stats, analysis, { birthdate = null, maxItems = 4 } = {}) {
  const out = [];
  const days_old = birthdate ? ageInDays(birthdate) : null;
  const cluster = analysis?.cluster || null;
  const rhythm = analysis?.rhythm || null;
  const diffs = analysis?.differences || [];
  const byKey = (k) => diffs.find(d => d.key === k);
  const totals = stats?.totals || {};
  const guidance = stats?.guidance || null;

  // Nothing to recommend from nothing. Say what would unlock it instead of
  // inventing advice.
  if (!analysis || analysis.nights_analyzed < 3) {
    return {
      items: [],
      note: 'A few more logged nights — ideally with each resettle logged, not just the bedtime — and this turns into specific things to try.',
    };
  }

  // -- Under 4 months: the answer is not a technique. ------------------------
  if (days_old != null && days_old < 113) {
    out.push({
      key: 'too_young',
      priority: 100,
      title: 'Rhythm rather than training, at this age',
      because: `${analysis.nights_analyzed} nights logged at ${Math.floor(days_old / 7)} weeks old.`,
      what_to_try: [
        'Keep night feeds quiet, dim, and boring; keep days bright and social.',
        'Put down drowsy-but-awake when you can — practice, not a programme.',
        'Follow tired cues rather than the clock.',
      ],
      ...EVIDENCE.practice,
      note: 'Night waking is developmentally expected before ~4 months, and formal sleep training is not recommended yet.',
    });
  }

  const inEarlyMorning = cluster &&
    cluster.typical_time_minutes >= EARLY_MORNING_FROM &&
    cluster.typical_time_minutes < EARLY_MORNING_TO;

  // -- The early-morning waking, which is its own problem. -------------------
  // By 4–6am sleep pressure is nearly spent, so the levers are different from
  // the ones for a 1am waking: light, noise, and how the wake is handled matter
  // far more, and going in quickly teaches the wake to stick.
  if (inEarlyMorning && cluster.nights_affected >= MIN_CLUSTER_NIGHTS) {
    const tooMuchDay = guidance?.recommended_max_minutes && totals.avg_daily_minutes != null &&
      totals.avg_daily_minutes > guidance.recommended_max_minutes;
    out.push({
      key: 'early_morning_waking',
      priority: 90,
      title: `Treat the ${cluster.typical_time} waking as an early-morning waking, not a night waking`,
      because: `Wakings cluster at ${cluster.typical_time} (${cluster.earliest}–${cluster.latest}) on ${cluster.nights_affected} of ${cluster.nights_logged} logged nights.`,
      what_to_try: [
        'Make the room properly dark and keep it dark until your chosen "morning" time — dawn light is the usual culprit at this hour.',
        'Hold the same response you would use at midnight: by 4am there is little sleep pressure left, so a quick start to the day teaches the waking to repeat.',
        'Keep the get-up time fixed even after a bad night, so the body clock has something stable to lock onto.',
        tooMuchDay
          ? 'Daytime sleep is above the age range — trimming the last nap slightly may push the morning later.'
          : 'White noise through the early hours covers the household and street noise that lands right at this time.',
      ],
      ...EVIDENCE.practice,
    });
  }

  // -- The alternating rhythm: the thing the parent actually noticed. --------
  if (rhythm?.pattern === 'alternating') {
    const driver = diffs[0];
    out.push({
      key: 'alternating_pattern',
      priority: 95,
      title: driver
        ? `The every-second-night pattern tracks ${driver.phrase}`
        : 'The every-second-night pattern looks like a swing, not a habit',
      because: driver
        ? `${rhythm.detail} ${driver.summary}`
        : rhythm.detail,
      what_to_try: driver
        ? [
            `Hold ${driver.lever} steady for a week — match the settled nights (${driver.settled_value}), not the average.`,
            'Change one thing only, and give it 5–7 nights before judging it. Two changes at once tell you nothing.',
            'Keep logging each resettle so the next week can be compared against this one.',
          ]
        : [
            'Log the day before each night — nap timing especially — so the swing has something to be matched against.',
            'Hold bedtime and the wind-down identical for a week; an alternating pattern often flattens once the day stops alternating.',
          ],
      ...EVIDENCE.routine,
      note: 'An alternating rhythm usually means something in the day alternates too — a nap that happens on nursery days but not at home is the classic one.',
    });
  }

  // -- Split night: awake for a long stretch in the middle. ------------------
  if (cluster && cluster.median_awake_minutes >= SPLIT_NIGHT_AWAKE_MIN && !inEarlyMorning) {
    out.push({
      key: 'split_night',
      priority: 80,
      title: `Awake about ${fmtHm(cluster.median_awake_minutes)} in the middle of the night`,
      because: `The ${cluster.typical_time} waking lasts a median of ${fmtHm(cluster.median_awake_minutes)} before sleep returns.`,
      what_to_try: [
        'A long, wide-awake, content stretch usually means there is more sleep in the 24 hours than is needed — trim daytime sleep or push bedtime 15–20 minutes later rather than earlier.',
        'Keep the stretch boring and dark; stimulation at this point extends it.',
      ],
      ...EVIDENCE.practice,
    });
  }

  // -- Bedtime consistency: the strongest evidence in the whole feature. -----
  const spread = stats?.bedtime?.spread_minutes;
  if (spread != null && spread >= 45) {
    out.push({
      key: 'steady_bedtime',
      priority: 88,
      title: `Pin the bedtime — it currently moves by about ${spread} minutes`,
      because: `Bedtimes ranged ${stats.bedtime.earliest} to ${stats.bedtime.latest} across ${totals.nights_logged} nights.`,
      what_to_try: [
        `Pick one time near ${stats.bedtime.average} and hold it within 15 minutes every night, weekends included.`,
        'Keep the wind-down short and in the same order every night — the order matters as much as the length.',
      ],
      ...EVIDENCE.routine,
      note: 'This is the single best-evidenced change available, and its benefit scales with how many nights you manage it.',
    });
  }

  // -- Pre-bed wake window, when the log shows it is off the typical band. ---
  const window = wakeWindowForBirthdate(birthdate);
  const preBed = byKey('pre_bed_window_minutes');
  if (window && preBed) {
    const disturbedLonger = preBed.delta_minutes > 0;
    out.push({
      key: 'pre_bed_window',
      priority: 70,
      title: disturbedLonger
        ? 'The awake stretch before bed runs longer on the disturbed nights'
        : 'The awake stretch before bed runs shorter on the disturbed nights',
      because: preBed.summary,
      what_to_try: disturbedLonger
        ? [
            `Aim for ${window.label} awake before bed — an overtired bedtime tends to fragment the second half of the night.`,
            'If the last nap ends late, cap it rather than letting bedtime drift.',
          ]
        : [
            `Aim for ${window.label} awake before bed — too little awake time makes the first stretch short and the middle of the night busy.`,
            'Stretching the final wake window by 15 minutes at a time is the usual way to do this.',
          ],
      ...EVIDENCE.wake_windows,
    });
  }

  // -- Total sleep against the consensus range. ------------------------------
  if (guidance?.recommended_min_minutes && totals.avg_daily_minutes != null &&
      totals.avg_daily_minutes < guidance.recommended_min_minutes) {
    out.push({
      key: 'below_range',
      priority: 75,
      title: `Total sleep is under the ${guidance.recommended_label}`,
      because: `Averaging ${fmtHm(totals.avg_daily_minutes)} a day over ${totals.days_logged} logged days.`,
      what_to_try: [
        'Move bedtime 15 minutes earlier every few nights until the total lands in range — an earlier bedtime is usually the first lever, not a later one.',
        'Protect the naps that are still happening; lost daytime sleep rarely improves the night.',
      ],
      ...EVIDENCE.duration,
    });
  }

  // -- A named method, once they are old enough for one. ---------------------
  // Only offered when the log shows a persistent problem, so it can't read as
  // "your baby sleeps fine, here's a training programme anyway".
  if (days_old != null && days_old >= 113 && cluster && cluster.nights_affected >= 3) {
    const phase = guidanceForBirthdate(birthdate)?.current_phase;
    const method = phase?.method;
    if (method) {
      out.push({
        key: 'method',
        priority: 60,
        title: `If it persists, ${method.name.toLowerCase()} is the fit for this age`,
        because: `A waking around ${cluster.typical_time} on ${cluster.nights_affected} of ${cluster.nights_logged} nights, at ${phase.age_label}.`,
        what_to_try: [
          method.summary,
          'Pick ONE method and hold it consistently for 1–2 weeks — inconsistency is what prolongs the crying.',
          'Talk to your pediatrician first, and stop if your child is unwell.',
        ],
        ...EVIDENCE.extinction,
        method_key: method.key,
        note: 'Behavioural methods have the strongest evidence base here, including 5-year follow-up showing no long-term harm (Price et al. 2012).',
      });
    }
  }

  // -- Worth a doctor, not another lever. -----------------------------------
  // Deliberately not framed as alarming: it names the observation and points at
  // the person qualified to interpret it.
  if (totals.avg_wakings != null && totals.avg_wakings >= 5 && days_old != null && days_old >= 183) {
    out.push({
      key: 'check_in',
      priority: 99,
      title: 'Worth mentioning at the next check-up',
      because: `About ${totals.avg_wakings} wakings a night at this age.`,
      what_to_try: [
        'Frequent waking that does not respond to routine changes is worth a conversation — reflux, allergy, apnoea, and iron levels are the usual things a doctor will want to rule out.',
        'Bring this log with you; the nightly pattern is more useful to them than a summary.',
      ],
      ...EVIDENCE.safe_sleep,
    });
  }

  const items = out.sort((a, b) => b.priority - a.priority).slice(0, maxItems)
    .map(({ priority, ...rest }) => rest);

  return {
    items,
    note: items.length
      ? 'Earned from your own log and the sources named on each item. Educational guidance, not medical advice — change one thing at a time and give it 5–7 nights.'
      : 'Nothing in the log stands out as worth changing right now.',
  };
}

// Builds a sleep span from a date + two HH:MM times. An end at or before the
// start means it ran past midnight, so the end lands on the next day — the
// normal case for a night sleep. Shared by the API routes and the concierge so
// the two can never disagree about what "7:30pm to 6:45am" means.
function span(date, startTime, endTime) {
  const parse = (t) => {
    const m = /^(\d{1,2}):(\d{2})$/.exec(String(t || '').trim());
    if (!m) return null;
    const h = parseInt(m[1]), min = parseInt(m[2]);
    return (h >= 0 && h < 24 && min >= 0 && min < 60) ? { h, min } : null;
  };
  const s = parse(startTime), e = parse(endTime);
  if (!s || !e || !/^\d{4}-\d{2}-\d{2}$/.test(date)) return null;
  const at = (t) => {
    const d = new Date(`${date}T00:00:00Z`);
    d.setUTCMinutes(d.getUTCMinutes() + t.h * 60 + t.min);
    return d;
  };
  const startAt = at(s), endAt = at(e);
  if (endAt <= startAt) endAt.setUTCDate(endAt.getUTCDate() + 1);
  const stamp = (d) => `${d.toISOString().slice(0, 10)} ${String(d.getUTCHours()).padStart(2, '0')}:${String(d.getUTCMinutes()).padStart(2, '0')}`;
  const pad = (v) => String(v).padStart(2, '0');
  return {
    start: stamp(startAt), end: stamp(endAt),
    startTime: `${pad(s.h)}:${pad(s.min)}`, endTime: `${pad(e.h)}:${pad(e.min)}`,
    minutes: Math.round((endAt - startAt) / 60000),
  };
}

// When the next sleep is likely due, based on when they last woke and the
// typical wake window for their age. Returns null unless there is both a
// birthdate to reason from and a finished sleep to measure from — a guess with
// nothing behind it is worse than no guess.
//
// `prepare_at` is deliberately the START of the window minus a short lead: the
// useful nudge is "start winding down", not "they are already overtired".
function nextSleepWindow(entries, { birthdate = null, leadMinutes = 15 } = {}) {
  const window = wakeWindowForBirthdate(birthdate);
  if (!window) return null;

  // The most recent sleep that has actually ended — nap or night. Counting
  // only from last night's wake made Home say "awake 4h" through a logged
  // morning nap, then fall back to bedtime once that first-nap window closed.
  let latest = null;
  for (const e of entries || []) {
    if (e.entry_type !== 'nap' && e.entry_type !== 'night_sleep') continue;
    const v = parseValue(e) || {};
    if (v.in_progress || !v.sleep_end) continue;
    const endedAt = parseSleepStamp(v.sleep_end);
    if (endedAt == null) continue;
    if (!latest || endedAt > latest.endedAt) latest = { endedAt, type: e.entry_type };
  }
  if (!latest) return null;

  const at = (mins) => latest.endedAt + mins * 60000;

  return {
    last_wake_at: formatSleepStamp(latest.endedAt),
    last_sleep_type: latest.type,
    wake_window_label: window.label,
    wake_window_min_minutes: window.min_minutes,
    wake_window_max_minutes: window.max_minutes,
    due_from: formatSleepStamp(at(window.min_minutes)),
    due_by: formatSleepStamp(at(window.max_minutes)),
    prepare_at: formatSleepStamp(at(Math.max(0, window.min_minutes - leadMinutes))),
    lead_minutes: leadMinutes,
    // Said plainly wherever this surfaces: this is a rule of thumb, not the
    // AASM/AAP consensus the duration ranges come from.
    basis: 'Typical wake windows used in pediatric sleep guidance — a rule of thumb, not a consensus standard.',
  };
}

// When to start the bedtime routine, from the bedtime they actually keep. Needs
// a few nights before it will say anything — one early night would otherwise
// drag the reminder to a time that isn't their bedtime at all.
//
// This one IS grounded: the bedtime-routine dose-response study is the strongest
// evidence in the whole feature, and it is about consistency, which is exactly
// what a nightly reminder supports.
function bedtimePrep(stats, { leadMinutes = 30, minNights = 3 } = {}) {
  const avg = stats?.bedtime?.average_minutes;
  const nights = stats?.totals?.nights_logged ?? 0;
  if (avg == null || nights < minNights) return null;

  const startAt = ((Math.round(avg) - leadMinutes) % 1440 + 1440) % 1440;
  const pad = (v) => String(v).padStart(2, '0');
  return {
    start_time: `${pad(Math.floor(startAt / 60))}:${pad(startAt % 60)}`,
    bedtime: stats.bedtime.average,
    lead_minutes: leadMinutes,
    based_on_nights: nights,
    spread_minutes: stats.bedtime.spread_minutes ?? null,
    basis: 'Based on the bedtime you actually keep. A consistent, same-order routine is the change with the most evidence behind it (Mindell et al. 2015, n=10,085).',
  };
}

module.exports = {
  compute, span, nextSleepWindow, bedtimePrep, analyzeWakings, recommend,
  DURATION_BANDS, NAP_BANDS, fmtHm, fmtClock,
};
