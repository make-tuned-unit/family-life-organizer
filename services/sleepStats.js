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

const { ageInDays, wakeWindowForBirthdate } = require('./sleepTraining');

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

// "yyyy-MM-dd HH:mm" -> minutes since midnight, or null.
function minutesOfDay(stamp) {
  const m = /^\d{4}-\d{2}-\d{2} (\d{2}):(\d{2})$/.exec(String(stamp || ''));
  return m ? parseInt(m[1]) * 60 + parseInt(m[2]) : null;
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

  // The most recent sleep that has actually ended.
  let latest = null;
  for (const e of entries || []) {
    if (e.entry_type !== 'nap' && e.entry_type !== 'night_sleep') continue;
    const v = parseValue(e) || {};
    if (v.in_progress || !v.sleep_end) continue;
    const endedAt = new Date(`${String(v.sleep_end).replace(' ', 'T')}:00`);
    if (isNaN(endedAt)) continue;
    if (!latest || endedAt > latest.endedAt) latest = { endedAt, type: e.entry_type };
  }
  if (!latest) return null;

  const at = (mins) => new Date(latest.endedAt.getTime() + mins * 60000);
  const dueFrom = at(window.min_minutes);
  const prepare = at(Math.max(0, window.min_minutes - leadMinutes));
  const stamp = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')} ${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;

  return {
    last_wake_at: stamp(latest.endedAt),
    last_sleep_type: latest.type,
    wake_window_label: window.label,
    wake_window_min_minutes: window.min_minutes,
    wake_window_max_minutes: window.max_minutes,
    due_from: stamp(dueFrom),
    due_by: stamp(at(window.max_minutes)),
    prepare_at: stamp(prepare),
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

module.exports = { compute, span, nextSleepWindow, bedtimePrep, DURATION_BANDS, NAP_BANDS, fmtHm, fmtClock };
