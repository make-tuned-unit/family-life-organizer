// Menstrual-cycle prediction for a `period` routine — two modes: plain period
// tracking, and trying-to-conceive (TTC) fertility estimation.
//
// Grounded in ACOG / NHS / Cleveland Clinic / NICHD guidance and Wilcox 1995
// (NEJM, the 6-day fertile window). The load-bearing facts:
//   • Cycle Day 1 = first day of full flow. Normal cycle 21–35 days, period 3–7.
//   • The LUTEAL phase is ~14 days and relatively fixed; the FOLLICULAR phase is
//     the variable part. So ovulation ≈ (next period − 14), NOT (last period + 14)
//     — otherwise every non-28-day cycle is wrong.
//   • Fertile window ≈ ovulation − 5 days … ovulation + 1 day (sperm ~5d, egg ~1d),
//     widened by the user's own cycle variance; it is a RANGE, never a fixed day.
//   • Need ≥3 cycles for a confident estimate; degrade gracefully below that and
//     for irregular cycles.
//   • This is informational only — NOT contraception, NOT medical advice.

const LUTEAL_LENGTH = 14;         // ~12–14; 14 is the standard default
const DEFAULT_CYCLE = 28;
const DEFAULT_PERIOD = 5;
const NORMAL_MIN = 21, NORMAL_MAX = 35;
const VARIANCE_CAP = 4;           // cap the extra days we widen the window by

const DISCLAIMER =
  'For information only — not medical advice, and not a form of birth control. ' +
  'Predictions are estimates and can be off by several days, especially if your ' +
  'cycles are irregular or you have PCOS, are in perimenopause, are breastfeeding, ' +
  'or recently stopped hormonal birth control. If you\'re trying to conceive, ' +
  'consider seeing a doctor after 12 months of trying (6 months if you\'re 35+). ' +
  'Talk to a clinician about periods that are very irregular, absent, heavy, or painful.';

// ---- date helpers (UTC-midnight day math so results don't wobble by timezone) ----
function toUTC(dateStr) {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(dateStr || ''));
  if (!m) return null;
  const t = Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
  return Number.isNaN(t) ? null : t;
}
function fromUTC(ms) {
  const d = new Date(ms);
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-${String(d.getUTCDate()).padStart(2, '0')}`;
}
function daysBetween(aMs, bMs) { return Math.round((bMs - aMs) / 86400000); }
function addDays(ms, n) { return ms + n * 86400000; }
function mean(xs) { return xs.reduce((s, x) => s + x, 0) / xs.length; }
function stddev(xs) {
  if (xs.length < 2) return 0;
  const m = mean(xs);
  return Math.sqrt(mean(xs.map(x => (x - m) ** 2)));
}

function parseConfig(config) {
  let c = {};
  try { c = typeof config === 'string' ? JSON.parse(config || '{}') : (config || {}); } catch { c = {}; }
  return {
    mode: c.mode === 'ttc' ? 'ttc' : 'period',
    luteal_length: Number.isFinite(c.luteal_length) ? c.luteal_length : LUTEAL_LENGTH,
    avg_cycle_override: Number.isFinite(c.avg_cycle_override) ? c.avg_cycle_override : null,
  };
}

// entries: routine_entries for this routine. todayISO defaults to server-local today.
function predict(entries, config, { todayISO } = {}) {
  const cfg = parseConfig(config);
  const today = toUTC(todayISO) ?? toUTC(new Date().toLocaleDateString('en-CA'));

  const starts = [...new Set((entries || [])
    .filter(e => e && e.entry_type === 'period_start' && toUTC(e.entry_date) != null)
    .map(e => toUTC(e.entry_date)))].sort((a, b) => a - b);

  // Typical period (bleeding) length from start→end pairs, else default.
  const ends = (entries || []).filter(e => e && e.entry_type === 'period_end' && toUTC(e.entry_date) != null)
    .map(e => toUTC(e.entry_date));
  const periodLengths = [];
  for (const s of starts) {
    const nextEnd = ends.filter(x => x >= s && x - s <= 12 * 86400000).sort((a, b) => a - b)[0];
    if (nextEnd != null) periodLengths.push(daysBetween(s, nextEnd) + 1);
  }
  const periodLength = periodLengths.length ? Math.round(mean(periodLengths)) : DEFAULT_PERIOD;

  const base = { mode: cfg.mode, disclaimer: DISCLAIMER, cycles_tracked: Math.max(0, starts.length - 1) };

  if (!starts.length) {
    return { ...base, insufficient: true, note: 'Log the first day of your period to begin.' };
  }

  const lastStart = starts[starts.length - 1];
  const currentCycleDay = Math.max(1, daysBetween(lastStart, today) + 1);

  // Cycle lengths between consecutive starts; keep the last up to 6, drop absurd
  // gaps (a >60-day gap almost always means a period wasn't logged, not a 60-day cycle).
  const allLengths = [];
  for (let i = 1; i < starts.length; i++) allLengths.push(daysBetween(starts[i - 1], starts[i]));
  const recent = allLengths.filter(l => l >= 15 && l <= 60).slice(-6);

  if (recent.length < 1) {
    // Only one period logged (or unusable gaps): show the cycle day, nothing predictive.
    return { ...base, insufficient: true, current_cycle_day: currentCycleDay, period_length: periodLength,
      note: 'A couple more logged periods and we can estimate your next one.' };
  }

  const avgCycle = cfg.avg_cycle_override || Math.round(mean(recent));
  const sd = stddev(recent);
  const irregular = recent.some(l => l < NORMAL_MIN || l > NORMAL_MAX) || avgCycle < NORMAL_MIN || avgCycle > NORMAL_MAX || sd > 9;

  const nextPeriod = addDays(lastStart, avgCycle);
  const daysUntilPeriod = daysBetween(today, nextPeriod);

  // Confidence scales with history depth and variance.
  let confidence;
  if (recent.length < 3 || irregular) confidence = 'low';
  else if (sd <= 2) confidence = 'high';
  else if (sd <= 5) confidence = 'medium';
  else confidence = 'low';

  // Ovulation anchored to the luteal phase (next period − luteal length).
  const widen = Math.min(VARIANCE_CAP, Math.ceil(sd));
  const ovulationCycleDay = avgCycle - cfg.luteal_length;
  const predictedOvulation = addDays(nextPeriod, -cfg.luteal_length);
  const fertileStart = addDays(predictedOvulation, -(5 + widen));
  const fertileEnd = addDays(predictedOvulation, 1 + widen);

  // Current phase (relative to cycle day).
  const fertileStartDay = ovulationCycleDay - (5 + widen);
  const fertileEndDay = ovulationCycleDay + 1 + widen;
  let phase;
  if (currentCycleDay <= periodLength) phase = 'menstrual';
  else if (currentCycleDay >= fertileStartDay && currentCycleDay <= fertileEndDay) {
    phase = (currentCycleDay >= ovulationCycleDay - 1 && currentCycleDay <= ovulationCycleDay + 1) ? 'ovulation' : 'fertile';
  } else if (currentCycleDay < fertileStartDay) phase = 'follicular';
  else phase = 'luteal';

  const out = {
    ...base,
    current_cycle_day: currentCycleDay,
    average_cycle_length: avgCycle,
    cycle_variability_days: Math.round(sd),
    period_length: periodLength,
    next_period_date: fromUTC(nextPeriod),
    days_until_period: daysUntilPeriod,
    is_late: daysUntilPeriod < 0,
    late_by_days: daysUntilPeriod < 0 ? -daysUntilPeriod : 0,
    current_phase: phase,
    confidence,
    irregular,
  };

  // Fertile-window / ovulation surface only in TTC mode, and only with enough
  // history to be even loosely meaningful (≥3 cycles), always as a range.
  if (cfg.mode === 'ttc') {
    if (recent.length >= 3 && !irregular) {
      out.predicted_ovulation_date = fromUTC(predictedOvulation);
      out.fertile_window = { start: fromUTC(fertileStart), end: fromUTC(fertileEnd) };
      // Ogino–Knaus calendar cross-check once ≥6 cycles exist.
      if (recent.length >= 6) {
        out.calendar_window_days = { first: Math.min(...recent) - 18, last: Math.max(...recent) - 11 };
      }
    } else {
      out.fertile_window = null;
      out.fertile_note = irregular
        ? 'Your cycles look irregular, so a fertile-window estimate wouldn\'t be reliable yet. Logging ovulation tests or cervical mucus helps — and a clinician can help too.'
        : 'Log a few more cycles and we can estimate your fertile window.';
    }
  }

  return out;
}

module.exports = { predict, LUTEAL_LENGTH, DISCLAIMER };
